import Foundation
import Network
import Security

enum ServerEvent {
    case page(String)
    case fileStarted(String)
    case fileFinished(String, success: Bool)
    case tlsFailed
}

enum ServerError: LocalizedError {
    case noPort

    var errorDescription: String? {
        switch self {
        case .noPort: return "No se encontró un puerto libre entre 4000 y 8000"
        }
    }
}

private final class Once {
    private let lock = NSLock()
    private var fired = false

    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

/// Tiny HTTP(S) server on Network.framework: serves registered files (streamed, no Range) and HTML pages.
final class LocalServer {
    private let queue = DispatchQueue(label: "infinityx.localserver")
    private var listener: NWListener?
    private var files: [String: URL] = [:]
    private var pages: [String: String] = [:]
    private var usesTLS = false

    /// Called on the main queue.
    var onEvent: ((ServerEvent) -> Void)?

    // MARK: Public

    /// Starts on a random port in 4000...8000 and returns it. `identity` non-nil means HTTPS.
    func start(identity: sec_identity_t?) async throws -> UInt16 {
        stop()
        usesTLS = identity != nil
        for _ in 0..<20 {
            let port = UInt16.random(in: 4000...8000)
            if try await tryStart(port: port, identity: identity) { return port }
        }
        throw ServerError.noPort
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func setFile(path: String, url: URL) {
        queue.async { self.files[path] = url }
    }

    func setPage(path: String, html: String) {
        queue.async { self.pages[path] = html }
    }

    // MARK: Listener

    private func tryStart(port: UInt16, identity: sec_identity_t?) async throws -> Bool {
        let params: NWParameters
        if let identity = identity {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, identity)
            params = NWParameters(tls: tls)
        } else {
            params = NWParameters.tcp
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let newListener = try NWListener(using: params, on: nwPort)
        newListener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        let once = Once()
        let ok: Bool = await withCheckedContinuation { cont in
            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.fire() { cont.resume(returning: true) }
                case .failed:
                    if once.fire() { cont.resume(returning: false) }
                    newListener.cancel()
                default:
                    break
                }
            }
            newListener.start(queue: queue)
        }
        if ok { listener = newListener }
        return ok
    }

    // MARK: Connections

    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                if self?.usesTLS == true {
                    DispatchQueue.main.async { self?.onEvent?(.tlsFailed) }
                }
                conn.cancel()
            }
        }
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            guard let self = self else { conn.cancel(); return }
            var buf = buffer
            if let data = data { buf.append(data) }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headData = buf.subdata(in: buf.startIndex..<range.lowerBound)
                self.respond(conn, head: String(data: headData, encoding: .utf8) ?? "")
            } else if error != nil || isComplete || buf.count > 65536 {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private func respond(_ conn: NWConnection, head: String) {
        let firstLine = head.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return finish(conn) }
        let method = String(parts[0])
        let target = String(parts[1])
        let path = String(target.split(separator: "?", omittingEmptySubsequences: false).first ?? "")
        let headOnly = method == "HEAD"
        guard method == "GET" || headOnly else {
            return sendSimple(conn, status: "405 Method Not Allowed", type: "text/plain", body: "")
        }

        if let html = pages[path] {
            notify(.page(path))
            sendSimple(conn, status: "200 OK", type: "text/html; charset=utf-8", body: headOnly ? "" : html,
                       declaredLength: html.utf8.count)
        } else if let fileURL = files[path] {
            serveFile(conn, path: path, url: fileURL, headOnly: headOnly)
        } else {
            sendSimple(conn, status: "404 Not Found", type: "text/plain", body: "Not found")
        }
    }

    private func serveFile(_ conn: NWConnection, path: String, url: URL, headOnly: Bool) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return sendSimple(conn, status: "500 Internal Server Error", type: "text/plain", body: "Cannot read file")
        }
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(size)\r\nConnection: close\r\n\r\n"
        if !headOnly { notify(.fileStarted(path)) }
        conn.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            guard let self = self else { try? handle.close(); conn.cancel(); return }
            if error != nil || headOnly {
                try? handle.close()
                if !headOnly { self.notify(.fileFinished(path, success: false)) }
                conn.cancel()
                return
            }
            self.stream(conn, handle: handle, path: path)
        })
    }

    private func stream(_ conn: NWConnection, handle: FileHandle, path: String) {
        let chunk = handle.readData(ofLength: 256 * 1024)
        if chunk.isEmpty {
            try? handle.close()
            notify(.fileFinished(path, success: true))
            finish(conn)
            return
        }
        conn.send(content: chunk, completion: .contentProcessed { [weak self] error in
            if error != nil {
                try? handle.close()
                self?.notify(.fileFinished(path, success: false))
                conn.cancel()
                return
            }
            self?.stream(conn, handle: handle, path: path)
        })
    }

    private func sendSimple(_ conn: NWConnection, status: String, type: String, body: String, declaredLength: Int? = nil) {
        let length = declaredLength ?? body.utf8.count
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(length)\r\nConnection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(Data(body.utf8))
        conn.send(content: out, completion: .contentProcessed { [weak self] _ in
            self?.finish(conn)
        })
    }

    private func finish(_ conn: NWConnection) {
        conn.send(content: nil, contentContext: .finalMessage, isComplete: true,
                  completion: .contentProcessed { _ in conn.cancel() })
    }

    private func notify(_ event: ServerEvent) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
    }
}
