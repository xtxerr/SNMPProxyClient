import Foundation
import Network
import Combine
import SwiftProtobuf

/// Thread-safe flag for continuation handling
final class AtomicBool: @unchecked Sendable {
    private var _value: Bool
    private let lock = NSLock()
    
    init(_ value: Bool) {
        _value = value
    }
    
    /// Returns true if was already set, false if we set it
    func testAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _value { return true }
        _value = true
        return false
    }
}

/// Pending request with timeout support
private struct PendingRequest {
    let continuation: CheckedContinuation<Snmpproxy_V1_Envelope, Error>
    let createdAt: Date
    let timeoutTask: Task<Void, Never>
}

/// Client for connecting to snmpproxyd server
@MainActor
class ProxyClient: ObservableObject {
    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var sessionID: String?
    @Published private(set) var targets: [String: ProxyTarget] = [:]
    
    private var connection: NWConnection?
    private var parser = WireProtocol.Parser()
    private var pendingRequests: [UInt64: PendingRequest] = [:]
    private var requestID: UInt64 = 0
    
    // Configuration
    private let requestTimeout: TimeInterval
    private let connectionTimeout: TimeInterval
    
    // For cancellation
    private var connectTask: Task<Void, Error>?
    private var cleanupTask: Task<Void, Never>?
    
    // Callbacks
    var onSample: ((Snmpproxy_V1_Sample) -> Void)?
    
    // MARK: - Initialization
    
    init(requestTimeout: TimeInterval = 30.0, connectionTimeout: TimeInterval = 10.0) {
        self.requestTimeout = requestTimeout
        self.connectionTimeout = connectionTimeout
    }
    
    // MARK: - Connection
    
    func connect(host: String, port: UInt16, token: String, useTLS: Bool = false) async throws {
        // Cancel any existing connection attempt
        connectTask?.cancel()
        disconnect()
        
        state = .connecting
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        
        let parameters: NWParameters
        if useTLS {
            parameters = NWParameters(tls: TLSOptions.insecure)
        } else {
            parameters = NWParameters.tcp
        }
        
        // Create connection
        let conn = NWConnection(to: endpoint, using: parameters)
        connection = conn
        
        // Use a separate DispatchQueue to avoid deadlock with @MainActor
        let connectionQueue = DispatchQueue(label: "snmpproxy.connection")
        
        // Wait for connection with proper cancellation and timeout support
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Connection task
                group.addTask {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        let resumed = AtomicBool(false)
                        
                        conn.stateUpdateHandler = { [weak self] newState in
                            switch newState {
                            case .ready:
                                guard !resumed.testAndSet() else { return }
                                continuation.resume()
                                
                            case .failed(let error):
                                guard !resumed.testAndSet() else { return }
                                Task { @MainActor in
                                    self?.state = .error(error.localizedDescription)
                                }
                                continuation.resume(throwing: error)
                                
                            case .cancelled:
                                guard !resumed.testAndSet() else { return }
                                continuation.resume(throwing: CancellationError())
                                
                            case .waiting(let error):
                                guard !resumed.testAndSet() else { return }
                                Task { @MainActor in
                                    self?.state = .error("Network unavailable: \(error.localizedDescription)")
                                }
                                continuation.resume(throwing: error)
                                
                            case .preparing, .setup:
                                break
                                
                            @unknown default:
                                break
                            }
                        }
                        
                        conn.start(queue: connectionQueue)
                    }
                }
                
                // Timeout task
                group.addTask { [connectionTimeout] in
                    try await Task.sleep(nanoseconds: UInt64(connectionTimeout * 1_000_000_000))
                    throw ProxyError.timeout
                }
                
                // Wait for first to complete
                do {
                    try await group.next()
                    group.cancelAll()
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
        } onCancel: {
            conn.cancel()
        }
        
        try Task.checkCancellation()
        
        setupStateHandler()
        startReceiving()
        startCleanupTask()
        
        // Authenticate
        state = .authenticating
        try await authenticate(token: token)
        
