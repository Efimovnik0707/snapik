// Port of `LocalImageSave.cs` and `WpfExportImageRenderer.cs`'s PNG encoding, SPEC §1.13, §4.4.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG/JPEG encode/decode plus the atomic-write helper described in SPEC §1.13
/// (`LocalImageSave.WriteAsync`).
public enum ImageCodec {
    public enum Format {
        case png
        /// `quality` is clamped to `1...100`, mirroring `Math.Clamp(quality, 1, 100)`.
        case jpeg(quality: Int)
    }

    public static func encode(_ image: CGImage, format: Format) -> Data? {
        let data = NSMutableData()
        let type: CFString
        var properties: [CFString: Any] = [:]
        switch format {
        case .png:
            type = UTType.png.identifier as CFString
        case .jpeg(let quality):
            type = UTType.jpeg.identifier as CFString
            let clamped = min(max(quality, 1), 100)
            properties[kCGImageDestinationLossyCompressionQuality] = Double(clamped) / 100.0
        }
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    public static func decodePNG(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Port of `LocalImageSave.WriteAsync`: `data` is assumed to already be fully encoded in
    /// memory; this only performs the atomic-replace half (encode-before-touching-disk,
    /// temp-file-then-move, temp file always cleaned up).
    public static func writeAtomically(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(url.lastPathComponent + "." + UUID().uuidString + ".tmp")
        try data.write(to: temporary, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporary) }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }
}
