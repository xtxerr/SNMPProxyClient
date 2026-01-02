import SwiftUI

@main
struct SNMPProxyClientApp: App {
    @StateObject private var proxyClient = ProxyClient()
    @StateObject private var timeSeriesStore = TimeSeriesStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(proxyClient)
                .environmentObject(timeSeriesStore)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Connect...") {
                    NotificationCenter.default.post(name: .showConnectSheet, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Button("Add Target...") {
                    NotificationCenter.default.post(name: .showAddTargetSheet, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(proxyClient.state != .connected)
            }
        }
        
        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let showConnectSheet = Notification.Name("showConnectSheet")
    static let showAddTargetSheet = Notification.Name("showAddTargetSheet")
}
