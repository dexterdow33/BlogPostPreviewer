#if os(iOS)
import SwiftUI
import UIKit

/// Granite State Report house style, from the site's own pages (nh-bills/style.css and
/// site/wp-page-head.html): navy and rust on warm paper, Georgia for reading.
public enum GSRTheme {
    public static let navy = Color(hex: 0x1A2E4A)
    public static let rust = Color(hex: 0xB14A37)
    public static let rustSoft = Color(hex: 0xF5E8DD)
    public static let ink = Color(hex: 0x23211E)
    public static let ink2 = Color(hex: 0x5C574E)
    public static let ink3 = Color(hex: 0x857E72)
    public static let paper = Color(hex: 0xFFFFFF)
    public static let paper2 = Color(hex: 0xFAF7F2)
    public static let paper3 = Color(hex: 0xF2EDE4)
    public static let rule = Color(hex: 0xE6E0D6)
    public static let rule2 = Color(hex: 0xD9D2C6)
    public static let ground = Color(hex: 0xEFE9DF)
    public static let good = Color(hex: 0x2E7D4F)

    /// Georgia, scaled with Dynamic Type from the given text style.
    public static func serif(_ style: Font.TextStyle, bold: Bool = false, italic: Bool = false) -> Font {
        let name: String
        switch (bold, italic) {
        case (true, true): name = "Georgia-BoldItalic"
        case (true, false): name = "Georgia-Bold"
        case (false, true): name = "Georgia-Italic"
        default: name = "Georgia"
        }
        return .custom(name, size: baseSize(style), relativeTo: style)
    }

    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 32
        case .title: return 27
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .subheadline: return 15
        case .callout: return 16
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        default: return 17
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// The small uppercase rust label above headings on the site ("TOOLS · TIPS").
public struct Kicker: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .default).weight(.bold))
            .tracking(2)
            .foregroundStyle(GSRTheme.rust)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The blackletter wordmark when the bundle carries it (the app), else the name in type
/// (the share extension, which ships without the image).
public struct Masthead: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 8) {
            Rectangle().fill(GSRTheme.navy).frame(height: 4)
            if UIImage(named: "Masthead") != nil {
                Image("Masthead")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320)
                    .accessibilityLabel("Granite State Report")
            } else {
                Text("Granite State Report")
                    .font(GSRTheme.serif(.title, bold: true))
                    .foregroundStyle(GSRTheme.navy)
            }
            Text("Independent New Hampshire Journalism · Northfield, NH".uppercased())
                .font(.system(.caption2).weight(.bold))
                .tracking(1.6)
                .foregroundStyle(GSRTheme.rust)
                .multilineTextAlignment(.center)
            Rectangle().fill(GSRTheme.rule2).frame(height: 1)
        }
        .padding(.bottom, 4)
    }
}

/// The site's primary button: rust, white text, square-ish corners.
public struct GSRButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    public init(prominent: Bool = true) { self.prominent = prominent }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline))
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .foregroundStyle(prominent ? Color.white : GSRTheme.rust)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(prominent ? (isEnabled ? GSRTheme.rust : GSRTheme.ink3) : GSRTheme.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(prominent ? Color.clear : GSRTheme.rust, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
#endif
