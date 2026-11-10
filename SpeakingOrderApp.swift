// Speaking Order: a single-window macOS app that randomises who speaks next
// in a meeting. Build with ./build.sh (needs Xcode Command Line Tools).

import SwiftUI

@main
struct SpeakingOrderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MeetingStore()

    var body: some Scene {
        Window("Speaking Order", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 720, minHeight: 480)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1200, height: 760)
        .windowResizability(.contentMinSize)
        .commands { MeetingCommands(store: store) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Names aren't dictionary words; don't underline them all in red.
        UserDefaults.standard.set(false, forKey: "NSAllowContinuousSpellChecking")
        // The old WebKit version kept its own saved window frame; drop it.
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame MainWindow")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject private var store: MeetingStore

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if store.showingSetup {
                SetupView()
            } else {
                MeetingView()
            }
        }
        .foregroundStyle(Theme.text)
    }
}

struct MeetingCommands: Commands {
    @ObservedObject var store: MeetingStore

    var body: some Commands {
        CommandMenu("Meeting") {
            // Arrow keys and S are handled by the meeting screen itself, so they
            // never reach the names box; the titles just show them.
            Button("Next Speaker  →", action: store.next)
                .disabled(!store.canAdvance)
            Button("Back  ←", action: store.back)
                .disabled(!store.canGoBack)
            Button("Skip Current Speaker  S", action: store.skipCurrent)
                .disabled(!store.canAdvance)
            Divider()
            Button("Reshuffle", action: store.reshuffle)
                .keyboardShortcut("r")
                .disabled(!store.inMeeting)
            Button("Reset Skipped", action: store.resetSkipped)
                .disabled(!store.hasSkipped)
            Button("Edit Names…", action: store.editNames)
                .keyboardShortcut("e")
                .disabled(!store.inMeeting)
        }
        CommandGroup(before: .toolbar) {
            Button("Actual Size", action: store.resetZoom)
                .keyboardShortcut("0")
            Button("Zoom In", action: store.zoomIn)
                .keyboardShortcut("+")
            Button("Zoom Out", action: store.zoomOut)
                .keyboardShortcut("-")
            Divider()
        }
    }
}
