import SwiftUI

struct ConfigView: View {
    @EnvironmentObject var proxyClient: ProxyClient
    @Environment(\.dismiss) var dismiss
    
    @State private var config: Snmpproxy_V1_RuntimeConfig?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Editable values
    @State private var timeoutMs: String = ""
    @State private var retries: String = ""
    @State private var bufferSize: String = ""
    @State private var minInterval: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Runtime Config")
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
            
            if isLoading && config == nil {
                ProgressView()
                    .padding()
            } else if config != nil {
                Form {
                    Section("Changeable") {
                        HStack {
                            Text("Default Timeout (ms)")
                            Spacer()
                            TextField("", text: $timeoutMs)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Button("Set") {
                                setConfig(timeoutMs: UInt32(timeoutMs) ?? 0)
                            }
                            .disabled(timeoutMs.isEmpty)
                        }
                        
                        HStack {
                            Text("Default Retries")
                            Spacer()
                            TextField("", text: $retries)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Button("Set") {
                                setConfig(retries: UInt32(retries) ?? 0)
                            }
                            .disabled(retries.isEmpty)
                        }
                        
                        HStack {
                            Text("Default Buffer Size")
                            Spacer()
                            TextField("", text: $bufferSize)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Button("Set") {
                                setConfig(bufferSize: UInt32(bufferSize) ?? 0)
                            }
                            .disabled(bufferSize.isEmpty)
                        }
                        
                        HStack {
                            Text("Min Interval (ms)")
                            Spacer()
                            TextField("", text: $minInterval)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Button("Set") {
                                setConfig(minIntervalMs: UInt32(minInterval) ?? 0)
                            }
                            .disabled(minInterval.isEmpty)
                        }
                    }
                    
                    Section("Read-only (set at startup)") {
                        LabeledContent("Poller Workers", value: "\(config?.pollerWorkers ?? 0)")
                        LabeledContent("Poller Queue Size", value: "\(config?.pollerQueueSize ?? 0)")
                        LabeledContent("Reconnect Window", value: "\(config?.reconnectWindowSec ?? 0) sec")
                    }
                }
                .formStyle(.grouped)
            }
            
            Spacer()
        }
        .frame(width: 450, height: 400)
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
                config = try await proxyClient.getConfig()
                updateFields()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    private func updateFields() {
        guard let config = config else { return }
        timeoutMs = "\(config.defaultTimeoutMs)"
        retries = "\(config.defaultRetries)"
        bufferSize = "\(config.defaultBufferSize)"
        minInterval = "\(config.minIntervalMs)"
    }
    
    private func setConfig(
        timeoutMs: UInt32 = 0,
        retries: UInt32 = 0,
        bufferSize: UInt32 = 0,
        minIntervalMs: UInt32 = 0
    ) {
        Task {
            do {
                let resp = try await proxyClient.setConfig(
                    defaultTimeoutMs: timeoutMs,
                    defaultRetries: retries,
                    defaultBufferSize: bufferSize,
                    minIntervalMs: minIntervalMs
                )
                if resp.ok {
                    config = resp.config
                    updateFields()
                } else {
                    errorMessage = resp.message
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ConfigView()
        .environmentObject(ProxyClient())
}
