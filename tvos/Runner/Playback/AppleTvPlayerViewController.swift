import UIKit

final class AppleTvPlayerViewController: UIViewController {
    private let player: MpvPlayerWrapper
    private let debugLabel = UILabel()
    private var debugTimer: Timer?
    private var didAttachSurface = false

    init(player: MpvPlayerWrapper) {
        self.player = player
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        player.attachVideoView(view)
        didAttachSurface = true

        debugLabel.numberOfLines = 0
        debugLabel.font = .monospacedSystemFont(ofSize: 26, weight: .regular)
        debugLabel.textColor = UIColor(red: 0, green: 0.9, blue: 0.4, alpha: 1)
        debugLabel.backgroundColor = UIColor(white: 0, alpha: 0.55)
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(debugLabel)
        NSLayoutConstraint.activate([
            debugLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            debugLabel.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 60),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if didAttachSurface {
            player.notifySurfaceReady()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        player.notifySurfaceReady()
        debugTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.updateDebug() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        debugTimer?.invalidate()
        debugTimer = nil
        player.stop()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .playPause, .select:
                togglePlayPause()
                return
            case .leftArrow:
                seekBy(-10)
                return
            case .rightArrow:
                seekBy(10)
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    private func togglePlayPause() {
        switch player.state {
        case .playing, .buffering, .opening:
            player.pause()
        default:
            player.resume()
        }
    }

    private func seekBy(_ delta: TimeInterval) {
        player.seek(to: max(0, player.currentTime + delta))
    }

    private func updateDebug() {
        let state: String
        switch player.state {
        case .idle: state = "idle"
        case .opening: state = "opening"
        case .buffering(let p): state = "buffering \(Int(p * 100))%"
        case .playing: state = "playing"
        case .paused: state = "paused"
        case .stopped: state = "stopped"
        case .ended: state = "ended"
        case .error: state = "error"
        }
        let inWindow = player.videoView?.window != nil
        debugLabel.text = """
            mpv: \(state)
            pos \(String(format: "%.1f", player.currentTime)) / \(String(format: "%.1f", player.duration))
            buf \(Int(player.bufferProgress * 100))%   surfaceInWindow=\(inWindow)
            audioTracks \(player.audioTracks.count)   subTracks \(player.subtitleTracks.count)
            lastCmd \(AppleTvVideoChannel.lastCommand)
            """
    }
}
