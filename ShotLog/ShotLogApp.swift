import SwiftUI
import SwiftData
import Observation

enum AppTab: Hashable {
    case log, history, stats
}

@Observable
final class AppState {
    var tab: AppTab = .log
    /// Set by "Brew again" so the Log tab can load those settings.
    var template: ShotDraft?
    var templateStamp = UUID()

    func brewAgain(_ shot: Shot) {
        var d = ShotDraft(from: shot, full: false)
        d.date = Date()
        template = d
        templateStamp = UUID()
        tab = .log
    }
}

@main
struct ShotLogApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
        }
        .modelContainer(for: [Shot.self, BeanBag.self])
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            NavigationStack { LogShotView(editing: nil) }
                .tabItem { Label("Log shot", systemImage: "cup.and.saucer.fill") }
                .tag(AppTab.log)
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "calendar") }
                .tag(AppTab.history)
            NavigationStack { StatsView() }
                .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.stats)
        }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
