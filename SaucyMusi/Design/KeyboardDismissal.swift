import SwiftUI
import UIKit

/// Installs one non-blocking tap recognizer at the window level so every screen,
/// sheet, form, and search field gets consistent keyboard dismissal behavior.
struct KeyboardDismissalInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissalHostingView {
        KeyboardDismissalHostingView()
    }

    func updateUIView(_ uiView: KeyboardDismissalHostingView, context: Context) {
        uiView.installIfNeeded()
    }

    static func dismantleUIView(_ uiView: KeyboardDismissalHostingView, coordinator: ()) {
        uiView.uninstall()
    }
}

final class KeyboardDismissalHostingView: UIView, UIGestureRecognizerDelegate {
    private weak var installedWindow: UIWindow?
    private lazy var dismissalRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    func installIfNeeded() {
        guard let window, installedWindow !== window else { return }
        uninstall()
        window.addGestureRecognizer(dismissalRecognizer)
        installedWindow = window
    }

    func uninstall() {
        installedWindow?.removeGestureRecognizer(dismissalRecognizer)
        installedWindow = nil
    }

    @objc private func dismissKeyboard() {
        installedWindow?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView: UIView? = touch.view
        while let view = touchedView {
            if view is UITextField || view is UITextView {
                return false
            }
            touchedView = view.superview
        }
        return true
    }
}
