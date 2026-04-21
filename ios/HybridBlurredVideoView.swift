import UIKit
import AVFoundation
import NitroModules

/// Container that keeps the `AVPlayerLayer` sized to its bounds. UIKit handles
/// subview autoresizing via autoresizingMask, but a raw `CALayer` won't follow
/// bounds changes on its own — so we resize it here on every layout pass.
/// Without this, the player layer stays at the (often zero) frame it had the
/// first time `afterUpdate` ran, which on newer nitro is before Fabric has
/// laid the view out, and the video renders invisibly.
private final class BlurredVideoContainerView: UIView {
    weak var playerLayer: CALayer?
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let playerLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

class HybridBlurredVideoView: HybridBlurredVideoViewSpec {

    // MARK: - View

    private let containerView = BlurredVideoContainerView()
    var view: UIView { containerView }

    // MARK: - Native layers

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var looperRef: Any?
    private var readyObservation: NSKeyValueObservation?
    private let blurOverlay = UIVisualEffectView(effect: nil)
    private var blurAnimator: UIViewPropertyAnimator?
    private let thumbnailView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return iv
    }()

    private var loadedSource: String?
    private var extractedSource: String?
    private var extractionToken: UUID?
    private var videoDidRenderFirstFrame = false

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
        didSet { if thumbnailSource != oldValue { reconcile() } }
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
        thumbnailView.frame = containerView.bounds
        blurOverlay.frame = containerView.bounds
        // Start with no poster; applyThumbnailVisibility will reveal it
        // only if the user actually asked for one.
        thumbnailView.alpha = 0
        thumbnailView.isHidden = true
        containerView.addSubview(thumbnailView)
        containerView.addSubview(blurOverlay)
        blurOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setupBlurAnimator()
    }

    func beforeUpdate() {}

    func afterUpdate() {
        containerView.setNeedsLayout()
    }

    // MARK: - Reconcile

    /// Whether the user wants any kind of poster image shown while the video
    /// loads. Purely a function of props — no state, no side effects.
    private var wantsThumbnail: Bool {
        return !thumbnailSource.isEmpty || enableThumbnail
    }

    private func reconcile() {
        // 1. Video lifecycle
        if showVideo {
            if loadedSource != source { loadVideo() }
        } else {
            unloadVideo()
        }

        // 2. Thumbnail image source
        if !thumbnailSource.isEmpty {
            loadThumbnailImage()
        } else if enableThumbnail && !source.isEmpty && extractedSource != source {
            extractThumbnailFromSource()
        } else if !wantsThumbnail {
            thumbnailView.image = nil
            extractedSource = nil
        }

        // 3. Thumbnail visibility
        applyThumbnailVisibility(animated: false)
    }

    /// Single source of truth for thumbnailView alpha/isHidden. Called on
    /// every reconcile and whenever the video readiness state changes.
    ///
    /// - If the user doesn't want a thumbnail → hidden, no poster.
    /// - If the user wants one AND the video has rendered → fade it out.
    /// - Otherwise → visible (alpha=1, not hidden).
    private func applyThumbnailVisibility(animated: Bool) {
        guard wantsThumbnail else {
            thumbnailView.layer.removeAllAnimations()
            thumbnailView.alpha = 0
            thumbnailView.isHidden = true
            return
        }

        let shouldFadeOut = showVideo && videoDidRenderFirstFrame
        if shouldFadeOut {
            guard !thumbnailView.isHidden else { return }
            if animated {
                UIView.animate(withDuration: 0.3, delay: 0.05, options: .curveEaseOut) {
                    self.thumbnailView.alpha = 0
                } completion: { _ in
                    self.thumbnailView.isHidden = true
                }
            } else {
                thumbnailView.alpha = 0
                thumbnailView.isHidden = true
            }
        } else {
            thumbnailView.layer.removeAllAnimations()
            thumbnailView.isHidden = false
            thumbnailView.alpha = 1
        }
    }

    // MARK: - Video loading

    private func unloadVideo() {
        readyObservation?.invalidate()
        readyObservation = nil
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        containerView.playerLayer = nil
        player = nil
        playerLayer = nil
        looperRef = nil
        loadedSource = nil
        videoDidRenderFirstFrame = false
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

        // Player layer goes below thumbnail + blur overlay so the poster
        // (and its blur) stay on top until the first frame renders.
        containerView.layer.insertSublayer(layer, at: 0)
        self.playerLayer = layer
        containerView.playerLayer = layer
        containerView.setNeedsLayout()

        // `isReadyForDisplay` is the correct signal for "a video frame is
        // actually on screen" — unlike `AVPlayerItem.status == .readyToPlay`,
        // which only means "playback can begin". Using .initial so we also
        // handle the case where the layer is already ready at observation
        // time (cached assets, rapid re-mounts).
        readyObservation = layer.observe(\.isReadyForDisplay, options: [.new, .initial]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.videoDidRenderFirstFrame = true
                self.applyThumbnailVisibility(animated: true)
            }
        }

        if !paused {
            player?.play()
        }
    }

    // MARK: - Thumbnail (explicit source)

    /// Loads a thumbnail from `thumbnailSource`. Accepts any form React Native
    /// hands us: `https://...` (remote), `file://...` (local file),
    /// `http://localhost:8081/...` (Metro dev assets), or a bare filesystem
    /// path. `URLSession` transparently handles http(s) and file schemes.
    private func loadThumbnailImage() {
        guard !thumbnailSource.isEmpty else { return }

        let url: URL? = {
            if let u = URL(string: thumbnailSource), u.scheme != nil {
                return u
            }
            // Bare path with no scheme — treat as local file.
            return URL(fileURLWithPath: thumbnailSource)
        }()
        guard let url else { return }

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
            thumbnailView.image = cached
            return
        }

        let token = UUID()
        extractionToken = token
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let image = try? await VideoThumbnailExtractor.extract(
                source: url, timeMs: 100, maxSize: 512
            ) else { return }
            await MainActor.run {
                guard let self, self.extractionToken == token else { return }
                // If the video already rendered and the poster is already
                // hidden, don't paint over the playing video.
                if self.videoDidRenderFirstFrame && self.thumbnailView.isHidden {
                    return
                }
                self.thumbnailView.image = image
            }
        }
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
        readyObservation?.invalidate()
        player?.pause()
        playerLayer?.removeFromSuperlayer()
    }
}
