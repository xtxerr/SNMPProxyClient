import SwiftUI
import SwiftProtobuf

// MARK: - Add Target Sheet

struct AddTargetSheet: View {
    @EnvironmentObject var proxyClient: ProxyClient
    @EnvironmentObject var timeSeriesStore: TimeSeriesStore
    @Environment(\.dismiss) private var dismiss
    
    // SNMP Target
    @State private var host: String = ""
    @State private var port: String = "161"
    @State private var oid: String = ""
    @State private var displayName: String = ""
    
    // SNMP Settings
    @State private var snmpVersion: SNMPVersion = .v2c
    @State private var community: String = "public"
    
    // SNMPv3
    @State private var securityName: String = ""
    @State private var securityLevel: SecurityLevel = .authPriv
    @State private var authProtocol: AuthProtocol = .sha256
    @State private var authPassword: String = ""
    @State private var privProtocol: PrivProtocol = .aes
    @State private var privPassword: String = ""
    @State private var contextName: String = ""
    
    // Polling
    @State private var intervalMs: String = "1000"
    @State private var bufferSize: String = "3600"
    
    // Metric Configuration
    @State private var metricConfig: MetricConfig = .networkOctetsIn
    @State private var autoDetectConfig: Bool = true
    @State private var showMetricConfig: Bool = false
    
