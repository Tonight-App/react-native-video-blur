import NitroModules

class HybridVideoThumbnailGenerator: HybridVideoThumbnailGeneratorSpec {

    func generateThumbnail(
        videoPath: String,
        timeMs: Double,
        maxSize: Double
    ) throws -> Promise<String> {
        return Promise.async {
            guard let url = VideoThumbnailExtractor.resolveURL(videoPath) else {
                throw RuntimeError.error(withMessage: "Invalid videoPath: \(videoPath)")
            }
            let t = max(Int(timeMs), 0)
            let s = max(Int(maxSize), 64)
            _ = try await VideoThumbnailExtractor.extract(
                source: url, timeMs: t, maxSize: s
            )
            return VideoThumbnailExtractor.cachedURL(
                for: url, timeMs: t, maxSize: s
            ).absoluteString
        }
    }
}
