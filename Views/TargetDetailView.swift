import SwiftUI

struct TargetDetailView: View {
    @EnvironmentObject var proxyClient: ProxyClient
    @Environment(\.dismiss) var dismiss
    
    let targetID: String
    
    @State private var target: Snmpproxy_V1_Target?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showEditSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Target Details")
                    .font(.headline)
                Spacer()
                
                Button(action: { showEditSheet = true }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .disabled(target == nil)
                
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
            
            if isLoading && target == nil {
                ProgressView()
                    .padding()
            } else if let target = target {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Basic Info
                        GroupBox("Target") {
                            LabeledContent("ID", value: target.id)
                            LabeledContent("Host", value: "\(target.host):\(target.port)")
                            LabeledContent("OID", value: target.oid)
                        }
                        
                        // Configuration
                        GroupBox("Configuration") {
                            LabeledContent("Interval", value: "\(target.intervalMs) ms")
                            LabeledContent("Buffer", value: "\(target.samplesBuffered) / \(target.bufferSize)")
                        }
                        
                        // Runtime State
                        GroupBox("State") {
                            HStack {
                                Text("Status")
                                Spacer()
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(stateColor(target.state))
                                        .frame(width: 8, height: 8)
                                    Text(target.state.isEmpty ? "unknown" : target.state)
                                }
                            }
                            LabeledContent("Subscribers", value: "\(target.subscribers)")
                            if target.lastPollMs > 0 {
                                LabeledContent("Last Poll", value: formatDate(ms: target.lastPollMs))
                            }
                            if !target.lastError.isEmpty {
                                LabeledContent("Last Error", value: target.lastError)
                                    .foregroundStyle(.red)
                            }
                        }
                        
                        // Statistics
                        if target.pollsTotal > 0 {
                            GroupBox("Statistics") {
                                LabeledContent("Total Polls", value: "\(target.pollsTotal)")
                                LabeledContent("Successful", value: "\(target.pollsSuccess)")
                                LabeledContent("Failed", value: "\(target.pollsFailed)")
                                
                                let rate = Double(target.pollsSuccess) / Double(target.pollsTotal) * 100
                                LabeledContent("Success Rate", value: String(format: "%.1f%%", rate))
                                
                                Divider()
                                
                                LabeledContent("Avg Poll Time", value: "\(target.avgPollMs) ms")
                                LabeledContent("Min Poll Time", value: "\(target.minPollMs) ms")
                                LabeledContent("Max Poll Time", value: "\(target.maxPollMs) ms")
                            }
                        }
                        
                        // Created
                        if target.createdAtMs > 0 {
                            GroupBox("History") {
                                LabeledContent("Created", value: formatDate(ms: target.createdAtMs))
                            }
                        }
                    }
                    .padding()
                }
            }
            
            Spacer()
        }
        .frame(width: 400, height: 550)
        .onAppear {
            refresh()
        }
        .sheet(isPresented: $showEditSheet) {
            if let target = target {
                TargetEditSheet(target: target) {
                    refresh()
                }
            }
        }
    }
    
    private func refresh() {
        guard proxyClient.state.isConnected else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                target = try await proxyClient.getTarget(targetID: targetID)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    private func stateColor(_ state: String) -> Color {
        switch state {
        case "polling": return .green
        case "unreachable": return .red
        case "error": return .orange
        default: return .gray
        }
    }
    
    private func formatDate(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Edit Sheet

struct TargetEditSheet: View {
    @EnvironmentObject var proxyClient: ProxyClient
    @Environment(\.dismiss) var dismiss
    
    let target: Snmpproxy_V1_Target
    let onUpdate: () -> Void
    
    @State private var intervalMs: String = ""
    @State private var timeoutMs: String = ""
    @State private var retries: String = ""
    @State private var bufferSize: String = ""
    
    @State private var isUpdating = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Target")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            Form {
                Section("Target: \(target.id)") {
                    Text("\(target.host):\(target.port) - \(target.oid)")
                        .foregroundStyle(.secondary)
                }
                
                Section("Settings (leave empty to keep current)") {
                    TextField("Interval (ms)", text: $intervalMs)
                        .textFieldStyle(.roundedBorder)
                    Text("Current: \(target.intervalMs) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Buffer Size", text: $bufferSize)
                        .textFieldStyle(.roundedBorder)
                    Text("Current: \(target.bufferSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("SNMP Timeout (ms)", text: $timeoutMs)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("SNMP Retries", text: $retries)
                        .textFieldStyle(.roundedBorder)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                
                if let success = successMessage {
                    Section {
                        Text(success)
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Update") {
                    update()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdating || !hasChanges)
            }
            .padding()
        }
        .frame(width: 400, height: 400)
    }
    
    private var hasChanges: Bool {
        !intervalMs.isEmpty || !bufferSize.isEmpty || !timeoutMs.isEmpty || !retries.isEmpty
    }
    
    private func update() {
        isUpdating = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            do {
                let resp = try await proxyClient.updateTarget(
                    targetID: target.id,
                    intervalMs: UInt32(intervalMs) ?? 0,
                    timeoutMs: UInt32(timeoutMs) ?? 0,
                    retries: UInt32(retries) ?? 0,
                    bufferSize: UInt32(bufferSize) ?? 0
                )
                
                if resp.ok {
                    successMessage = resp.message
                    onUpdate()
                    
                    // Clear fields
                    intervalMs = ""
                    bufferSize = ""
                    timeoutMs = ""
                    retries = ""
                } else {
                    errorMessage = resp.message
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isUpdating = false
        }
    }
}

#Preview {
    TargetDetailView(targetID: "abc123")
        .environmentObject(ProxyClient())
}
