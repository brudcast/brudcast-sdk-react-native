#if canImport(UIKit)
import SwiftUI
import UIKit

/// Drives a presented message's entrance and exit.
final class InAppPresentationModel: ObservableObject {
    @Published var visible = false
    @Published var dragOffset: CGFloat = 0

    let design: InAppDesign
    let theme: InAppTheme
    let reduceMotion: Bool
    var onButton: (String?, InAppAction) -> Void = { _, _ in }
    var onDismiss: (BrudcastDismissReason) -> Void = { _ in }

    init(design: InAppDesign, theme: InAppTheme) {
        self.design = design
        self.theme = theme
        self.reduceMotion = UIAccessibility.isReduceMotionEnabled
    }

    var entranceDuration: Double {
        if reduceMotion { return 0.15 }
        switch design.format {
        case .modal: return 0.25
        case .banner: return 0.3
        case .fullscreen, .inboxOnly: return 0.35
        }
    }

    var exitDuration: Double {
        if reduceMotion { return 0.15 }
        switch design.format {
        case .fullscreen, .inboxOnly: return 0.25
        case .modal, .banner: return 0.2
        }
    }

    var entrance: Animation {
        if reduceMotion { return .easeInOut(duration: 0.15) }
        switch design.format {
        case .banner: return .spring(response: 0.3, dampingFraction: 0.9)
        default: return .easeOut(duration: entranceDuration)
        }
    }

    var exit: Animation {
        .easeIn(duration: exitDuration)
    }
}

struct InAppModalView: View {
    /// How far a dismissible modal's content starts from the top: the close button and its inset.
    private static let closeButtonClearance: CGFloat = 48

    @ObservedObject var model: InAppPresentationModel
    let containerSize: CGSize
    let safeInsets: EdgeInsets

