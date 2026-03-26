import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    var sparkleUpdater: SparkleUpdater

    var body: some View {
        TabView {
            AccountsTab(appState: appState)
                .tabItem { Label("Accounts", systemImage: "person.2") }

            RepositoriesTab(appState: appState)
                .tabItem { Label("Repositories", systemImage: "folder") }

            GeneralTab(appState: appState, sparkleUpdater: sparkleUpdater)
                .tabItem { Label("General", systemImage: "gearshape") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            let hasVisibleSettings = NSApp.windows.contains {
                $0.isVisible && $0.title.contains("Settings")
            }
            if !hasVisibleSettings {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
