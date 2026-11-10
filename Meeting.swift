// The meeting model: who's in the running order, who has spoken or been
// skipped, and the actions that move through it. Saved to UserDefaults as
// JSON in the same shape the old WebKit version used, so a meeting in
// progress carries over.

import AppKit
import SwiftUI

enum Status: String, Codable {
    case pending, spoken, skipped
}

/// One Next or Skip, so Back can undo it.
struct Step: Codable, Equatable {
    var pos: Int
    var action: Status
}

struct MeetingState: Codable, Equatable {
    var order: [String]      // names in running order
    var status: [Status]     // per position
    var current: Int?        // position of current speaker, nil when nobody is left
    var history: [Step]

    /// First pending position after `from`, wrapping round so anyone unskipped
    /// earlier in the list is picked up after the end.
    func findPending(after from: Int?, excluding exclude: Int? = nil) -> Int? {
        let n = order.count
        guard n > 0 else { return nil }
        let start = from ?? -1
        for k in 1...n {
            let i = ((start + k) % n + n) % n
            if i != exclude && status[i] == .pending { return i }
        }
        return nil
    }

    var nextPos: Int? { current.flatMap { findPending(after: $0, excluding: $0) } }
    var spokenCount: Int { status.filter { $0 == .spoken }.count }
    var skippedCount: Int { status.filter { $0 == .skipped }.count }
}

/// Direction of the last move, used to animate the stage names.
enum Motion {
    case none, forward, back
}

private let stateKey = "speakingOrderState"
private let zoomKey = "zoom"

@MainActor
final class MeetingStore: ObservableObject {
    @Published private(set) var state: MeetingState?
    @Published private(set) var showingSetup: Bool
    @Published var setupText = ""
    @Published private(set) var motion: Motion = .none
    @Published private(set) var zoom: CGFloat

