#if canImport(UIKit)
import SwiftUI
import UIKit

struct InAppTheme {
    var accent: UIColor
}

struct InAppBlockList: View {
    let blocks: [InAppBlock]
    let contentWidth: CGFloat
    let theme: InAppTheme
    let onButton: (String?, InAppAction) -> Void
    var imageCornerRadius: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                InAppBlockView(block: block, contentWidth: contentWidth, theme: theme, onButton: onButton, imageCornerRadius: imageCornerRadius)
                    .padding(.top, index == 0 ? 0 : Self.spacing(before: block, after: blocks[index - 1]))
            }
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    static func spacing(before block: InAppBlock, after previous: InAppBlock) -> CGFloat {
        if case .text(_, .title, _, _) = previous, case .text(_, .body, _, _) = block {
            return 8
        }
        if case .button = previous, case .button = block {
            return 8
        }
        return 12
    }
}

struct InAppBlockView: View {
    let block: InAppBlock
    let contentWidth: CGFloat
    let theme: InAppTheme
    let onButton: (String?, InAppAction) -> Void
    var imageCornerRadius: CGFloat = 8

    var body: some View {
        switch block {
        case .text(_, let role, let text, let style):
            InAppTextView(role: role, text: text, style: style, width: contentWidth)
        case .image(_, let url, let ratio, let alt, let radius):
            InAppImageView(url: url, aspectRatio: ratio, alt: alt, cornerRadius: radius.map { CGFloat($0) } ?? imageCornerRadius, width: contentWidth)
        case .button(let id, let label, let action, let style):
            InAppButtonView(label: label, style: style, theme: theme, width: contentWidth) {
                onButton(id, action)
            }
        case .spacer(_, let height):
            Color.clear.frame(width: contentWidth, height: CGFloat(height))
        case .divider(_, let color, let thickness):
            Rectangle()
                .fill(Color(UIColor.brudcast(color) ?? .separator))
                .frame(width: contentWidth, height: thickness == 1 ? 1 / UIScreen.main.scale : CGFloat(thickness))
        case .columns(_, let children):
            InAppColumnsView(children: children, contentWidth: contentWidth, theme: theme, onButton: onButton)
        }
    }
}

struct InAppColumnsView: View {
    let children: [InAppBlock]
    let contentWidth: CGFloat
    let theme: InAppTheme
    let onButton: (String?, InAppAction) -> Void

    var body: some View {
        if contentWidth < 280 || children.count < 2 {
            InAppBlockList(blocks: children, contentWidth: contentWidth, theme: theme, onButton: onButton)
        } else {
            let column = (contentWidth - 12) / 2
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    InAppBlockView(block: child, contentWidth: column, theme: theme, onButton: onButton)
                }
            }
            .frame(width: contentWidth, alignment: .leading)
        }
    }
}

struct InAppTextView: View {
    let role: InAppTextRole
    let text: String
    let style: InAppTextStyle
    let width: CGFloat
    var lineLimit: Int?

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .multilineTextAlignment(textAlignment)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: lineLimit == nil)
            .frame(width: width, alignment: frameAlignment)
            .accessibilityAddTraits(role == .title ? .isHeader : [])
    }

    private var textStyle: UIFont.TextStyle {
        switch role {
        case .title: return .title2
        case .body: return .body
        case .caption: return .footnote
        }
    }

    private var font: Font {
        let weight: Font.Weight
        switch style.weight ?? (role == .title ? .bold : .regular) {
        case .regular: weight = .regular
        case .medium: weight = .medium
        case .bold: weight = .bold
        }
        let size = style.size.map { CGFloat($0) } ?? UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
        let scaled = UIFontMetrics(forTextStyle: textStyle).scaledValue(for: size)
        return .system(size: scaled, weight: weight)
    }

    private var color: Color {
        if let custom = UIColor.brudcast(style.color, dark: style.darkColor) {
            return Color(custom)
        }
        return Color(role == .caption ? UIColor.secondaryLabel : UIColor.label)
    }

    private var textAlignment: TextAlignment {
        switch style.align {
        case .start, .left: return .leading
        case .center: return .center
        case .end, .right: return .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch style.align {
        case .start, .left: return .leading
        case .center: return .center
        case .end, .right: return .trailing
        }
    }
}

struct InAppImageView: View {
    let url: URL
    let aspectRatio: Double
    let alt: String
    let cornerRadius: CGFloat
    let width: CGFloat
    var height: CGFloat?

    var body: some View {
        let resolvedHeight = height ?? width / CGFloat(aspectRatio)
        Group {
            if let image = InAppImageLoader.shared.image(for: url) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(UIColor.secondarySystemFill)
            }
        }
        .frame(width: width, height: resolvedHeight)
        .clipped()
        .cornerRadius(cornerRadius)
        .accessibilityElement()
        .accessibilityLabel(Text(alt))
        .accessibilityAddTraits(.isImage)
        .accessibilityHidden(alt.isEmpty)
    }
}

struct InAppButtonView: View {
    let label: String
    let style: InAppButtonStyle
    let theme: InAppTheme
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: UIFontMetrics(forTextStyle: .body).scaledValue(for: 17), weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(labelColor))
                .padding(.horizontal, 16)
                .frame(width: width)
                .frame(minHeight: 48)
                .background(background)
                .contentShape(Rectangle())
        }
        .buttonStyle(InAppPressStyle())
    }

    private var fill: UIColor {
        UIColor.brudcast(style.background, dark: style.darkBackground) ?? theme.accent
    }

    private var labelColor: UIColor {
        if let custom = UIColor.brudcast(style.textColor, dark: style.darkTextColor) {
            return custom
        }
        switch style.variant {
        case .primary: return fill.contrastingLabel
        case .secondary, .text: return UIColor.brudcast(style.background, dark: style.darkBackground) ?? theme.accent
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style.variant {
        case .primary:
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(fill))
        case .secondary:
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(labelColor), lineWidth: 1)
        case .text:
            Color.clear
        }
    }
}

struct InAppPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct InAppCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(UIColor.label).opacity(0.6))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(UIColor.systemBackground).opacity(0.6)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(InAppPressStyle())
        .accessibilityLabel(Text("Close"))
    }
}

struct InAppBackground: View {
    let layout: InAppLayout
    var defaultColor: UIColor = .systemBackground

    static func color(layout: InAppLayout, default fallback: UIColor) -> UIColor {
        guard let light = UIColor.brudcast(layout.backgroundColor) else { return fallback }
        let dark = UIColor.brudcast(layout.darkBackgroundColor) ?? fallback
        return UIColor { traits in traits.userInterfaceStyle == .dark ? dark.resolvedColor(with: traits) : light }
    }

    var body: some View {
        ZStack {
            Color(Self.color(layout: layout, default: defaultColor))
            if let url = layout.backgroundImageURL, let image = InAppImageLoader.shared.image(for: url) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                Color.black.opacity(0.4)
            }
        }
    }
}

struct InAppHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A scroll view as tall as its content, up to a maximum.
struct InAppFittingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: contentHeight > maxHeight) {
            content()
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: InAppHeightKey.self, value: proxy.size.height)
                })
        }
        .onPreferenceChange(InAppHeightKey.self) { contentHeight = $0 }
        .frame(height: min(max(contentHeight, 1), maxHeight))
    }
}
#endif
