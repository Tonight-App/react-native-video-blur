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
    private let blurOverlay = UIVisualEffectView(
        effect: UIBlurEffect(style: .dark)
    )
    private let thumbnailView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        return iv
    }()

    // MARK: - Props

    var source: String = "" {
        didSet { if source != oldValue { loadVideo() } }
    }
    var paused: Bool = true {
        didSet { paused ? player?.pause() : player?.play() }
    }
    var looping: Bool = false
    var blurRadius: Double = 7.0 {
        didSet { updateBlurIntensity() }
    }
    var thumbnailSource: String = "" {
        didSet { loadThumbnail() }
    }
    var rotation: Double = 0

    // MARK: - Init

    init() {
        containerView.clipsToBounds = true
        containerView.backgroundColor = .black
        containerView.addSubview(thumbnailView)
        blurOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    func beforeUpdate() {}

    func afterUpdate() {
        let bounds = containerView.bounds
        playerLayer?.frame = bounds
        blurOverlay.frame = bounds
        thumbnailView.frame = bounds
    }

    // MARK: - Video loading

    private func loadVideo() {
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        looperRef = nil

        guard !source.isEmpty, let url = URL(string: source) else { return }

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

        containerView.layer.addSublayer(layer)
        self.playerLayer = layer

        containerView.addSubview(blurOverlay)
        containerView.bringSubviewToFront(thumbnailView)

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

    // MARK: - Thumbnail

    private func loadThumbnail() {
        thumbnailView.alpha = 1
        thumbnailView.isHidden = false

        guard !thumbnailSource.isEmpty, let url = URL(string: thumbnailSource) else {
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.thumbnailView.image = image
            }
        }.resume()
    }

    // MARK: - Blur intensity

    private func updateBlurIntensity() {
        // UIVisualEffectView gives zero-flicker GPU blur. For custom radius,
        // render through AVPlayerItemVideoOutput + CIGaussianBlur + MTKView.
    }

    deinit {
        statusObservation?.invalidate()
        player?.pause()
        playerLayer?.removeFromSuperlayer()
    }
}
