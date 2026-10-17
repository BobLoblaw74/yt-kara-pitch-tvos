import AVFoundation
import SwiftUI
import UIKit

/// Full-screen `AVPlayerLayer` that hands Siri Remote presses to `onPress`.
///
/// Presses are read as `UIPress` types so directional *clicks* stay apart from swipes. Menu is
/// passed on to the system so Back still leaves the screen.
final class PlayerHostController: UIViewController {
    var onPress: (UIPress.PressType) -> Void = { _ in }
    private let player: AVPlayer

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
        let handled: [UIPress.PressType] = [.upArrow, .downArrow, .leftArrow, .rightArrow, .select, .playPause]
        let mine = presses.filter { handled.contains($0.type) }
        mine.forEach { onPress($0.type) }
        if mine.count < presses.count { super.pressesBegan(presses.subtracting(mine), with: event) }
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override var canBecomeFocused: Bool { true }
}

struct PlayerHost: UIViewControllerRepresentable {
    let player: AVPlayer
    let onPress: (UIPress.PressType) -> Void

    func makeUIViewController(context: Context) -> PlayerHostController {
        let controller = PlayerHostController(player: player)
        controller.onPress = onPress
        return controller
    }

    func updateUIViewController(_ controller: PlayerHostController, context: Context) {
        controller.onPress = onPress
    }
}
