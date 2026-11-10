// The meeting screen: the current and next speaker on the left, the running
// order on the right.

import SwiftUI

struct MeetingView: View {
    @EnvironmentObject private var store: MeetingStore

    // Arrow keys and S are handled by MeetingStore.handleKey.
    var body: some View {
        if let state = store.state {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    StageView(state: state, windowWidth: geo.size.width)
                    SidebarView(state: state)
                        .frame(width: min(420, max(280, geo.size.width * 0.35)))
                }
            }
        }
    }
}

// MARK: Stage

private struct StageView: View {
    @EnvironmentObject private var store: MeetingStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var names
    let state: MeetingState
    let windowWidth: CGFloat

    /// Like CSS clamp(min, vw%, max), scaled by the zoom setting.
    private func size(_ lo: CGFloat, _ vw: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(hi, max(lo, windowWidth * vw)) * store.zoom
    }

    var body: some View {
        let z = store.zoom
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let cur = state.current {
                    SectionLabel(text: "Now speaking")
                    nameSlot(state.order[cur], slot: "current",
                             size: currentSize, otherSize: nextSize, lineHeight: 1.05,
                             weight: .bold, color: Theme.text)
                        .padding(.top, 12 * z)
                    nextBlock
                        .padding(.top, 40 * z)
                } else {
                    SectionLabel(text: "Finished")
                    Text(state.skippedCount > 0
                         ? "Everyone present has spoken (\(state.skippedCount) skipped)"
                         : "Everyone has spoken")
                        .font(.system(size: size(36, 0.05, 72), weight: .bold))
                        .foregroundStyle(Theme.done)
                        .padding(.top, 12 * z)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            footer
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 40)
    }

    private var currentSize: CGFloat { size(48, 0.08, 120) }
    private var nextSize: CGFloat { size(26, 0.032, 44) }

    private var nextBlock: some View {
        let nextPos = state.nextPos
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Up next")
            nameSlot(nextPos.map { state.order[$0] } ?? "Nobody — last speaker", slot: "next",
                     size: nextSize, otherSize: currentSize, lineHeight: 1.2,
                     weight: .semibold, color: nextPos == nil ? Theme.dim : Theme.next)
                .padding(.top, 6 * store.zoom)
        }
    }

    /// A fixed-height, one-line slot so a shrunk-to-fit name never shifts the
    /// layout. Moving forward, the same name in "Up next" and "Now speaking"
    /// shares a matched geometry id, so it travels up and grows into place
    /// (and the reverse for Back).
    private func nameSlot(_ name: String, slot: String, size: CGFloat, otherSize: CGFloat,
                          lineHeight: CGFloat, weight: Font.Weight, color: Color) -> some View {
        ZStack(alignment: .leading) {
            Text(name)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.1)
                .matchedGeometryEffect(id: reduceMotion ? "\(slot)|\(name)" : name, in: names,
                                       properties: .position)
                .id(name)
                .transition(transition(slot: slot, size: size, scale: otherSize / size))
        }
        .frame(maxWidth: .infinity, minHeight: size * lineHeight, maxHeight: size * lineHeight,
               alignment: .leading)
    }

    /// `scale`: the other slot's text size relative to this one, so a name
    /// arriving from that slot starts at the size it was there.
    private func transition(slot: String, size: CGFloat, scale: CGFloat) -> AnyTransition {
        if reduceMotion { return .opacity }
        let blurIn = AnyTransition.modifier(active: BlurModifier(radius: 8), identity: BlurModifier(radius: 0))
        switch (slot, store.motion) {
        case ("current", .back):
            // Back: the previous speaker drops in from above.
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: -size * 0.5)).combined(with: blurIn),
                removal: .opacity)
        case ("current", _):
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: scale)),
                removal: .opacity.combined(with: .offset(y: -size * 0.15))
                    .animation(.easeIn(duration: 0.25)))
        case (_, .back):
            // Back: the current speaker moves down and shrinks into "Up next".
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: scale)),
                removal: .opacity.animation(.easeOut(duration: 0.2)))
        default:
            // Forward: once the old next name has moved up, the new one rises in.
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: size * 0.3))
                    .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35).delay(0.6)),
                removal: .opacity.animation(.easeOut(duration: 0.2)))
        }
    }

    private var footer: some View {
        let z = store.zoom
        let style = PanelButtonStyle(zoom: z)
        return VStack(alignment: .leading, spacing: 10 * z) {
            Rectangle().fill(Theme.border).frame(height: 1)
                .padding(.bottom, 14 * z)
            let progress = Text("\(state.spokenCount) of \(state.order.count) spoken"
                                + (state.skippedCount > 0 ? " · \(state.skippedCount) skipped" : ""))
                .font(store.font(16))
                .foregroundStyle(Theme.muted)
                .fixedSize()
            let buttons = HStack(spacing: 10 * z) {
                Button("← Back", action: store.back)
                    .buttonStyle(style)
                    .disabled(state.history.isEmpty)
                Button("Skip", action: store.skipCurrent)
                    .buttonStyle(style)
                    .disabled(state.current == nil)
                Button("Next →", action: store.next)
                    .buttonStyle(PanelButtonStyle(primary: true, zoom: z))
                    .disabled(state.current == nil)
            }
            // Progress and buttons on one line, or stacked in a narrow window.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10 * z) {
                    progress
                    Spacer(minLength: 0)
                    buttons
                }
                VStack(alignment: .leading, spacing: 10 * z) {
                    progress
                    buttons
                }
            }
            HStack(spacing: 4 * z) {
                Kbd(key: "→"); Text("next  ")
                Kbd(key: "←"); Text("back  ")
                Kbd(key: "S"); Text("skip current speaker")
            }
            .font(store.font(14))
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
        }
        .transaction { $0.animation = nil }
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

