import Foundation

enum AppPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var imports: URL { ensure(documents.appendingPathComponent("Imports")) }
    static var signed: URL { ensure(documents.appendingPathComponent("Signed")) }
    static var appSupport: URL {
        ensure(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
