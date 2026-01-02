import SwiftUI

struct ConnectSheet: View {
    @EnvironmentObject var proxyClient: ProxyClient
    @Environment(\.dismiss) var dismiss
    
    @AppStorage("lastHost") private var host = "localhost"
    @AppStorage("lastPort") private var port = "9161"
    @AppStorage("useTLS") private var useTLS = false
    
    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var connectTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Connect to Server")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    cancelAndDismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section {
                    TextField("Host", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isConnecting)
                    
                    TextField("Port", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isConnecting)
                    
                    SecureField("Token", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isConnecting)
                    
                    Toggle("Use TLS", isOn: $useTLS)
                        .disabled(isConnecting)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                
                // Connection status during connect
                if isConnecting {
                    Section {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(proxyClient.state.statusText)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
            
            Divider()
            
            // Footer
            HStack {
                if proxyClient.state.isConnected {
                    Button("Disconnect") {
                        proxyClient.disconnect()
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if isConnecting {
                    Button("Cancel") {
                        cancelConnect()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Connect") {
                        connect()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(host.isEmpty || token.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 400)
        .onAppear {
            // Try to load token from keychain or environment
            if token.isEmpty {
                token = ProcessInfo.processInfo.environment["SNMPPROXY_TOKEN"] ?? ""
            }
        }
        .onDisappear {
            // Cancel if sheet is dismissed while connecting
            if isConnecting {
                cancelConnect()
            }
        }
    }
    
    private func connect() {
        guard let portNum = UInt16(port) else {
            errorMessage = "Invalid port number"
            return
        }
        
        isConnecting = true
        errorMessage = nil
        
        connectTask = Task {
            do {
                try await proxyClient.connect(
                    host: host,
                    port: portNum,
                    token: token,
                    useTLS: useTLS
                )
                dismiss()
            } catch is CancellationError {
                // User cancelled - do nothing
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
    
    private func cancelConnect() {
        connectTask?.cancel()
        proxyClient.cancelConnect()
        isConnecting = false
        errorMessage = nil
    }
    
    private func cancelAndDismiss() {
        if isConnecting {
            cancelConnect()
        }
        dismiss()
    }
}

#Preview {
    ConnectSheet()
        .environmentObject(ProxyClient())
}
