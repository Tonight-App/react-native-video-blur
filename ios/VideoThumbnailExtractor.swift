import AVFoundation
import UIKit

/// Shared fast-path thumbnail extractor used by both the standalone Nitro
/// module and `HybridBlurredVideoView`'s built-in `enableThumbnail` mode.
/// Writes JPEGs into the caches dir keyed by (url, timeMs, maxSize) so repeat
/// calls — across view instances and the standalone API — are free.
enum VideoThumbnailExtractor {

    static func cachedURL(for source: URL, timeMs: Int, maxSize: Int) -> URL {
        let key = "\(source.absoluteString)|\(timeMs)|\(maxSize)"
        let hash = String(key.hashValue.magnitude, radix: 36)
        return FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("blurvideo-thumb-\(hash).jpg")
    }

    static func cachedImage(for source: URL, timeMs: Int, maxSize: Int) -> UIImage? {
        let url = cachedURL(for: source, timeMs: timeMs, maxSize: maxSize)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Extracts and caches a frame. Runs synchronously — callers should
    /// dispatch to a background queue.
    static func extract(
        source: URL,
        timeMs: Int,
        maxSize: Int
    ) async throws -> UIImage {
        let outURL = cachedURL(for: source, timeMs: timeMs, maxSize: maxSize)
        if let img = cachedImage(for: source, timeMs: timeMs, maxSize: maxSize) {
            return img
        }

        let asset = AVURLAsset(
            url: source,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        let cap = CGFloat(max(maxSize, 64))
        generator.maximumSize = CGSize(width: cap, height: cap)

        let time = CMTime(value: CMTimeValue(max(timeMs, 0)), timescale: 1000)

        let cgImage: CGImage = try await withCheckedThrowingContinuation { cont in
            generator.generateCGImagesAsynchronously(
                forTimes: [NSValue(time: time)]
            ) { _, image, _, _, error in
                if let error = error { cont.resume(throwing: error) }
                else if let image = image { cont.resume(returning: image) }
                else { cont.resume(throwing: NSError(domain: "BlurredVideo", code: -1)) }
            }
        }

        let uiImage = UIImage(cgImage: cgImage)
        if let data = uiImage.jpegData(compressionQuality: 0.8) {
            try? data.write(to: outURL, options: .atomic)
        }
        return uiImage
    }

    static func resolveURL(_ path: String) -> URL? {
        if let u = URL(string: path), u.scheme != nil { return u }
        return URL(fileURLWithPath: path)
    }
}
