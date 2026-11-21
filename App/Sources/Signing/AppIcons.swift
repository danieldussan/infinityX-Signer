import Foundation
import UIKit
import InfinityXCore

/// Applies icon edits to an unpacked .app before it is signed.
enum AppIcons {
    static func apply(appDir: URL, png: Data?, removeAlternates: Bool) throws {
        let plistURL = appDir.appendingPathComponent("Info.plist")
        let raw = try Data(contentsOf: plistURL)
        guard var dict = try PropertyListSerialization.propertyList(from: raw, format: nil) as? [String: Any]
        else { throw CocoaError(.propertyListReadCorrupt) }

        if removeAlternates {
            let (updated, bases) = IconEditor.removingAlternateIcons(dict)
            dict = updated
            removeFiles(appDir: appDir, bases: bases)
        }
        if let png {
            guard let image = UIImage(data: png) else { throw CocoaError(.fileReadCorruptFile) }
            for target in IconEditor.targets {
                guard let data = square(image, pixels: target.pixels) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: appDir.appendingPathComponent(target.fileName), options: .atomic)
            }
            dict = IconEditor.settingPrimaryIcon(dict)
        }
        let out = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try out.write(to: plistURL, options: .atomic)
    }

    /// Center-crops to a square and renders at exactly `pixels` x `pixels`, opaque (app icons have no alpha).
    static func square(_ image: UIImage, pixels: Int) -> Data? {
        let side = CGFloat(pixels)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let src = image.size
        guard src.width > 0, src.height > 0 else { return nil }
        let scale = side / min(src.width, src.height)
        let w = src.width * scale
        let h = src.height * scale
        return renderer.pngData { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
    }

    private static func removeFiles(appDir: URL, bases: [String]) {
        let fm = FileManager.default
        let stems = bases.map { IconNames.stem($0).lowercased() }.filter { !$0.isEmpty }
        for name in (try? fm.contentsOfDirectory(atPath: appDir.path)) ?? [] where name.lowercased().hasSuffix(".png") {
            let s = IconNames.stem(name).lowercased()
            if stems.contains(where: { s.hasPrefix($0) }) {
                try? fm.removeItem(at: appDir.appendingPathComponent(name))
            }
        }
    }
}
