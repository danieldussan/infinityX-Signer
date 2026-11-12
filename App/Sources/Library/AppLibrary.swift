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

    /// Drops "Firmadas" records whose file is gone. Installed history stays even without the file.
    func reconcile() {
        let kept = records.filter { $0.installedAt != nil || $0.fileExists }
        if kept.count != records.count {
            records = kept
            save()
        }
    }

    /// Adds the apps of a finished sign run, replacing records with the same bundle id or file name.
    func add(_ apps: [SignedApp]) {
        let now = Date()
        for app in apps {
            let name = app.ipaURL.lastPathComponent
            let size = (try? FileManager.default.attributesOfItem(atPath: app.ipaURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            records.removeAll { $0.ipaFileName == name || $0.bundleID == app.job.bundleID }
            records.append(AppRecord(id: UUID().uuidString, name: app.job.displayName, bundleID: app.job.bundleID,
                                     ipaFileName: name, sizeBytes: size, signedAt: now, installedAt: nil,
                                     version: app.version))
        }
        save()
    }

    /// Called by the install coordinator when an item completes.
    func markInstalled(fileName: String) {
        guard let i = records.firstIndex(where: { $0.ipaFileName == fileName }) else { return }
        records[i].installedAt = Date()
        save()
    }

    /// Deletes the record and its IPA file (used by trash in Firmadas and Quitar in Instaladas).
    /// ponytail: Quitar also deletes the file; nothing else in the UI could reach it afterwards.
    func remove(_ record: AppRecord) {
        try? FileManager.default.removeItem(at: record.ipaURL)
        records.removeAll { $0.id == record.id }
        save()
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