        state = .connected
    }
    
    func disconnect() {
        connectTask?.cancel()
        cleanupTask?.cancel()
        connection?.cancel()
        connection = nil
        state = .disconnected
        sessionID = nil
        targets.removeAll()
        parser.reset()
        
        for (_, pending) in pendingRequests {
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: ProxyError.notConnected)
        }
        pendingRequests.removeAll()
    }
    
    func cancelConnect() {
        connectTask?.cancel()
        connection?.cancel()
        connection = nil
        state = .disconnected
    }
    
    private func setupStateHandler() {
        connection?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                switch newState {
                case .failed(let error):
                    self?.handleDisconnect(error: error.localizedDescription)
                case .cancelled:
                    self?.handleDisconnect(error: nil)
                default:
                    break
                }
            }
        }
    }
    
    private func handleDisconnect(error: String?) {
        cleanupTask?.cancel()
        
        if let error = error {
            state = .error(error)
        } else {
            state = .disconnected
        }
        sessionID = nil
        
        for (_, pending) in pendingRequests {
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: ProxyError.notConnected)
        }
        pendingRequests.removeAll()
    }
    
    // MARK: - Request Cleanup
    
    private func startCleanupTask() {
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.cleanupStaleRequests()
            }
        }
    }
    
    private func cleanupStaleRequests() {
        let now = Date()
        let staleThreshold = requestTimeout * 2
        
        for (id, pending) in pendingRequests {
            if now.timeIntervalSince(pending.createdAt) > staleThreshold {
                pending.timeoutTask.cancel()
                pending.continuation.resume(throwing: ProxyError.timeout)
                pendingRequests.removeValue(forKey: id)
            }
        }
    }
    
    // MARK: - Receiving
    
    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let data = data {
                    self.handleReceivedData(data)
                }
                
                if let error = error {
                    self.handleDisconnect(error: error.localizedDescription)
                    return
                }
                
                if isComplete {
                    self.handleDisconnect(error: nil)
                    return
                }
                
                self.startReceiving()
            }
        }
    }
    
    private func handleReceivedData(_ data: Data) {
        parser.append(data)
        
        for messageData in parser.extractMessages() {
            do {
                let envelope = try Snmpproxy_V1_Envelope(serializedBytes: messageData)
                handleEnvelope(envelope)
            } catch {
                print("Failed to parse envelope: \(error)")
            }
        }
    }
    
    private func handleEnvelope(_ envelope: Snmpproxy_V1_Envelope) {
        // Check if it's a response to a pending request
        if envelope.id != 0, let pending = pendingRequests.removeValue(forKey: envelope.id) {
            pending.timeoutTask.cancel()
            pending.continuation.resume(returning: envelope)
            return
        }
        
        // Handle push messages
        switch envelope.payload {
        case .sample(let sample):
            onSample?(sample)
        default:
            break
        }
    }
    
    // MARK: - Sending
    
    private func send(_ envelope: Snmpproxy_V1_Envelope) async throws {
        guard let connection = connection else {
            throw ProxyError.notConnected
        }
        
        let data = try envelope.serializedData()
        let framed = WireProtocol.frame(data)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    private func request(_ envelope: Snmpproxy_V1_Envelope) async throws -> Snmpproxy_V1_Envelope {
        guard state == .connected || state == .authenticating else {
            throw ProxyError.notConnected
        }
        
        var envelope = envelope
        requestID += 1
        envelope.id = requestID
        let currentID = envelope.id
        
        try await send(envelope)
        
        return try await withCheckedThrowingContinuation { [weak self, requestTimeout] continuation in
            guard let self = self else {
                continuation.resume(throwing: ProxyError.notConnected)
                return
            }
            
            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(requestTimeout * 1_000_000_000))
                
                guard !Task.isCancelled else { return }
                
                if let pending = self?.pendingRequests.removeValue(forKey: currentID) {
                    pending.continuation.resume(throwing: ProxyError.timeout)
                }
            }
            
            pendingRequests[currentID] = PendingRequest(
                continuation: continuation,
                createdAt: Date(),
                timeoutTask: timeoutTask
            )
        }
    }
    
    // MARK: - Authentication
    
    private func authenticate(token: String) async throws {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.auth = Snmpproxy_V1_AuthRequest.with { $0.token = token }
        
        let response = try await request(envelope)
        
        if case .authResp(let authResp) = response.payload {
            if authResp.ok {
                sessionID = authResp.sessionID
            } else {
                throw ProxyError.authFailed(authResp.message)
            }
        } else if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        } else {
            throw ProxyError.unexpectedResponse
        }
    }
    
    // MARK: - API Methods
    
    func monitor(
        host: String,
        port: UInt32 = 161,
        oid: String,
        intervalMs: UInt32 = 1000,
        bufferSize: UInt32 = 3600,
        snmpConfig: Snmpproxy_V1_SNMPConfig
    ) async throws -> (targetID: String, created: Bool) {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.monitor = Snmpproxy_V1_MonitorRequest.with {
            $0.host = host
            $0.port = port
            $0.oid = oid
            $0.intervalMs = intervalMs
            $0.bufferSize = bufferSize
            $0.snmp = snmpConfig
        }
        
        let response = try await request(envelope)
        
        if case .monitorResp(let resp) = response.payload {
            targets[resp.targetID] = ProxyTarget(
                id: resp.targetID,
                host: host,
                port: port,
                oid: oid,
                intervalMs: intervalMs
            )
            return (resp.targetID, resp.created)
        } else if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
        
        throw ProxyError.unexpectedResponse
    }
    
    func unmonitor(targetID: String) async throws {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.unmonitor = Snmpproxy_V1_UnmonitorRequest.with { $0.targetID = targetID }
        
        let response = try await request(envelope)
        
        if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
        
        targets.removeValue(forKey: targetID)
    }
    
    func listTargets(filterHost: String = "") async throws -> [Snmpproxy_V1_Target] {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.listTargets = Snmpproxy_V1_ListTargetsRequest.with {
            $0.filterHost = filterHost
        }
        
        let response = try await request(envelope)
        
        if case .listTargetsResp(let resp) = response.payload {
            return resp.targets
        } else if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
        
        throw ProxyError.unexpectedResponse
    }
    
    func getTarget(targetID: String) async throws -> Snmpproxy_V1_Target {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.getTarget = Snmpproxy_V1_GetTargetRequest.with { $0.targetID = targetID }
        
        let response = try await request(envelope)
        
        if case .getTargetResp(let resp) = response.payload {
            return resp.target
        } else if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
        
        throw ProxyError.unexpectedResponse
    }
    
    func subscribe(targetIDs: [String]) async throws -> [String] {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.subscribe = Snmpproxy_V1_SubscribeRequest.with { $0.targetIds = targetIDs }
        
        let response = try await request(envelope)
        
        if case .subscribeResp(let resp) = response.payload {
            return resp.subscribed
        } else if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
        
        throw ProxyError.unexpectedResponse
    }
    
    func unsubscribe(targetIDs: [String] = []) async throws {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.unsubscribe = Snmpproxy_V1_UnsubscribeRequest.with { $0.targetIds = targetIDs }
        
        let response = try await request(envelope)
        
        if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
    }
    
    func getHistory(targetIDs: [String], lastN: UInt32 = 100) async throws -> [Snmpproxy_V1_TargetHistory] {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.getHistory = Snmpproxy_V1_GetHistoryRequest.with {
            $0.targetIds = targetIDs
            $0.lastN = lastN
        }
        
        let response = try await request(envelope)
        
        if case .getHistoryResp(let resp) = response.payload {
            return resp.history
        } else if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
        
        throw ProxyError.unexpectedResponse
    }
    
    // MARK: - NEW: Status & Config API
    
    /// Get server status information
    func getServerStatus() async throws -> Snmpproxy_V1_GetServerStatusResponse {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.getServerStatus = Snmpproxy_V1_GetServerStatusRequest()
        
        let response = try await request(envelope)
        
        if case .getServerStatusResp(let resp) = response.payload {
            return resp
        } else if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
        
        throw ProxyError.unexpectedResponse
    }
    
    /// Get current session information
    func getSessionInfo() async throws -> Snmpproxy_V1_GetSessionInfoResponse {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.getSessionInfo = Snmpproxy_V1_GetSessionInfoRequest()
        
        let response = try await request(envelope)
        
        if case .getSessionInfoResp(let resp) = response.payload {
            return resp
        } else if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
        
        throw ProxyError.unexpectedResponse
    }
    
    /// Update target settings (interval, timeout, retries, buffer)
    func updateTarget(
        targetID: String,
        intervalMs: UInt32 = 0,
        timeoutMs: UInt32 = 0,
        retries: UInt32 = 0,
        bufferSize: UInt32 = 0
    ) async throws -> Snmpproxy_V1_UpdateTargetResponse {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.updateTarget = Snmpproxy_V1_UpdateTargetRequest.with {
            $0.targetID = targetID
            $0.intervalMs = intervalMs
            $0.timeoutMs = timeoutMs
            $0.retries = retries
            $0.bufferSize = bufferSize
        }
        
        let response = try await request(envelope)
        
        if case .updateTargetResp(let resp) = response.payload {
            return resp
        } else if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
        
        throw ProxyError.unexpectedResponse
    }
    
    /// Get runtime configuration
    func getConfig() async throws -> Snmpproxy_V1_RuntimeConfig {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.getConfig = Snmpproxy_V1_GetConfigRequest()
        
        let response = try await request(envelope)
        
        if case .getConfigResp(let resp) = response.payload {
            return resp.config
        } else if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
        
        throw ProxyError.unexpectedResponse
    }
    
    /// Set runtime configuration
    func setConfig(
        defaultTimeoutMs: UInt32 = 0,
        defaultRetries: UInt32 = 0,
        defaultBufferSize: UInt32 = 0,
        minIntervalMs: UInt32 = 0
    ) async throws -> Snmpproxy_V1_SetConfigResponse {
        var envelope = Snmpproxy_V1_Envelope()
        envelope.setConfig = Snmpproxy_V1_SetConfigRequest.with {
            $0.defaultTimeoutMs = defaultTimeoutMs
            $0.defaultRetries = defaultRetries
            $0.defaultBufferSize = defaultBufferSize
            $0.minIntervalMs = minIntervalMs
        }
        
        let response = try await request(envelope)
        
        if case .setConfigResp(let resp) = response.payload {
            return resp
        } else if case .error(let error) = response.payload {
            throw ProxyError.serverError(error.code, error.message)
        }
        
        throw ProxyError.unexpectedResponse
    }
}

// MARK: - Supporting Types

struct ProxyTarget: Identifiable {
    let id: String
    let host: String
    let port: UInt32
    let oid: String
    let intervalMs: UInt32
}

enum ProxyError: LocalizedError {
    case authFailed(String)
    case serverError(Int32, String)
    case unexpectedResponse
    case notConnected
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .authFailed(let msg): return "Authentication failed: \(msg)"
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .unexpectedResponse: return "Unexpected response from server"
        case .notConnected: return "Not connected to server"
        case .timeout: return "Request timeout"
        }
    }
}

// MARK: - TLS Options

enum TLSOptions {
    static var insecure: NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, completion in
            completion(true)
        }, .main)
        
        return options
    }
}
