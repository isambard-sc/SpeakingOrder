// The names screen: paste a list, then randomise and start.

import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: MeetingStore
    @FocusState private var focused: Bool

    var body: some View {
        let count = MeetingStore.parseNames(store.setupText).count
        let z = store.zoom
        VStack(alignment: .leading, spacing: 0) {
            Text("Speaking order")
                .font(store.font(28, .bold))
                .padding(.bottom, 8 * z)
            Text("Paste everyone's name, one per line. They'll be put in a random order.")
                .font(store.font(16))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 20 * z)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.setupText)
                    .font(store.font(17))
                    .lineSpacing(17 * 0.5 * z)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .focused($focused)
                if store.setupText.isEmpty {
                    Text("Alice\nBob\nCharlie")
                        .font(store.font(17))
                        .lineSpacing(17 * 0.5 * z)
                        .foregroundStyle(Theme.dim)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(14 * z)
            .frame(minHeight: 320 * z, maxHeight: .infinity)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(focused ? Theme.accent : Theme.border, lineWidth: focused ? 2 : 1))

            HStack(spacing: 12 * z) {
                Button("Randomise & start", action: store.startFromSetup)
                    .buttonStyle(PanelButtonStyle(primary: true, zoom: z))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(count == 0)
                if count > 0 {
                    Text("\(count) name\(count == 1 ? "" : "s")")
                        .font(store.font(16))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.top, 16 * z)
        }
        .frame(maxWidth: 640 * z)
        .padding(.horizontal, 16)
        .padding(.vertical, 48 * z)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
    }
}
