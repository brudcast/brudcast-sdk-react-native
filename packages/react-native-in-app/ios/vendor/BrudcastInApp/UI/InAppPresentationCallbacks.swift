import Foundation

/// What a presented message reports back to the module. Every closure is safe to call from the
/// main queue.
struct InAppPresentationCallbacks {
    var onImpression: () -> Void
    var onButton: (_ buttonId: String?, _ action: InAppAction) -> Void
    var onDismiss: (BrudcastDismissReason) -> Void
    var onClosed: () -> Void

    static let none = InAppPresentationCallbacks(onImpression: {}, onButton: { _, _ in }, onDismiss: { _ in }, onClosed: {})
}
