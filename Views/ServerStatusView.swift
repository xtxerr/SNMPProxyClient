import SwiftUI

struct ServerStatusView: View {
    @EnvironmentObject var proxyClient: ProxyClient
    @Environment(\.dismiss) var dismiss
    
    @State private var status: Snmpproxy_V1_GetServerStatusResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var autoRefresh = true
    @State private var refreshTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Server Status")
                    .font(.headline)
                Spacer()
                
                Toggle("Auto-refresh", isOn: $autoRefresh)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .padding()
            }
            
            if isLoading && status == nil {
                ProgressView()
                    .padding()
            } else if let status = status {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // General
                        GroupBox("General") {
                            LabeledContent("Version", value: status.version.isEmpty ? "unknown" : status.version)
                            LabeledContent("Uptime", value: formatDuration(ms: status.uptimeMs))
                            LabeledContent("Started", value: formatDate(ms: status.startedAtMs))
                        }
                        
                        // Sessions
                        GroupBox("Sessions") {
                            LabeledContent("Active", value: "\(status.sessionsActive)")
                            LabeledContent("Lost", value: "\(status.sessionsLost)")
                        }
                        
                        // Targets
                        GroupBox("Targets") {
                            LabeledContent("Total", value: "\(status.targetsTotal)")
                            LabeledContent("Polling", value: "\(status.targetsPolling)")
                            LabeledContent("Unreachable", value: "\(status.targetsUnreachable)")
                        }
                        
                        // Poller
                        GroupBox("Poller") {
                            LabeledContent("Workers", value: "\(status.pollerWorkers)")
                            LabeledContent("Queue", value: "\(status.pollerQueueUsed) / \(status.pollerQueueCapacity)")
                            LabeledContent("Heap Size", value: "\(status.pollerHeapSize)")
                        }
                        
                        // Statistics
                        GroupBox("Statistics") {
                            LabeledContent("Total Polls", value: "\(status.pollsTotal)")
                            LabeledContent("Successful", value: "\(status.pollsSuccess)")
                            LabeledContent("Failed", value: "\(status.pollsFailed)")
                            if status.pollsTotal > 0 {
                                let rate = Double(status.pollsSuccess) / Double(status.pollsTotal) * 100
                                LabeledContent("Success Rate", value: String(format: "%.1f%%", rate))
                            }
                        }
                    }
                    .padding()
                }
            }
            
            Spacer()
        }
        .frame(width: 400, height: 500)
        .onAppear {
            refresh()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
        .onChange(of: autoRefresh) { _, newValue in
            if newValue {
                startAutoRefresh()
            } else {
                refreshTask?.cancel()
            }
        }
    }
    
    private func refresh() {
        guard proxyClient.state.isConnected else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                status = try await proxyClient.getServerStatus()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    private func startAutoRefresh() {
        refreshTask?.cancel()
        
        guard autoRefresh else { return }
        
        refreshTask = Task {
            while !Task.isCancelled && autoRefresh {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                if proxyClient.state.isConnected {
                    refresh()
                }
            }
        }
    }
    
    private func formatDuration(ms: Int64) -> String {
        let totalSeconds = ms / 1000
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatDate(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    ServerStatusView()
        .environmentObject(ProxyClient())
}