    // State
    @State private var isAdding = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                // ─────────────────────────────────────────────────────────────
                // Target
                // ─────────────────────────────────────────────────────────────
                Section("Target") {
                    HStack {
                        TextField("Host", text: $host)
                            .textFieldStyle(.roundedBorder)
                        Text(":")
                        TextField("Port", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                    
                    TextField("OID", text: $oid)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: oid) { _, newOID in
                            if autoDetectConfig, let detected = MetricConfig.preset(for: newOID) {
                                metricConfig = detected
                            }
                        }
                    
                    TextField("Display Name (optional)", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }
                
                // ─────────────────────────────────────────────────────────────
                // SNMP Version
                // ─────────────────────────────────────────────────────────────
                Section("SNMP") {
                    Picker("Version", selection: $snmpVersion) {
                        Text("SNMPv2c").tag(SNMPVersion.v2c)
                        Text("SNMPv3").tag(SNMPVersion.v3)
                    }
                    .pickerStyle(.segmented)
                    
                    if snmpVersion == .v2c {
                        TextField("Community", text: $community)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        // SNMPv3 settings
                        TextField("Security Name", text: $securityName)
                            .textFieldStyle(.roundedBorder)
                        
                        Picker("Security Level", selection: $securityLevel) {
                            ForEach(SecurityLevel.allCases) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        
                        if securityLevel != .noAuthNoPriv {
                            Picker("Auth Protocol", selection: $authProtocol) {
                                ForEach(AuthProtocol.allCases) { proto in
                                    Text(proto.rawValue).tag(proto)
                                }
                            }
                            
                            SecureField("Auth Password", text: $authPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        if securityLevel == .authPriv {
                            Picker("Privacy Protocol", selection: $privProtocol) {
                                ForEach(PrivProtocol.allCases) { proto in
                                    Text(proto.rawValue).tag(proto)
                                }
                            }
                            
                            SecureField("Privacy Password", text: $privPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        TextField("Context Name (optional)", text: $contextName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                // ─────────────────────────────────────────────────────────────
                // Polling
                // ─────────────────────────────────────────────────────────────
                Section("Polling") {
                    HStack {
                        Text("Interval")
                        Spacer()
                        TextField("ms", text: $intervalMs)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Text("ms")
                    }
                    
                    HStack {
                        Text("Buffer Size")
                        Spacer()
                        TextField("samples", text: $bufferSize)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Text("samples")
                    }
                }
                
                // ─────────────────────────────────────────────────────────────
                // Metric Configuration
                // ─────────────────────────────────────────────────────────────
                Section {
                    Toggle("Auto-detect from OID", isOn: $autoDetectConfig)
                    
                    // Quick preset picker
                    Picker("Metric Type", selection: Binding(
                        get: { presetIndex(for: metricConfig) },
                        set: { index in
                            if let idx = index, idx < MetricConfig.allTemplates.count {
                                metricConfig = MetricConfig.allTemplates[idx].config
                            }
                        }
                    )) {
                        Text("Custom").tag(nil as Int?)
                        ForEach(Array(MetricConfig.allTemplates.enumerated()), id: \.offset) { index, template in
                            Text(template.name).tag(index as Int?)
                        }
                    }
                    
                    HStack {
                        // Type badge
                        MetricTypeBadge(config: metricConfig)
                        
                        Spacer()
                        
                        // Preview
                        Text("Preview: \(metricConfig.formatter.format(1_000_000))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // Configure button
                        Button("Configure...") {
                            showMetricConfig = true
                        }
                        .buttonStyle(.link)
                    }
                } header: {
                    Text("Metric Display")
                } footer: {
                    Text("Controls how the value is interpreted and displayed")
                }
                
                // ─────────────────────────────────────────────────────────────
                // Error
                // ─────────────────────────────────────────────────────────────
                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Target")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addTarget()
                    }
                    .disabled(!isValid || isAdding)
                }
            }
            .sheet(isPresented: $showMetricConfig) {
                NavigationStack {
                    MetricConfigView(config: $metricConfig)
                }
                .frame(minWidth: 500, minHeight: 600)
            }
        }
        .frame(minWidth: 450, minHeight: 500)
    }
    
    // MARK: - Validation
    
    private var isValid: Bool {
        !host.isEmpty && !oid.isEmpty && 
        (snmpVersion == .v2c || !securityName.isEmpty)
    }
    
    private func presetIndex(for config: MetricConfig) -> Int? {
        for (index, template) in MetricConfig.allTemplates.enumerated() {
            if template.config.metricType == config.metricType &&
               template.config.unit == config.unit &&
               template.config.multiplier == config.multiplier {
                return index
            }
        }
        return nil
    }
    
    // MARK: - Build SNMP Config
    
    private func buildSNMPConfig() -> Snmpproxy_V1_SNMPConfig {
        var config = Snmpproxy_V1_SNMPConfig()
        
        if snmpVersion == .v2c {
            config.v2C = Snmpproxy_V1_SNMPv2c.with {
                $0.community = community
            }
        } else {
            config.v3 = Snmpproxy_V1_SNMPv3.with {
                $0.securityName = securityName
                $0.securityLevel = securityLevel.protoValue
                
                if securityLevel != .noAuthNoPriv {
                    $0.authProtocol = authProtocol.protoValue
                    $0.authPassword = authPassword
                }
                
                if securityLevel == .authPriv {
                    $0.privProtocol = privProtocol.protoValue
                    $0.privPassword = privPassword
                }
                
                if !contextName.isEmpty {
                    $0.contextName = contextName
                }
            }
        }
        
        return config
    }
    
    // MARK: - Add Target
    
    private func addTarget() {
        isAdding = true
        errorMessage = nil
        
        Task {
            do {
                let portNum = UInt32(port) ?? 161
                let interval = UInt32(intervalMs) ?? 1000
                let buffer = UInt32(bufferSize) ?? 3600
                
                let snmpConfig = buildSNMPConfig()
                
                let (targetID, _) = try await proxyClient.monitor(
                    host: host,
                    port: portNum,
                    oid: oid,
                    intervalMs: interval,
                    bufferSize: buffer,
                    snmpConfig: snmpConfig
                )
                
                // Configure the time series with our metric config
                let name = displayName.isEmpty ? "\(host):\(oid)" : displayName
                timeSeriesStore.configureSeries(
                    targetID: targetID,
                    displayName: name,
                    oid: oid,
                    config: metricConfig
                )
                
                // Auto-subscribe
                _ = try? await proxyClient.subscribe(targetIDs: [targetID])
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAdding = false
                }
            }
        }
    }
}

// MARK: - Supporting Types

enum SNMPVersion: String, CaseIterable {
    case v2c, v3
}

enum SecurityLevel: String, CaseIterable, Identifiable {
    case noAuthNoPriv, authNoPriv, authPriv
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .noAuthNoPriv: return "No Auth, No Priv"
        case .authNoPriv: return "Auth, No Priv"
        case .authPriv: return "Auth + Priv"
        }
    }
    
    var protoValue: Snmpproxy_V1_SecurityLevel {
        switch self {
        case .noAuthNoPriv: return .noAuthNoPriv
        case .authNoPriv: return .authNoPriv
        case .authPriv: return .authPriv
        }
    }
}

enum AuthProtocol: String, CaseIterable, Identifiable {
    case md5 = "MD5"
    case sha = "SHA"
    case sha224 = "SHA224"
    case sha256 = "SHA256"
    case sha384 = "SHA384"
    case sha512 = "SHA512"
    
    var id: String { rawValue }
    
    var protoValue: Snmpproxy_V1_AuthProtocol {
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

enum PrivProtocol: String, CaseIterable, Identifiable {
    case des = "DES"
    case aes = "AES"
    case aes192 = "AES192"
    case aes256 = "AES256"
    
    var id: String { rawValue }
    
    var protoValue: Snmpproxy_V1_PrivProtocol {
        switch self {
        case .des: return .des
        case .aes: return .aes
        case .aes192: return .aes192
        case .aes256: return .aes256
        }
    }
}

// MARK: - Preview

#Preview {
    AddTargetSheet()
        .environmentObject(ProxyClient())
        .environmentObject(TimeSeriesStore())
}