    init() {
        let saved = Self.load()
        state = saved
        showingSetup = saved == nil
        let z = UserDefaults.standard.double(forKey: zoomKey)
        zoom = z == 0 ? 1 : CGFloat(z)

        // Watch keys app-wide rather than relying on a view having focus.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) ?? false } ? nil : event
        }
    }

    /// → ↓ next, ← ↑ back, S skip, during a meeting. Returns true if handled.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard inMeeting,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              !(NSApp.keyWindow?.firstResponder is NSText) else { return false }
        switch event.keyCode {
        case 124, 125: next()   // → ↓
        case 123, 126: back()   // ← ↑
        default:
            guard event.charactersIgnoringModifiers?.lowercased() == "s" else { return false }
            skipCurrent()
        }
        return true
    }

    var inMeeting: Bool { !showingSetup && state != nil }
    var canAdvance: Bool { inMeeting && state?.current != nil }
    var canGoBack: Bool { inMeeting && !(state?.history.isEmpty ?? true) }
    var hasSkipped: Bool { inMeeting && (state?.skippedCount ?? 0) > 0 }

    // MARK: Names

    /// One name per line. Keeps only letters, spaces, and hyphens/apostrophes
    /// inside names, so pasted bullets, numbering and tabs are dropped.
    nonisolated static func parseNames(_ text: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let name = String(line)
                .replacing(#/[^\p{L}\p{M}\s'’-]/#, with: " ")
                .replacing(#/\s+/#, with: " ")
                .replacing(#/^[\s'’-]+|[\s'’-]+$/#, with: "")
            if !name.isEmpty && seen.insert(name.lowercased()).inserted { names.append(name) }
        }
        return names
    }

    func startFromSetup() {
        let names = Self.parseNames(setupText)
        guard !names.isEmpty else { return }
        start(names)
        showingSetup = false
    }

    func editNames() {
        guard let state else { return }
        setupText = state.order.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .joined(separator: "\n")
        showingSetup = true
    }

    /// `skipped`: names to carry over as skipped (used by Reshuffle).
    private func start(_ names: [String], skipped: Set<String> = []) {
        let order = names.shuffled()
        var s = MeetingState(order: order,
                             status: order.map { skipped.contains($0) ? .skipped : .pending },
                             current: nil, history: [])
        s.current = s.findPending(after: nil)
        commit(s, .forward)
    }

    func reshuffle() {
        guard let state else { return }
        let skipped = zip(state.order, state.status).filter { $0.1 == .skipped }.map(\.0)
        start(state.order, skipped: Set(skipped))
    }

    // MARK: Moving through the order

    func next() {
        apply(.forward) { s in
            guard let pos = s.current else { return }
            s.status[pos] = .spoken
            s.history.append(Step(pos: pos, action: .spoken))
            s.current = s.findPending(after: pos)
        }
    }

    func skipCurrent() {
        apply(.forward) { s in
            guard let pos = s.current else { return }
            s.status[pos] = .skipped
            s.history.append(Step(pos: pos, action: .skipped))
            s.current = s.findPending(after: pos)
        }
    }

    func back() {
        apply(.back) { s in
            guard let last = s.history.popLast() else { return }
            if let cur = s.current { s.status[cur] = .pending }
            s.status[last.pos] = .pending
            s.current = last.pos
        }
    }

    func toggleSkip(_ pos: Int) {
        guard let state else { return }
        if state.status[pos] != .skipped && pos == state.current {
            skipCurrent()
            return
        }
        apply(.forward) { s in
            if s.status[pos] == .skipped {
                s.status[pos] = .pending
                if s.current == nil { s.current = pos }
            } else {
                s.status[pos] = .skipped
            }
        }
    }

    /// Move someone who hasn't spoken to the bottom of the list. Positions after
    /// them shift up by one, so current and history positions are remapped too.
    func deferSpeaker(_ pos: Int) {
        guard let state else { return }
        let n = state.order.count
        if pos == n - 1 && pos != state.current { return }
        apply(pos == state.current ? .forward : .none) { s in
            let remap = { (i: Int) in i == pos ? n - 1 : i > pos ? i - 1 : i }
            s.order.append(s.order.remove(at: pos))
            s.status.remove(at: pos)
            s.status.append(.pending)
            for i in s.history.indices { s.history[i].pos = remap(s.history[i].pos) }
            if pos == s.current {
                // Hand over to whoever is next; that's the deferred person only if
                // nobody else is waiting.
                s.current = s.findPending(after: pos - 1)
            } else if let cur = s.current {
                s.current = remap(cur)
            }
        }
    }

    func resetSkipped() {
        apply(.none) { s in
            s.status = s.status.map { $0 == .skipped ? .pending : $0 }
            if s.current == nil { s.current = s.findPending(after: nil) }
        }
    }

    // MARK: Zoom

    func zoomIn() { setZoom(zoom + 0.1) }
    func zoomOut() { setZoom(zoom - 0.1) }
    func resetZoom() { setZoom(1) }

    private func setZoom(_ z: CGFloat) {
        zoom = min(2.5, max(0.5, (z * 10).rounded() / 10))
        UserDefaults.standard.set(Double(zoom), forKey: zoomKey)
    }

    /// System font at `size` points, scaled by the View menu zoom.
    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * zoom, weight: weight)
    }

    // MARK: Changes and saving

    private func apply(_ motion: Motion, _ change: (inout MeetingState) -> Void) {
        guard var s = state else { return }
        change(&s)
        if s != state { commit(s, motion) }
    }

    private func commit(_ s: MeetingState, _ motion: Motion) {
        self.motion = motion
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduce ? .easeInOut(duration: 0.2) : .timingCurve(0.65, 0, 0.35, 1, duration: 0.6)) {
            state = s
        }
        save()
    }

    private func save() {
        guard let state, let data = try? JSONEncoder().encode(state),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: stateKey)
    }

    private static func load() -> MeetingState? {
        guard let json = UserDefaults.standard.string(forKey: stateKey),
              let s = try? JSONDecoder().decode(MeetingState.self, from: Data(json.utf8)),
              !s.order.isEmpty, s.status.count == s.order.count else { return nil }
        return s
    }
}
