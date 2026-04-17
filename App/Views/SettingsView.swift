import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    var sparkleUpdater: SparkleUpdater

    var body: some View {
        TabView(selection: $appState.selectedSettingsTab) {
            AccountsTab(appState: appState)
                .tabItem { Label("Accounts", systemImage: "person.2") }
                .tag(AppState.SettingsTab.accounts)

            RepositoriesTab(appState: appState)
                .tabItem { Label("Repositories", systemImage: "folder") }
                .tag(AppState.SettingsTab.repositories)

            GeneralTab(appState: appState, sparkleUpdater: sparkleUpdater)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(AppState.SettingsTab.general)

            AboutTab(sparkleUpdater: sparkleUpdater)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(AppState.SettingsTab.about)
        }
        .frame(minWidth: 520, maxWidth: 520,
               minHeight: 350, idealHeight: 420, maxHeight: 800)
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
