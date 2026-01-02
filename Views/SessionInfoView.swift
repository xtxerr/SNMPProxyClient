import SwiftUI

struct SessionInfoView: View {
    @EnvironmentObject var proxyClient: ProxyClient
    @Environment(\.dismiss) var dismiss
    
    @State private var session: Snmpproxy_V1_GetSessionInfoResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Session Info")
                    .font(.headline)
                Spacer()
                
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
            
            if isLoading && session == nil {
                ProgressView()
                    .padding()
            } else if let session = session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Session Details
                        GroupBox("Session") {
                            LabeledContent("Session ID", value: session.sessionID)
                            LabeledContent("Token ID", value: session.tokenID)
                            LabeledContent("Created", value: formatDate(ms: session.createdAtMs))
                            LabeledContent("Connected", value: formatDate(ms: session.connectedAtMs))
                        }
                        
                        // Owned Targets
                        GroupBox("Owned Targets (\(session.ownedTargets.count))") {
                            if session.ownedTargets.isEmpty {
                                Text("No owned targets")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(session.ownedTargets, id: \.self) { targetID in
                                    HStack {
                                        Image(systemName: "target")
                                            .foregroundStyle(.secondary)
                                        Text(targetID)
                                            .font(.system(.body, design: .monospaced))
                                        Spacer()
                                    }
                                }
                            }
                        }
                        
                        // Subscribed Targets
                        GroupBox("Subscribed (\(session.subscribedTargets.count))") {
                            if session.subscribedTargets.isEmpty {
                                Text("No subscriptions")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(session.subscribedTargets, id: \.self) { targetID in
                                    HStack {
                                        Image(systemName: "bell.fill")
                                            .foregroundStyle(.blue)
                                        Text(targetID)
                                            .font(.system(.body, design: .monospaced))
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            
            Spacer()
        }
        .frame(width: 400, height: 450)
        .onAppear {
            refresh()
        }
    }
    
    private func refresh() {
        guard proxyClient.state.isConnected else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                session = try await proxyClient.getSessionInfo()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
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
    SessionInfoView()
        .environmentObject(ProxyClient())
}
