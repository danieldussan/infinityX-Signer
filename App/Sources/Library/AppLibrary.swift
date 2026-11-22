import Foundation
import InfinityXCore

/// One signed app kept in Documents/Signed. `installedAt != nil` moves it from "Firmadas" to "Instaladas".
struct AppRecord: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var bundleID: String
    var ipaFileName: String
    var sizeBytes: Int64
    var signedAt: Date
    var installedAt: Date?
    var version: String?
    /// Certificate/profile used to sign it; nil for records saved before this was tracked.
    var cert: CertSnapshot?

    var ipaURL: URL { AppPaths.signed.appendingPathComponent(ipaFileName) }
    var fileExists: Bool { FileManager.default.fileExists(atPath: ipaURL.path) }

    /// Adapter for the existing install queue. ponytail: number 0, the queue only keys items by its own id.
    var signedApp: SignedApp {
        SignedApp(job: SigningJob(number: 0, displayName: name, bundleID: bundleID, outputFileName: ipaFileName),
                  ipaURL: ipaURL, version: version ?? "1.0")
    }
}

/// Persistent list of signed / installed apps (JSON in Application Support).
@MainActor
final class AppLibrary: ObservableObject {
    @Published private(set) var records: [AppRecord] = []
    private let fileURL: URL

    init(fileURL: URL = AppPaths.appSupport.appendingPathComponent("library.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? Self.decoder.decode([AppRecord].self, from: data) {
            records = decoded
        }
        reconcile()
    }

    /// Ready to install: signed and never installed from here.
    var signed: [AppRecord] {
        records.filter { $0.installedAt == nil }.sorted { $0.signedAt > $1.signedAt }
    }

    var installed: [AppRecord] {
        records.filter { $0.installedAt != nil }.sorted { ($0.installedAt ?? .distantPast) > ($1.installedAt ?? .distantPast) }
    }

    /// Apps whose certificate is expired or expires within a week, soonest first.
    var needingAttention: [AppRecord] {
        records.filter { ($0.cert?.status() ?? .valid) != .valid }
            .sorted { ($0.cert?.expiresAt ?? .distantFuture) < ($1.cert?.expiresAt ?? .distantFuture) }
    }

    /// Drops "Firmadas" records whose file is gone. Installed history stays even without the file.
    func reconcile() {
        let kept = records.filter { $0.installedAt != nil || $0.fileExists }
        if kept.count != records.count {
            records = kept
            save()
        }
    }

    /// Adds the apps of a finished sign run. The bundle id decides: same bundle keeps only the latest
    /// (installed or not), different bundles coexist whatever their names.
    func add(_ apps: [SignedApp], cert: CertSnapshot? = nil) {
        let now = Date()
        for app in apps {
            let name = app.ipaURL.lastPathComponent
            let size = (try? FileManager.default.attributesOfItem(atPath: app.ipaURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            // The new IPA overwrote any file with this name, so a pending record of another bundle pointing at it is stale.
            let replaced = records.filter { $0.bundleID == app.job.bundleID || ($0.installedAt == nil && $0.ipaFileName == name) }
            records.removeAll { r in replaced.contains { $0.id == r.id } }
            for old in replaced where old.ipaFileName != name && !records.contains(where: { $0.ipaFileName == old.ipaFileName }) {
                try? FileManager.default.removeItem(at: old.ipaURL)
            }
            records.append(AppRecord(id: UUID().uuidString, name: app.job.displayName, bundleID: app.job.bundleID,
                                     ipaFileName: name, sizeBytes: size, signedAt: now, installedAt: nil,
                                     version: app.version, cert: cert))
        }
        save()
        ExpiryAlerts.reschedule(for: records)
    }

    /// Called by the install coordinator when an item completes.
    func markInstalled(fileName: String) {
        guard let i = records.firstIndex(where: { $0.ipaFileName == fileName && $0.installedAt == nil }) else { return }
        records[i].installedAt = Date()
        save()
    }

    /// Deletes the record and its IPA file (used by trash in Firmadas and Quitar in Instaladas).
    /// ponytail: Quitar also deletes the file; nothing else in the UI could reach it afterwards.
    func remove(_ record: AppRecord) {
        records.removeAll { $0.id == record.id }
        if !records.contains(where: { $0.ipaFileName == record.ipaFileName }) {
            try? FileManager.default.removeItem(at: record.ipaURL)
        }
        save()
        ExpiryAlerts.reschedule(for: records)
    }

    private func save() {
        guard let data = try? Self.encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es")
        f.unitsStyle = .full
        return f
    }()

    static func string(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "ahora" }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