// MARK: Sidebar

private struct SidebarView: View {
    @EnvironmentObject private var store: MeetingStore
    let state: MeetingState

    var body: some View {
        let z = store.zoom
        let tool = PanelButtonStyle(size: .compact, zoom: z)
        VStack(spacing: 0) {
            let tools = HStack(spacing: 8 * z) {
                Button("Reshuffle", action: store.reshuffle).buttonStyle(tool)
                Button("Reset", action: store.resetSkipped).buttonStyle(tool)
                    .help("Unskip everyone")
                    .disabled(state.skippedCount == 0)
                Button("Edit", action: store.editNames).buttonStyle(tool)
                    .help("Edit names")
            }
            // Heading and buttons side by side, or stacked when the sidebar is narrow.
            ViewThatFits(in: .horizontal) {
                HStack {
                    SectionLabel(text: "Running order").fixedSize()
                    Spacer(minLength: 12)
                    tools
                }
                VStack(alignment: .leading, spacing: 10 * z) {
                    SectionLabel(text: "Running order")
                    tools
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(state.order.enumerated()), id: \.element) { i, name in
                                RowView(index: i, name: name, status: state.status[i],
                                        isCurrent: i == state.current, isNext: i == state.nextPos)
                            }
                        }
                        .padding(.horizontal, 12)
                        // The list just updates; only the stage animates.
                        .transaction { $0.animation = nil }
                        // Spare room below the last name so the end of the list can scroll up too.
                        .padding(.bottom, geo.size.height * 0.8)
                    }
                    // Keep the current speaker about 20% down the list so a couple of
                    // names above and the upcoming names below stay visible.
                    .onChange(of: state, initial: true) {
                        guard let cur = state.current else { return }
                        withAnimation(.easeInOut(duration: 0.4)) {
                            proxy.scrollTo(state.order[cur], anchor: UnitPoint(x: 0, y: 0.2))
                        }
                    }
                }
            }
        }
        .background(Theme.panel)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
    }
}

private struct RowView: View {
    @EnvironmentObject private var store: MeetingStore
    private let hovering = State(initialValue: false) // see PanelButton
    let index: Int
    let name: String
    let status: Status
    let isCurrent: Bool
    let isNext: Bool

    private var tag: (String, Color)? {
        if isCurrent { return ("Speaking", Theme.accent) }
        if isNext { return ("Next", Theme.next) }
        switch status {
        case .spoken: return ("✓", Theme.done)
        // Skipped rows show an Unskip button instead of a tag.
        case .skipped, .pending: return nil
        }
    }

    private var nameColor: Color {
        if isCurrent { return Theme.text }
        if isNext { return Theme.next }
        switch status {
        case .spoken: return Theme.dim
        case .skipped: return Theme.skip
        case .pending: return Theme.text
        }
    }

    var body: some View {
        let z = store.zoom
        let mini = PanelButtonStyle(size: .mini, zoom: z)
        HStack(spacing: 12 * z) {
            Text("\(index + 1)")
                .font(store.font(14).monospacedDigit())
                .foregroundStyle(Theme.dim)
                .frame(width: 26 * z, alignment: .trailing)
            Text(name)
                .font(store.font(19, isCurrent ? .bold : .regular))
                .foregroundStyle(nameColor)
                .strikethrough(status == .skipped && !isCurrent, color: Theme.skip)
                .opacity(status == .skipped && !isCurrent ? 0.8 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let (text, color) = tag {
                Text(text.uppercased())
                    .font(store.font(12, .semibold))
                    .tracking(12 * 0.08 * z)
                    .foregroundStyle(color)
                    .fixedSize()
            }
            if status == .skipped {
                Button("Unskip") { store.toggleSkip(index) }
                    .buttonStyle(mini)
            }
        }
        // Skip and Defer appear over the right-hand end on hover rather than
        // reserving space, so names get the full width.
        .overlay(alignment: .trailing) {
            if hovering.wrappedValue && status == .pending {
                HStack(spacing: 8 * z) {
                    Button("Defer") { store.deferSpeaker(index) }
                        .buttonStyle(mini)
                        .help("Move to the bottom of the list")
                    Button("Skip") { store.toggleSkip(index) }
                        .buttonStyle(mini)
                }
                .padding(.leading, 12 * z)
                .background(isCurrent ? Theme.accentBg : Theme.panel)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9 * z)
        .background(isCurrent ? Theme.accentBg : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isCurrent ? Theme.accent : .clear))
        .contentShape(Rectangle())
        .onHover { hovering.wrappedValue = $0 }
    }
}
