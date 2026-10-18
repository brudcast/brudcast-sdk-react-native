#if canImport(UIKit)
import SwiftUI
import UIKit
import Brudcast

/// Puts messages on screen in a window of their own above the app.
final class InAppPresenter {
    static let shared = InAppPresenter()

    private var window: UIWindow?
    private var model: InAppPresentationModel?
    private weak var previousKeyWindow: UIWindow?
    private var closing = false
    private var autoDismiss: DispatchWorkItem?

    private init() {}

    var isPresenting: Bool {
        window != nil
    }

    /// Shows a message. Must be called on the main queue.
    ///
    /// - Parameters:
    ///   - messageId: The message id, for logs.
    ///   - design: The design to draw; its images must already be loaded.
    ///   - options: The SDK options, for appearance and accent colour.
    ///   - callbacks: Where impression, button and dismiss reports go.
    ///   - completion: Called with false when nothing could be shown, such as with no active scene.
    func present(messageId: String, design: InAppDesign, options: BrudcastOptions, callbacks: InAppPresentationCallbacks, completion: @escaping (Bool) -> Void) {
        guard window == nil, UIApplication.shared.applicationState == .active, let scene = BrudcastPresentation.activeScene() else {
            completion(false)
            return
        }
        let accent = options.accentColor ?? BrudcastPresentation.keyWindow()?.tintColor ?? .systemBlue
        let model = InAppPresentationModel(design: design, theme: InAppTheme(accent: accent))
        model.onButton = { [weak self] buttonId, action in
            callbacks.onButton(buttonId, action)
            self?.close(model: model, callbacks: callbacks)
        }
        model.onDismiss = { [weak self] reason in
            callbacks.onDismiss(reason)
            self?.close(model: model, callbacks: callbacks)
        }

        let created = BrudcastMessageWindow(windowScene: scene)
        created.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        created.backgroundColor = .clear
        switch options.appearance {
        case .light: created.overrideUserInterfaceStyle = .light
        case .dark: created.overrideUserInterfaceStyle = .dark
        case .system: created.overrideUserInterfaceStyle = BrudcastPresentation.keyWindow()?.overrideUserInterfaceStyle ?? .unspecified
        }

        let bounds = scene.coordinateSpace.bounds
        let insets = BrudcastPresentation.keyWindow()?.safeAreaInsets ?? .zero
        let edgeInsets = EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
        let controller: UIViewController

        switch design.format {
        case .banner:
            let width = min(bounds.width - 32, 500)
            let host = UIHostingController(rootView: AnyView(InAppBannerView(model: model, width: width)))
            host.view.backgroundColor = .clear
            let fitting = host.sizeThatFits(in: CGSize(width: width, height: 200))
            let height = min(fitting.height, 120) + 8 + 24
            let isTop = design.layout.position != .bottom
            let y = isTop ? insets.top : bounds.height - insets.bottom - height
            created.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            host.rootView = AnyView(
                InAppBannerView(model: model, width: width)
                    .padding(isTop ? .top : .bottom, 8)
                    .frame(width: bounds.width, height: height, alignment: isTop ? .top : .bottom)
            )
            controller = host
        case .modal:
            created.frame = bounds
            controller = Self.host(InAppModalView(model: model, containerSize: bounds.size, safeInsets: edgeInsets), modal: true)
        case .fullscreen, .inboxOnly:
            created.frame = bounds
            controller = Self.host(InAppFullscreenView(model: model, containerSize: bounds.size, safeInsets: edgeInsets), modal: true)
        }

        created.rootViewController = controller
        self.model = model
        window = created
        closing = false

        if design.format == .banner {
            created.isHidden = false
        } else {
            previousKeyWindow = BrudcastPresentation.keyWindow()
            created.makeKeyAndVisible()
        }

        DispatchQueue.main.async {
            withAnimation(model.entrance) {
                model.visible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + model.entranceDuration) {
                guard self.model === model, !self.closing else { return }
                callbacks.onImpression()
                if design.format == .banner {
                    let announcement = [design.title, design.bodyText].compactMap { $0 }.joined(separator: ". ")
                    UIAccessibility.post(notification: .announcement, argument: announcement)
                } else {
                    UIAccessibility.post(notification: .screenChanged, argument: controller.view)
                }
                if design.format == .banner, let seconds = design.layout.autoDismissSeconds {
                    self.scheduleAutoDismiss(after: seconds, model: model, callbacks: callbacks)
                }
            }
        }
        BrudcastLogger.shared.debug("Presented message \(messageId)")
        completion(true)
    }

    private func scheduleAutoDismiss(after seconds: Double, model: InAppPresentationModel, callbacks: InAppPresentationCallbacks) {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.model === model else { return }
            if model.dragOffset != 0 {
                self.scheduleAutoDismiss(after: 1, model: model, callbacks: callbacks)
                return
            }
            model.onDismiss(.auto)
        }
        autoDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func close(model: InAppPresentationModel, callbacks: InAppPresentationCallbacks) {
        guard self.model === model, !closing else { return }
        closing = true
        autoDismiss?.cancel()
        withAnimation(model.exit) {
            model.visible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + model.exitDuration) {
            self.window?.isHidden = true
            self.window?.rootViewController = nil
            self.window = nil
            self.model = nil
            self.closing = false
            if let previous = self.previousKeyWindow, !previous.isHidden {
                previous.makeKey()
            }
            self.previousKeyWindow = nil
            callbacks.onClosed()
        }
    }

    private static func host<V: View>(_ view: V, modal: Bool) -> UIViewController {
        let host = UIHostingController(rootView: view.edgesIgnoringSafeArea(.all))
        host.view.backgroundColor = .clear
        host.view.accessibilityViewIsModal = modal
        return host
    }
}

final class BrudcastMessageWindow: UIWindow {}
#endif
