import Foundation
import InfinityXCore
import Zsign
import ZIPFoundation

enum RowState: Equatable {
    case pending
    case signing
    case signed(URL)
    case failed(String)
}

struct SignedApp {
    let job: SigningJob
    let ipaURL: URL
    let version: String
}

struct SigningRequest {
    let ipaURL: URL
    let p12URL: URL
    let profileURL: URL
    let password: String
    let stripPlugins: Bool
}

enum SigningError: LocalizedError {
    case noApp
    case zsignFailed

    var errorDescription: String? {
        switch self {
        case .noApp: return "El IPA no contiene Payload/*.app"
        case .zsignFailed: return "Zsign falló (revisa certificado, contraseña y perfil)"
        }
    }
}

private final class Flag {
    var ok = true
}

/// Unzips the IPA once, then signs one fresh copy of the .app per job.
final class SigningEngine {
    func run(request: SigningRequest,
             jobs: [SigningJob],
             onUpdate: @escaping @MainActor (Int, RowState) -> Void) async -> [SignedApp] {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("sign-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }

        let base = work.appendingPathComponent("base")
        let baseApp: URL
        do {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            try fm.unzipItem(at: request.ipaURL, to: base)
            guard let found = Self.findApp(in: base.appendingPathComponent("Payload")) else {
                throw SigningError.noApp
            }
            baseApp = found
        } catch {
            for job in jobs { await onUpdate(job.number, .failed(error.localizedDescription)) }
            return []
        }

        var results: [SignedApp] = []
        for job in jobs {
            await onUpdate(job.number, .signing)
            do {
                let app = try signOne(job: job, baseApp: baseApp, request: request, work: work)
                // The counter only advances after a successful sign.
                var counter = UserDefaultsCounterStore()
                advance(&counter, afterSuccess: job.number)
                results.append(app)
                await onUpdate(job.number, .signed(app.ipaURL))
            } catch {
                await onUpdate(job.number, .failed(error.localizedDescription))
            }
        }
        return results
    }

    private func signOne(job: SigningJob, baseApp: URL, request: SigningRequest, work: URL) throws -> SignedApp {
        let fm = FileManager.default
        let jobDir = work.appendingPathComponent("job-\(job.number)")
        defer { try? fm.removeItem(at: jobDir) }

        let payload = jobDir.appendingPathComponent("Payload")
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        let appCopy = payload.appendingPathComponent(baseApp.lastPathComponent)
        try fm.copyItem(at: baseApp, to: appCopy)

        // ponytail: we sign a fresh copy per job, so localized strings are cleaned every time (cost: one copy per job).
        try PlistEditor.setName(appDir: appCopy, name: job.displayName, cleanLocalized: true)
        try AppPlist.setBundleID(appDir: appCopy, bundleID: job.bundleID)
        if request.stripPlugins { try PlistEditor.stripPlugins(appDir: appCopy) }

        let flag = Flag()
        let returned = Zsign.sign(
            appPath: appCopy.path,
            provisionPath: request.profileURL.path,
            p12Path: request.p12URL.path,
            p12Password: request.password,
            entitlementsPath: "",
            removeProvision: false,
            completion: { success in
                if !success { flag.ok = false }
            }
        )
        guard returned && flag.ok else { throw SigningError.zsignFailed }

        let version = AppPlist.version(appDir: appCopy)
        let out = AppPaths.signed.appendingPathComponent(job.outputFileName)
        if fm.fileExists(atPath: out.path) { try fm.removeItem(at: out) }
        // ponytail: stored (no compression) for speed; signed IPAs are larger than the original.
        try fm.zipItem(at: payload, to: out, shouldKeepParent: true, compressionMethod: .none)
        return SignedApp(job: job, ipaURL: out, version: version)
    }

    private static func findApp(in payload: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.pathExtension == "app" }
    }
}
