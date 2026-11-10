// Colours and shared bits of styling, matching the old web version.

import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0f1115)
    static let panel = Color(hex: 0x171a21)
    static let panel2 = Color(hex: 0x1e222b)
    static let border = Color(hex: 0x2a2f3a)
    static let text = Color(hex: 0xe8eaee)
    static let muted = Color(hex: 0x8a91a0)
    static let dim = Color(hex: 0x5b6170)
    static let accent = Color(hex: 0x4fb3ff)
    static let accentBg = Color(hex: 0x12324a)
    static let next = Color(hex: 0xf2c14e)
    static let done = Color(hex: 0x4cc38a)
    static let skip = Color(hex: 0xe5736b)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255,
                  green: Double(hex >> 8 & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

/// Small uppercase heading, e.g. "NOW SPEAKING".
struct SectionLabel: View {
    @EnvironmentObject private var store: MeetingStore
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(store.font(15, .semibold))
            .tracking(15 * 0.12 * store.zoom)
            .foregroundStyle(Theme.muted)
    }
}

/// A key cap, e.g. in the "→ next" hint.
struct Kbd: View {
    @EnvironmentObject private var store: MeetingStore
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 12 * store.zoom, design: .monospaced))
            .padding(.horizontal, 6 * store.zoom)
            .padding(.vertical, 1)
            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
    }
}

struct PanelButtonStyle: ButtonStyle {
    enum Size { case regular, compact, mini }

    var primary = false
    var size: Size = .regular
    var zoom: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        PanelButton(configuration: configuration, primary: primary, size: size, zoom: zoom)
    }
}

private struct PanelButton: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    let size: PanelButtonStyle.Size
    let zoom: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    // `@State` is a compiler macro in recent SDKs and the Command Line Tools
    // don't ship its plugin, so use the State type directly.
    private let hovering = State(initialValue: false)

    var body: some View {
        let (fontSize, v, h): (CGFloat, CGFloat, CGFloat) = switch size {
        case .regular: (16, 8, 14)
        case .compact: (13, 5, 10)
        case .mini: (12, 3, 9)
        }
        configuration.label
            .lineLimit(1)
            .fixedSize()
            .font(.system(size: fontSize * zoom, weight: primary ? .semibold : .regular))
            .foregroundStyle(primary ? Color(hex: 0x06121c) : Theme.text)
            .padding(.vertical, v * zoom)
            .padding(.horizontal, h * zoom)
            .background(primary ? Theme.accent : Theme.panel2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(primary ? Theme.accent : hovering.wrappedValue && isEnabled ? Theme.muted : Theme.border))
            .contentShape(Rectangle())
            .brightness(configuration.isPressed ? -0.08 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering.wrappedValue = $0 }
    }
}
