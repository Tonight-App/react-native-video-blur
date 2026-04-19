import UIKit
import AVFoundation
import NitroModules

class HybridBlurredVideoView: HybridBlurredVideoViewSpec {

    // MARK: - View

    private let containerView = UIView()
    var view: UIView { containerView }

    // MARK: - Native layers

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var looperRef: Any?
    private var statusObservation: NSKeyValueObservation?
    private let blurOverlay = UIVisualEffectView(effect: nil)
    private var blurAnimator: UIViewPropertyAnimator?
    private let thumbnailView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        return iv
    }()

    private var loadedSource: String?
    private var extractedSource: String?
    private var extractionToken: UUID?

    // MARK: - Props

    var source: String = "" {
        didSet { if source != oldValue { reconcile() } }
    }
    var paused: Bool = true {
        didSet { paused ? player?.pause() : player?.play() }
    }
    var looping: Bool = false
    var blurRadius: Double = 7.0 {
        didSet { applyBlurFraction() }
    }
    var thumbnailSource: String = "" {
        didSet { if thumbnailSource != oldValue { loadRemoteThumbnail() } }
    }
    var enableThumbnail: Bool = false {
        didSet { if enableThumbnail != oldValue { reconcile() } }
    }
    var showVideo: Bool = true {
        didSet { if showVideo != oldValue { reconcile() } }
    }
    var rotation: Double = 0

    // MARK: - Init

    override init() {
        super.init()
        containerView.clipsToBounds = true
        containerView.backgroundColor = .black
        containerView.addSubview(thumbnailView)
        containerView.addSubview(blurOverlay)
        blurOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setupBlurAnimator()
    }

    func beforeUpdate() {}

    func afterUpdate() {
        let bounds = containerView.bounds
        playerLayer?.frame = bounds
        blurOverlay.frame = bounds
        thumbnailView.frame = bounds
    }

    // MARK: - Reconcile

    private func reconcile() {
        if showVideo {
            if loadedSource != source { loadVideo() }
        } else {
            unloadVideo()
        }

        if enableThumbnail
            && thumbnailSource.isEmpty
            && !source.isEmpty
            && extractedSource != source {
            extractThumbnailFromSource()
        }
    }

    // MARK: - Video loading

    private func unloadVideo() {
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        looperRef = nil
        loadedSource = nil
        thumbnailView.alpha = 1
        thumbnailView.isHidden = false
    }

    private func loadVideo() {
        unloadVideo()

        guard !source.isEmpty, let url = URL(string: source) else { return }
        loadedSource = source

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        if looping {
            let queuePlayer = AVQueuePlayer(items: [item])
            let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            self.looperRef = looper
            self.player = queuePlayer
        } else {
            self.player = AVPlayer(playerItem: item)
        }

        player?.isMuted = true

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = containerView.bounds

        if rotation == 90 {
            layer.setAffineTransform(CGAffineTransform(rotationAngle: .pi / 2))
        }

        // Player layer goes below thumbnail + blur overlay so the thumbnail
        // (and its blur) stay on top until we explicitly fade them out.
        containerView.layer.insertSublayer(layer, at: 0)
        self.playerLayer = layer

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self, item.status == .readyToPlay else { return }
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.3, delay: 0.15, options: .curveEaseOut) {
                    self.thumbnailView.alpha = 0
                } completion: { _ in
                    self.thumbnailView.isHidden = true
                }
            }
        }

        if !paused {
            player?.play()
        }
    }

    // MARK: - Thumbnail (remote source)

    private func loadRemoteThumbnail() {
        guard !thumbnailSource.isEmpty, let url = URL(string: thumbnailSource) else {
            return
        }

        let videoAlreadyReady = player?.currentItem?.status == .readyToPlay
        if !videoAlreadyReady {
            thumbnailView.alpha = 1
            thumbnailView.isHidden = false
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.thumbnailView.image = image
            }
        }.resume()
    }

    // MARK: - Thumbnail (extracted from source)

    private func extractThumbnailFromSource() {
        guard let url = VideoThumbnailExtractor.resolveURL(source) else { return }
        extractedSource = source

        // Synchronous cache hit — paint immediately, no flicker.
        if let cached = VideoThumbnailExtractor.cachedImage(
            for: url, timeMs: 100, maxSize: 512
        ) {
            applyExtractedImage(cached)
            return
        }

        let videoAlreadyReady = player?.currentItem?.status == .readyToPlay
        if !videoAlreadyReady {
            thumbnailView.alpha = 1
            thumbnailView.isHidden = false
        }

        let token = UUID()
        extractionToken = token
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let image = try? await VideoThumbnailExtractor.extract(
                source: url, timeMs: 100, maxSize: 512
            ) else { return }
            await MainActor.run {
                guard let self, self.extractionToken == token else { return }
                self.applyExtractedImage(image)
            }
        }
    }

    private func applyExtractedImage(_ image: UIImage) {
        // Don't clobber if video already rendered and faded thumb out.
        if player?.currentItem?.status == .readyToPlay && thumbnailView.isHidden {
            return
        }
        thumbnailView.image = image
    }

    // MARK: - Blur intensity

    private func setupBlurAnimator() {
        blurAnimator?.stopAnimation(true)
        blurAnimator?.finishAnimation(at: .start)

        blurOverlay.effect = nil
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.blurOverlay.effect = UIBlurEffect(style: .light)
        }
        animator.pausesOnCompletion = true
        animator.fractionComplete = CGFloat(min(max(blurRadius / 10.0, 0), 1))
        blurAnimator = animator
    }

    private func applyBlurFraction() {
        if blurAnimator == nil {
            setupBlurAnimator()
        } else {
            blurAnimator?.fractionComplete = CGFloat(min(max(blurRadius / 10.0, 0), 1))
        }
    }

    deinit {
        blurAnimator?.stopAnimation(true)
        blurAnimator?.finishAnimation(at: .start)
        statusObservation?.invalidate()
        player?.pause()
        playerLayer?.removeFromSuperlayer()
    }
}
