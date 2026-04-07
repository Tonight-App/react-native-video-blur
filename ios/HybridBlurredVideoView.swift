import UIKit
import AVFoundation
import NitroModules

class HybridBlurredVideoView: HybridBlurredVideoViewSpec {

    // MARK: - View

    private let containerView = UIView()
    override var view: UIView { containerView }

    // MARK: - Native layers

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var looperRef: Any?
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

    override init() {
        super.init()
        containerView.clipsToBounds = true
        containerView.backgroundColor = .black
        containerView.addSubview(thumbnailView)
        blurOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    override func beforeUpdate() {
        super.beforeUpdate()
    }

    override func afterUpdate() {
        super.afterUpdate()
        let bounds = containerView.bounds
        playerLayer?.frame = bounds
        blurOverlay.frame = bounds
        thumbnailView.frame = bounds
    }

    // MARK: - Video loading

    private func loadVideo() {
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

        item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)

        if !paused {
            player?.play()
        }
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "status",
           let item = object as? AVPlayerItem,
           item.status == .readyToPlay
        {
            item.removeObserver(self, forKeyPath: "status")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                UIView.animate(withDuration: 0.3, delay: 0.15, options: .curveEaseOut) {
                    self.thumbnailView.alpha = 0
                } completion: { _ in
                    self.thumbnailView.isHidden = true
                }
            }
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
        // swap for a CIGaussianBlur CAFilter on playerLayer.
        // playerLayer?.filters = [CIFilter(name: "CIGaussianBlur",
        //     parameters: ["inputRadius": blurRadius])!]
    }

    deinit {
        player?.pause()
        playerLayer?.removeFromSuperlayer()
    }
}
