import AVFoundation
import SwiftUI
import UIKit

/// What the Siri Remote asks of the player (SPEC §6.2).
enum RemoteAction: Equatable {
    case keyUp, keyDown, seekBack, seekForward, skip, togglePause, back
}

/// Full-screen `AVPlayerLayer` that reads the Siri Remote as `UIPress` types, so directional
/// *clicks* stay apart from swipes. Holding right for `holdToSkip` skips instead of seeking.
final class PlayerHostController: UIViewController {
    static let holdToSkip: Duration = .seconds(1)

    var onAction: (RemoteAction) -> Void = { _ in }
    private let player: AVPlayer
    /// Bumped on each right press, so a hold timer can tell whether it's still the same press.
    private var rightPress = 0
    private var rightHeldToSkip = false

    init(player: AVPlayer) {
        self.player = player
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        self.view = view
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] { [view] }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            switch press.type {
            case .upArrow: onAction(.keyUp)
            case .downArrow: onAction(.keyDown)
            case .leftArrow: onAction(.seekBack)
            case .rightArrow: rightDown()
            case .select, .playPause: onAction(.togglePause)
            case .menu: onAction(.back)
            default: unhandled.insert(press)
            }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .rightArrow }) { rightUp(seek: true) }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .rightArrow }) { rightUp(seek: false) }
        super.pressesCancelled(presses, with: event)
    }

    private func rightDown() {
        rightPress += 1
        rightHeldToSkip = false
        let press = rightPress
        Task { [weak self] in
            try? await Task.sleep(for: Self.holdToSkip)
            guard let self, self.rightPress == press else { return }
            self.rightHeldToSkip = true
            self.onAction(.skip)
        }
    }

    private func rightUp(seek: Bool) {
        if seek && !rightHeldToSkip { onAction(.seekForward) }
        rightPress += 1  // cancels the hold timer
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override var canBecomeFocused: Bool { true }
}

struct PlayerHost: UIViewControllerRepresentable {
    let player: AVPlayer
    let onAction: (RemoteAction) -> Void

    func makeUIViewController(context: Context) -> PlayerHostController {
        let controller = PlayerHostController(player: player)
        controller.onAction = onAction
        return controller
    }

    func updateUIViewController(_ controller: PlayerHostController, context: Context) {
        controller.onAction = onAction
    }
}