    var body: some View {
        let layout = model.design.layout
        let width = min(containerSize.width - 48, 400)
        let padding = CGFloat(layout.padding)
        let maxHeight = containerSize.height - safeInsets.top - safeInsets.bottom - 48
        ZStack(alignment: alignment) {
            Color(UIColor.brudcast(layout.overlayColor) ?? .black)
                .opacity(model.visible ? layout.overlayOpacity : 0)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    if layout.dismissible { model.onDismiss(.overlayTap) }
                }
                .accessibilityHidden(true)

            ZStack(alignment: .topTrailing) {
                InAppFittingScrollView(maxHeight: maxHeight) {
                    InAppBlockList(
                        blocks: model.design.blocks,
                        contentWidth: width - padding * 2,
                        theme: model.theme,
                        onButton: model.onButton
                    )
                    .padding(.horizontal, padding)
                    .padding(.bottom, padding)
                    .padding(.top, layout.dismissible ? max(padding, Self.closeButtonClearance) : padding)
                }
                if layout.dismissible {
                    InAppCloseButton { model.onDismiss(.closeButton) }
                        .padding(4)
                }
            }
            .frame(width: width)
            .background(InAppBackground(layout: layout))
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(layout.cornerRadius), style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 8)
            .padding(.vertical, 24)
            .padding(.top, safeInsets.top)
            .padding(.bottom, safeInsets.bottom)
            .scaleEffect(model.visible || model.reduceMotion ? 1 : 0.96)
            .opacity(model.visible ? 1 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityAction(.escape) {
                if layout.dismissible { model.onDismiss(.back) }
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    private var alignment: Alignment {
        switch model.design.layout.position {
        case .top: return .top
        case .bottom: return .bottom
        case .center: return .center
        }
    }
}

struct InAppBannerView: View {
    @ObservedObject var model: InAppPresentationModel
    let width: CGFloat

    var body: some View {
        let layout = model.design.layout
        let isTop = layout.position != .bottom
        HStack(alignment: .center, spacing: 12) {
            if case .image(_, let url, _, let alt, _)? = model.design.blocks.first(where: { if case .image = $0 { return true } else { return false } }) {
                InAppImageView(url: url, aspectRatio: 1, alt: alt, cornerRadius: 8, width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let title = text(.title) {
                    InAppTextView(role: .title, text: title.text, style: title.style, width: textWidth, lineLimit: 1)
                        .font(.headline)
                }
                if let body = text(.body) ?? text(.caption) {
                    InAppTextView(role: .body, text: body.text, style: body.style, width: textWidth, lineLimit: 2)
                }
            }
            if layout.dismissible {
                InAppCloseButton { model.onDismiss(.closeButton) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: 120)
        .background(InAppBackground(layout: layout, defaultColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: min(CGFloat(layout.cornerRadius), 20), style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let action = layout.bannerAction {
                model.onButton(nil, action)
            }
        }
        .offset(y: model.dragOffset + (model.visible ? 0 : (isTop ? -220 : 220)))
        .opacity(model.reduceMotion && !model.visible ? 0 : 1)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard layout.dismissible else { return }
                    let translation = value.translation.height
                    model.dragOffset = isTop ? min(0, translation) : max(0, translation)
                }
                .onEnded { value in
                    guard layout.dismissible else { return }
                    let translation = value.predictedEndTranslation.height
                    if (isTop && translation < -40) || (!isTop && translation > 40) {
                        model.onDismiss(.swipe)
                    } else {
                        withAnimation(.spring()) { model.dragOffset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(layout.bannerAction == nil ? [] : .isButton)
        .accessibilityAction(.escape) {
            if layout.dismissible { model.onDismiss(.back) }
        }
    }

    private var hasImage: Bool {
        model.design.blocks.contains { if case .image = $0 { return true } else { return false } }
    }

    private var textWidth: CGFloat {
        width - 24 - (hasImage ? 60 : 0) - (model.design.layout.dismissible ? 56 : 0)
    }

    private func text(_ role: InAppTextRole) -> (text: String, style: InAppTextStyle)? {
        for block in model.design.blocks {
            if case .text(_, let blockRole, let text, let style) = block, blockRole == role {
                return (text, style)
            }
        }
        return nil
    }
}

struct InAppFullscreenView: View {
    @ObservedObject var model: InAppPresentationModel
    let containerSize: CGSize
    let safeInsets: EdgeInsets

    var body: some View {
        let layout = model.design.layout
        let padding = CGFloat(layout.padding)
        let contentWidth = min(containerSize.width, 600) - padding * 2
        let available = containerSize.height - safeInsets.top - safeInsets.bottom
        let split = Self.splitTrailingButtons(model.design.blocks)
        ZStack(alignment: .topTrailing) {
            InAppBackground(layout: layout)
                .frame(width: containerSize.width, height: containerSize.height)
                .clipped()
                .edgesIgnoringSafeArea(.all)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    InAppBlockList(blocks: split.content, contentWidth: contentWidth, theme: model.theme, onButton: model.onButton)
                    Spacer(minLength: split.buttons.isEmpty ? 0 : 24)
                    if !split.buttons.isEmpty {
                        InAppBlockList(blocks: split.buttons, contentWidth: contentWidth, theme: model.theme, onButton: model.onButton)
                    }
                }
                .padding(.horizontal, padding)
                .padding(.top, padding + (layout.dismissible ? 32 : 0))
                .padding(.bottom, padding)
                .frame(width: containerSize.width)
                .frame(minHeight: available)
            }
            .padding(.top, safeInsets.top)
            .padding(.bottom, safeInsets.bottom)
            if layout.dismissible {
                InAppCloseButton { model.onDismiss(.closeButton) }
                    .padding(.top, safeInsets.top + 4)
                    .padding(.trailing, 8)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .offset(y: model.visible || model.reduceMotion ? 0 : containerSize.height)
        .opacity(model.reduceMotion && !model.visible ? 0 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) {
            if layout.dismissible { model.onDismiss(.back) }
        }
    }

    static func splitTrailingButtons(_ blocks: [InAppBlock]) -> (content: [InAppBlock], buttons: [InAppBlock]) {
        var index = blocks.count
        while index > 0, case .button = blocks[index - 1] {
            index -= 1
        }
        return (Array(blocks[..<index]), Array(blocks[index...]))
    }
}

/// A design drawn as a static card, for the inbox detail and custom inboxes.
struct InAppCardView: View {
    let design: InAppDesign
    let theme: InAppTheme
    let width: CGFloat
    let onButton: (String?, InAppAction) -> Void

    var body: some View {
        let padding = CGFloat(design.layout.padding)
        let blocks = design.format == .banner ? bannerBlocks : design.blocks
        InAppBlockList(blocks: blocks, contentWidth: width - padding * 2, theme: theme, onButton: onButton)
            .padding(padding)
            .frame(width: width)
            .background(InAppBackground(layout: design.layout))
    }

    private var bannerBlocks: [InAppBlock] {
        var blocks = design.blocks
        if let action = design.layout.bannerAction, action.type != .dismiss {
            let style = InAppButtonStyle(variant: .primary, background: nil, textColor: nil, darkBackground: nil, darkTextColor: nil)
            blocks.append(.button(id: "banner", label: "Open", action: action, style: style))
        }
        return blocks
    }
}
#endif
