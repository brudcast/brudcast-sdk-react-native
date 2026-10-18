import Foundation

/// The highest design `schemaVersion` this SDK can draw.
public let BrudcastSupportedSchemaVersion = 1

public enum InAppFormat: String {
    case modal
    case banner
    case fullscreen
    case inboxOnly = "inbox_only"
}

public enum InAppPosition: String {
    case top
    case center
    case bottom
}

enum InAppTextRole: String {
    case title
    case body
    case caption
}

enum InAppTextWeight: String {
    case regular
    case medium
    case bold
}

enum InAppTextAlign: String {
    case start
    case center
    case end
    case left
    case right
}

enum InAppButtonVariant: String {
    case primary
    case secondary
    case text
}

enum InAppActionType: String {
    case deeplink
    case url
    case dismiss
    case customEvent = "custom_event"
    case requestPushPermission = "request_push_permission"
}

struct InAppAction: Equatable {
    var type: InAppActionType
    var value: String?
    var opensInApp: Bool

    static func parse(_ raw: Any?) -> InAppAction? {
        guard let object = raw as? [String: Any],
              let typeRaw = object["type"] as? String,
              let type = InAppActionType(rawValue: typeRaw) else {
            return nil
        }
        let value = (object["value"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        switch type {
        case .deeplink, .url, .customEvent:
            guard value != nil else { return nil }
        case .dismiss, .requestPushPermission:
            break
        }
        let target = object["target"] as? String
        return InAppAction(type: type, value: value, opensInApp: type == .url && target != "browser")
    }
}

struct InAppTextStyle: Equatable {
    var size: Double?
    var weight: InAppTextWeight?
    var align: InAppTextAlign
    var color: String?
    var darkColor: String?
}

struct InAppButtonStyle: Equatable {
    var variant: InAppButtonVariant
    var background: String?
    var textColor: String?
    var darkBackground: String?
    var darkTextColor: String?
}

indirect enum InAppBlock: Equatable {
    case text(id: String, role: InAppTextRole, text: String, style: InAppTextStyle)
    case image(id: String, url: URL, aspectRatio: Double, alt: String, cornerRadius: Double?)
    case button(id: String, label: String, action: InAppAction, style: InAppButtonStyle)
    case spacer(id: String, height: Double)
    case divider(id: String, color: String?, thickness: Double)
    case columns(id: String, children: [InAppBlock])

    var id: String {
        switch self {
        case .text(let id, _, _, _), .image(let id, _, _, _, _), .button(let id, _, _, _),
             .spacer(let id, _), .divider(let id, _, _), .columns(let id, _):
            return id
        }
    }

    var imageURLs: [URL] {
        switch self {
        case .image(_, let url, _, _, _):
            return [url]
        case .columns(_, let children):
            return children.flatMap(\.imageURLs)
        default:
            return []
        }
    }
}

struct InAppLayout: Equatable {
    var position: InAppPosition
    var dismissible: Bool
    var overlayColor: String
    var overlayOpacity: Double
    var backgroundColor: String?
    var backgroundImageURL: URL?
    var darkBackgroundColor: String?
    var cornerRadius: Double
    var padding: Double
    var autoDismissSeconds: Double?
    var bannerAction: InAppAction?
}

/// Why a design cannot be drawn.
enum InAppDesignError: Error, Equatable {
    case unsupportedVersion(Int)
    case unknownFormat(String)
    case unknownBlock(String)
    case invalidBlock(String)
    case empty
}

struct InAppDesign: Equatable {
    var schemaVersion: Int
    var format: InAppFormat
    var layout: InAppLayout
    var blocks: [InAppBlock]

    var imageURLs: [URL] {
        blocks.flatMap(\.imageURLs) + [layout.backgroundImageURL].compactMap { $0 }
    }

    var title: String? {
        for block in blocks {
            if case .text(_, .title, let text, _) = block {
                return text
            }
        }
        return nil
    }

    var bodyText: String? {
        for block in blocks {
            if case .text(_, .body, let text, _) = block {
                return text
            }
        }
        return nil
    }

    var firstImageURL: URL? {
        blocks.flatMap(\.imageURLs).first
    }

    /// Reads a design document, refusing anything this SDK cannot draw faithfully.
    ///
    /// - Parameter raw: The decoded `design` object.
    /// - Returns: The design.
    /// - Throws: `InAppDesignError` for a newer schema version, an unknown format or block, or a block
    ///   missing what it needs.
    static func parse(_ raw: Any?) throws -> InAppDesign {
        guard let object = raw as? [String: Any] else { throw InAppDesignError.empty }
        let version = (object["schemaVersion"] as? NSNumber)?.intValue ?? 0
        guard version >= 1, version <= BrudcastSupportedSchemaVersion else {
            throw InAppDesignError.unsupportedVersion(version)
        }
        let formatRaw = object["format"] as? String ?? ""
        guard let format = InAppFormat(rawValue: formatRaw) else {
            throw InAppDesignError.unknownFormat(formatRaw)
        }
        let layout = parseLayout(object["layout"] as? [String: Any] ?? [:], format: format)
        let rawBlocks = object["blocks"] as? [Any] ?? []
        let blocks = try rawBlocks.enumerated().map { index, raw in try parseBlock(raw, index: index, nested: false) }
        guard !blocks.isEmpty else { throw InAppDesignError.empty }
        return InAppDesign(schemaVersion: version, format: format, layout: layout, blocks: blocks)
    }

    private static func parseLayout(_ object: [String: Any], format: InAppFormat) -> InAppLayout {
        let overlay = object["overlay"] as? [String: Any] ?? [:]
        let background = object["background"] as? [String: Any] ?? [:]
        let dark = object["darkMode"] as? [String: Any] ?? [:]
        let darkBackground = dark["backgroundColor"] as? String
            ?? (dark["background"] as? [String: Any])?["color"] as? String
        let defaultPosition: InAppPosition = format == .banner ? .top : .center
        let position = (object["position"] as? String).flatMap(InAppPosition.init(rawValue:)) ?? defaultPosition
        return InAppLayout(
            position: format == .banner && position == .center ? .top : position,
            dismissible: object["dismissible"] as? Bool ?? true,
            overlayColor: overlay["color"] as? String ?? "#000000",
            overlayOpacity: clamp(number(overlay["opacity"]) ?? 0.5, 0, 1),
            backgroundColor: background["color"] as? String,
            backgroundImageURL: (background["imageUrl"] as? String).flatMap(webURL),
            darkBackgroundColor: darkBackground,
            cornerRadius: clamp(number(object["cornerRadius"]) ?? 16, 0, 48),
            padding: clamp(number(object["padding"]) ?? 24, 0, 64),
            autoDismissSeconds: number(object["autoDismissSeconds"]).flatMap { $0 > 0 ? min($0, 60) : nil },
            bannerAction: InAppAction.parse(object["bannerAction"])
        )
    }

    private static func parseBlock(_ raw: Any, index: Int, nested: Bool) throws -> InAppBlock {
        guard let object = raw as? [String: Any], let type = object["type"] as? String else {
            throw InAppDesignError.invalidBlock("block \(index)")
        }
        let id = object["id"] as? String ?? "block_\(index)"
        switch type {
        case "text":
            let role = (object["role"] as? String).flatMap(InAppTextRole.init(rawValue:)) ?? .body
            guard let text = object["text"] as? String, !text.isEmpty else {
                throw InAppDesignError.invalidBlock(id)
            }
            let style = object["style"] as? [String: Any] ?? [:]
            return .text(id: id, role: role, text: text, style: InAppTextStyle(
                size: number(style["size"]).map { clamp($0, 10, 64) },
                weight: (style["weight"] as? String).flatMap(InAppTextWeight.init(rawValue:)),
                align: (style["align"] as? String).flatMap(InAppTextAlign.init(rawValue:)) ?? .start,
                color: style["color"] as? String,
                darkColor: style["darkColor"] as? String
            ))
        case "image":
            guard let url = (object["url"] as? String).flatMap(webURL) else {
                throw InAppDesignError.invalidBlock(id)
            }
            return .image(
                id: id,
                url: url,
                aspectRatio: clamp(number(object["aspectRatio"]) ?? 1.6, 0.25, 4),
                alt: object["alt"] as? String ?? "",
                cornerRadius: number(object["cornerRadius"])
            )
        case "button":
            guard let label = object["label"] as? String, !label.isEmpty,
                  let action = InAppAction.parse(object["action"]) else {
                throw InAppDesignError.invalidBlock(id)
            }
            let style = object["style"] as? [String: Any] ?? [:]
            return .button(id: id, label: label, action: action, style: InAppButtonStyle(
                variant: (style["variant"] as? String).flatMap(InAppButtonVariant.init(rawValue:)) ?? .primary,
                background: style["background"] as? String,
                textColor: style["textColor"] as? String,
                darkBackground: style["darkBackground"] as? String,
                darkTextColor: style["darkTextColor"] as? String
            ))
        case "spacer":
            return .spacer(id: id, height: clamp(number(object["height"]) ?? 16, 0, 120))
        case "divider":
            return .divider(id: id, color: object["color"] as? String, thickness: clamp(number(object["thickness"]) ?? 1, 0.5, 8))
        case "columns":
            guard !nested else { throw InAppDesignError.invalidBlock(id) }
            let rawChildren = object["children"] as? [Any] ?? []
            let children = try rawChildren.prefix(2).enumerated().map { childIndex, child in
                try parseBlock(child, index: childIndex, nested: true)
            }
            guard !children.isEmpty else { throw InAppDesignError.invalidBlock(id) }
            return .columns(id: id, children: children)
        default:
            throw InAppDesignError.unknownBlock(type)
        }
    }

    private static func number(_ raw: Any?) -> Double? {
        (raw as? NSNumber)?.doubleValue
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }
}
