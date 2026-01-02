import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultInterval") private var defaultInterval = "1000"
    @AppStorage("maxDataPoints") private var maxDataPoints = "3600"
    @AppStorage("defaultCommunity") private var defaultCommunity = "public"
    @AppStorage("graphRefreshRate") private var graphRefreshRate = "1.0"
    
    var body: some View {
        TabView {
            GeneralSettingsView(
                defaultInterval: $defaultInterval,
                maxDataPoints: $maxDataPoints,
                graphRefreshRate: $graphRefreshRate
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            SNMPSettingsView(
                defaultCommunity: $defaultCommunity
            )
            .tabItem {
                Label("SNMP", systemImage: "network")
            }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @Binding var defaultInterval: String
    @Binding var maxDataPoints: String
    @Binding var graphRefreshRate: String
    
    var body: some View {
        Form {
            Section("Polling") {
                TextField("Default Interval (ms)", text: $defaultInterval)
                TextField("Max Data Points", text: $maxDataPoints)
            }
            
            Section("Display") {
                TextField("Graph Refresh Rate (sec)", text: $graphRefreshRate)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct SNMPSettingsView: View {
    @Binding var defaultCommunity: String
    
    var body: some View {
        Form {
            Section("SNMPv2c Defaults") {
                TextField("Community", text: $defaultCommunity)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
