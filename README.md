# SNMP Proxy Client

Native macOS client for snmpproxyd with live graphing.

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15+
- swift-protobuf

## Setup

### 1. Install swift-protobuf

```bash
brew install swift-protobuf
```

### 2. Generate Protobuf Files

```bash
make proto
```

### 3. Create Xcode Project

1. Open Xcode
2. File → New → Project
3. Choose "App" (macOS)
4. Product Name: `SNMPProxyClient`
5. Interface: SwiftUI
6. Language: Swift

### 4. Add Files to Project

Drag all `.swift` files from this directory into the Xcode project.

### 5. Add SwiftProtobuf Package

1. File → Add Package Dependencies
2. Enter: `https://github.com/apple/swift-protobuf.git`
3. Add to target: SNMPProxyClient

### 6. Build & Run

Press ⌘R

## Usage

1. Click connection status → Connect
2. Enter server details and token
3. Click "+" to add a target
4. Enter SNMP details (host, OID, community or v3 credentials)
5. Select target in sidebar to view graph

## Features

- [x] Connect to snmpproxyd
- [x] SNMPv2c and SNMPv3 support
- [x] Live streaming graphs
- [x] Multiple targets
- [x] Rate calculation (counter → bps)
- [x] Counter wrap detection (64-bit)
- [x] Configurable time windows
- [x] Request timeouts
- [x] Proper cancellation support

## Architecture

```
┌─────────────────────────────────────────────┐
│                    Views                     │
│  ContentView → LiveGraphView                │
│              → AddTargetSheet               │
│              → ConnectSheet                 │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│              Services                        │
│  TimeSeriesStore (rate calculation, storage)│
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│              Network                         │
│  ProxyClient (TCP + Protobuf)               │
│  WireProtocol (varint length-delimited)     │
└─────────────────────────────────────────────┘
```

## File Structure

```
SNMPProxyClient/
├── App/
│   └── SNMPProxyClientApp.swift    # Entry point
├── Models/
│   └── Proto/
│       └── snmpproxy.pb.swift      # Generated
├── Network/
│   ├── ConnectionState.swift
│   ├── ProxyClient.swift           # TCP client with timeout support
│   └── WireProtocol.swift          # Varint framing
├── Services/
│   └── TimeSeriesStore.swift       # Data management
├── Views/
│   ├── ContentView.swift
│   ├── LiveGraphView.swift         # Swift Charts
│   ├── ConnectSheet.swift
│   ├── AddTargetSheet.swift
│   └── SettingsView.swift
└── Proto/
    └── snmpproxy.proto
```

## Wire Protocol

The client uses **varint-prefixed length-delimited protobuf**, compatible with
Go's `google.golang.org/protobuf/encoding/protodelim`.

```
┌─────────────────────────────────────────────┐
│ [varint: message length][protobuf payload]  │
└─────────────────────────────────────────────┘
```

**Varint encoding:**
- Each byte: 7 data bits + 1 continuation bit (MSB)
- MSB=1: more bytes follow
- MSB=0: last byte

Example implementation in `WireProtocol.swift`:

```swift
static func frame(_ data: Data) -> Data {
    var framed = Data()
    framed.append(contentsOf: encodeVarint(UInt64(data.count)))
    framed.append(data)
    return framed
}

private static func encodeVarint(_ value: UInt64) -> [UInt8] {
    var v = value
    var result: [UInt8] = []
    while v > 0x7F {
        result.append(UInt8((v & 0x7F) | 0x80))
        v >>= 7
    }
    result.append(UInt8(v))
    return result
}
```

## Timeout Configuration

The `ProxyClient` supports configurable timeouts:

```swift
let client = ProxyClient(
    requestTimeout: 30.0,      // Individual request timeout
    connectionTimeout: 10.0    // Initial connection timeout
)
```

## Error Handling

The client handles various error conditions:

| Error | Description |
|-------|-------------|
| `authFailed` | Authentication rejected by server |
| `serverError` | Server returned an error response |
| `unexpectedResponse` | Protocol mismatch |
| `notConnected` | No active connection |
| `timeout` | Request or connection timed out |

## Known Limitations

- No automatic reconnection (planned)
- TLS certificate validation disabled (uses `InsecureSkipVerify`)
- No credential storage (token must be provided each session)

## Troubleshooting

### Connection hangs
The client uses a dedicated dispatch queue to avoid deadlocks with `@MainActor`.
If connections hang, check that the server is reachable.

### Rate shows as 0
Rate calculation requires at least 2 samples. Wait for the polling interval.

### Graph not updating
Ensure the target is subscribed (check sidebar selection).

## License

MIT
