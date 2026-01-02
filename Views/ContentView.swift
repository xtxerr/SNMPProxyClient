import SwiftUI

struct ContentView: View {
    @EnvironmentObject var proxyClient: ProxyClient
    @EnvironmentObject var timeSeriesStore: TimeSeriesStore
    
    @State private var showConnectSheet = false
    @State private var showAddTargetSheet = false
    @State private var showServerStatusSheet = false
    @State private var showSessionInfoSheet = false
    @State private var showConfigSheet = false
    @State private var selectedTargetForDetail: String?
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                showAddTargetSheet: $showAddTargetSheet,
                selectedTargetForDetail: $selectedTargetForDetail
            )
        } detail: {
            if timeSeriesStore.selectedSeriesIDs.isEmpty {
                ContentUnavailableView(
                    "No Targets Selected",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Select targets from the sidebar to view their graphs")
                )
            } else {
                GraphContainerView()
            }
        }
        .navigationTitle("SNMP Proxy")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Server menu
                Menu {
                    Button(action: { showServerStatusSheet = true }) {
                        Label("Server Status", systemImage: "server.rack")
                    }
                    .disabled(!proxyClient.state.isConnected)
                    
                    Button(action: { showSessionInfoSheet = true }) {
                        Label("Session Info", systemImage: "person.circle")
                    }
                    .disabled(!proxyClient.state.isConnected)
                    
                    Button(action: { showConfigSheet = true }) {
                        Label("Configuration", systemImage: "gearshape")
                    }
                    .disabled(!proxyClient.state.isConnected)
                    
                    Divider()
                    
                    Button(action: { proxyClient.disconnect() }) {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .disabled(!proxyClient.state.isConnected)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                
                ConnectionStatusView(showConnectSheet: $showConnectSheet)
            }
        }
        .sheet(isPresented: $showConnectSheet) {
            ConnectSheet()
        }
        .sheet(isPresented: $showAddTargetSheet) {
            AddTargetSheet()
        }
        .sheet(isPresented: $showServerStatusSheet) {
            ServerStatusView()
        }
        .sheet(isPresented: $showSessionInfoSheet) {
            SessionInfoView()
        }
        .sheet(isPresented: $showConfigSheet) {
            ConfigView()
        }
        .sheet(item: $selectedTargetForDetail) { targetID in
            TargetDetailView(targetID: targetID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showConnectSheet)) { _ in
            showConnectSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddTargetSheet)) { _ in
            showAddTargetSheet = true
        }
        .onAppear {
            setupSampleHandler()
        }
    }
    
    private func setupSampleHandler() {
        proxyClient.onSample = { sample in
            Task { @MainActor in
                timeSeriesStore.addSample(sample)
            }
        }
    }
}

// Conform String to Identifiable for sheet binding
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var proxyClient: ProxyClient
    @EnvironmentObject var timeSeriesStore: TimeSeriesStore
    @Binding var showAddTargetSheet: Bool
    @Binding var selectedTargetForDetail: String?
    
    var body: some View {
        List(selection: $timeSeriesStore.selectedSeriesIDs) {
            Section("Targets") {
                ForEach(Array(timeSeriesStore.series.values)) { series in
                    TargetRow(series: series)
                        .tag(series.id)
                        .contextMenu {
                            Button("Show Details") {
                                selectedTargetForDetail = series.targetID
                            }
                            
                            Divider()
                            
                            Button("Unsubscribe") {
                                Task {
                                    try? await proxyClient.unsubscribe(targetIDs: [series.targetID])
                                    timeSeriesStore.selectedSeriesIDs.remove(series.targetID)
                                }
                            }
                            
                            Button("Remove", role: .destructive) {
                                Task {
                                    try? await proxyClient.unmonitor(targetID: series.targetID)
                                    timeSeriesStore.remove(targetID: series.targetID)
                                }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button(action: { showAddTargetSheet = true }) {
                    Image(systemName: "plus")
                }
                .disabled(!proxyClient.state.isConnected)
            }
        }
    }
}

struct TargetRow: View {
    @ObservedObject var series: TimeSeries
    @State private var showConfigSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(series.displayName)
                    .font(.headline)
                
                Spacer()
                
                MetricTypeBadge(config: series.metricConfig)
            }
            
            HStack {
                if let displayValue = series.currentDisplayValue {
                    Text(displayValue)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(valueColor)
                } else {
                    Text("No data")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                // Mini sparkline
                SparklineView(series: series, width: 50, height: 16)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Configure Metric...") {
                showConfigSheet = true
            }
        }
        .sheet(isPresented: $showConfigSheet) {
            NavigationStack {
                MetricConfigView(config: Binding(
                    get: { series.metricConfig },
                    set: { series.metricConfig = $0; series.recalculateDisplayValues() }
                ))
            }
            .frame(minWidth: 500, minHeight: 600)
        }
    }
    
    private var valueColor: Color {
        guard let rate = series.currentRate else { return .secondary }
        return series.metricConfig.formatter.color(for: rate)
    }
}

// MARK: - Connection Status

struct ConnectionStatusView: View {
    @EnvironmentObject var proxyClient: ProxyClient
    @Binding var showConnectSheet: Bool
    
    var body: some View {
        Button(action: { showConnectSheet = true }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(proxyClient.state.statusText)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var statusColor: Color {
        switch proxyClient.state {
        case .disconnected: return .gray
        case .connecting, .authenticating: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
}

// MARK: - Graph Container

struct GraphContainerView: View {
    @EnvironmentObject var timeSeriesStore: TimeSeriesStore
    @State private var timeWindow: TimeInterval = 300 // 5 minutes
    
    var body: some View {
        VStack {
            // Time window picker
            Picker("Time Window", selection: $timeWindow) {
                Text("1 min").tag(TimeInterval(60))
                Text("5 min").tag(TimeInterval(300))
                Text("15 min").tag(TimeInterval(900))
                Text("1 hour").tag(TimeInterval(3600))
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Graph
            LiveGraphView(
                series: timeSeriesStore.selectedSeries,
                timeWindow: timeWindow
            )
            .padding()
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(ProxyClient())
        .environmentObject(TimeSeriesStore())
}
