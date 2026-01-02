import SwiftUI
import SwiftProtobuf

struct AddTargetSheet: View {
    @EnvironmentObject var proxyClient: ProxyClient
    @EnvironmentObject var timeSeriesStore: TimeSeriesStore
    @Environment(\.dismiss) var dismiss
    
    // Common
    @State private var host = ""
    @State private var port = "161"
    @State private var oid = ""
    @State private var displayName = ""
    @State private var intervalMs = "1000"
    
    // SNMP Version
    @State private var useV3 = false
    
    // SNMPv2c
    @State private var community = "public"
    
    // SNMPv3
    @State private var securityName = ""
    @State private var securityLevel: SecurityLevel = .authPriv
    @State private var authProtocol: AuthProtocol = .sha256
    @State private var authPassword = ""
    @State private var privProtocol: PrivProtocol = .aes
    @State private var privPassword = ""
    @State private var contextName = ""
    
    // State
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var autoSubscribe = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Target")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Form
            ScrollView {
                Form {
                    // Target
                    Section("Target") {
                        TextField("Host", text: $host, prompt: Text("192.168.1.1"))
                        TextField("Port", text: $port)
                        TextField("OID", text: $oid, prompt: Text("1.3.6.1.2.1.31.1.1.1.6.1"))
                        TextField("Display Name", text: $displayName, prompt: Text("Optional"))
                        TextField("Interval (ms)", text: $intervalMs)
                    }
                    
                    // SNMP Version
                    Section("SNMP Version") {
                        Picker("Version", selection: $useV3) {
                            Text("SNMPv2c").tag(false)
                            Text("SNMPv3").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // SNMPv2c Settings
                    if !useV3 {
                        Section("SNMPv2c") {
                            TextField("Community", text: $community)
                        }
                    }
                    
                    // SNMPv3 Settings
                    if useV3 {
                        Section("SNMPv3 Security") {
                            TextField("Security Name (User)", text: $securityName)
                            
                            Picker("Security Level", selection: $securityLevel) {
                                Text("noAuthNoPriv").tag(SecurityLevel.noAuthNoPriv)
                                Text("authNoPriv").tag(SecurityLevel.authNoPriv)
                                Text("authPriv").tag(SecurityLevel.authPriv)
                            }
                        }
                        
                        if securityLevel != .noAuthNoPriv {
                            Section("Authentication") {
                                Picker("Protocol", selection: $authProtocol) {
                                    Text("MD5").tag(AuthProtocol.md5)
                                    Text("SHA").tag(AuthProtocol.sha)
                                    Text("SHA-224").tag(AuthProtocol.sha224)
                                    Text("SHA-256").tag(AuthProtocol.sha256)
                                    Text("SHA-384").tag(AuthProtocol.sha384)
                                    Text("SHA-512").tag(AuthProtocol.sha512)
                                }
                                
                                SecureField("Password", text: $authPassword)
                            }
                        }
                        
                        if securityLevel == .authPriv {
                            Section("Privacy") {
                                Picker("Protocol", selection: $privProtocol) {
                                    Text("DES").tag(PrivProtocol.des)
                                    Text("AES").tag(PrivProtocol.aes)
                                    Text("AES-192").tag(PrivProtocol.aes192)
                                    Text("AES-256").tag(PrivProtocol.aes256)
                                }
                                
                                SecureField("Password", text: $privPassword)
                            }
                        }
                        
                        Section("Optional") {
                            TextField("Context Name", text: $contextName)
                        }
                    }
                    
                    // Options
                    Section("Options") {
                        Toggle("Subscribe to live updates", isOn: $autoSubscribe)
                    }
                    
                    // Error
                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Add") {
                    addTarget()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAdding || !isValid)
            }
            .padding()
        }
        .frame(width: 450, height: 600)
    }
    
    private var isValid: Bool {
        !host.isEmpty && !oid.isEmpty && (!useV3 || !securityName.isEmpty)
    }
    
    private func addTarget() {
        guard let portNum = UInt32(port), let interval = UInt32(intervalMs) else {
            errorMessage = "Invalid port or interval"
            return
        }
        
        isAdding = true
        errorMessage = nil
        
        let snmpConfig = buildSNMPConfig()
        let name = displayName.isEmpty ? "\(host)/\(oid)" : displayName
        
        Task {
            do {
                let (targetID, created) = try await proxyClient.monitor(
                    host: host,
                    port: portNum,
                    oid: oid,
                    intervalMs: interval,
                    snmpConfig: snmpConfig
                )
                
                // Create time series
                let _ = timeSeriesStore.getOrCreate(targetID: targetID, displayName: name)
                
                // Auto-subscribe
                if autoSubscribe {
                    let _ = try await proxyClient.subscribe(targetIDs: [targetID])
                    timeSeriesStore.selectedSeriesIDs.insert(targetID)
                }
                
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isAdding = false
        }
    }
    
    private func buildSNMPConfig() -> Snmpproxy_V1_SNMPConfig {
        var config = Snmpproxy_V1_SNMPConfig()
        
        if useV3 {
            var v3 = Snmpproxy_V1_SNMPv3()
            v3.securityName = securityName
            v3.securityLevel = securityLevel.proto
            v3.authProtocol = authProtocol.proto
            v3.authPassword = authPassword
            v3.privProtocol = privProtocol.proto
            v3.privPassword = privPassword
            v3.contextName = contextName
            config.v3 = v3
        } else {
            var v2c =  Snmpproxy_V1_SNMPv2c()
            v2c.community = community
            config.v2C = v2c
        }
        
        return config
    }
}

// MARK: - Enums with Proto Mapping

enum SecurityLevel: String, CaseIterable {
    case noAuthNoPriv, authNoPriv, authPriv
    
    var proto: Snmpproxy_V1_SecurityLevel {
        switch self {
        case .noAuthNoPriv: return .noAuthNoPriv
        case .authNoPriv: return .authNoPriv
        case .authPriv: return .authPriv
        }
    }
}

enum AuthProtocol: String, CaseIterable {
    case md5, sha, sha224, sha256, sha384, sha512
    
    var proto: Snmpproxy_V1_AuthProtocol {
        switch self {
        case .md5: return .md5
        case .sha: return .sha
        case .sha224: return .sha224
        case .sha256: return .sha256
        case .sha384: return .sha384
        case .sha512: return .sha512
        }
    }
}

enum PrivProtocol: String, CaseIterable {
    case des, aes, aes192, aes256
    
    var proto: Snmpproxy_V1_PrivProtocol {
        switch self {
        case .des: return .des
        case .aes: return .aes
        case .aes192: return .aes192
        case .aes256: return .aes256
        }
    }
}

#Preview {
    AddTargetSheet()
        .environmentObject(ProxyClient())
        .environmentObject(TimeSeriesStore())
}
