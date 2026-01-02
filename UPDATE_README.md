# Swift Client Update

Update für Feature-Parity mit dem CLI-Client (snmpctl).

## Neue Features

| Feature | Beschreibung |
|---------|-------------|
| Server Status | Version, Uptime, Sessions, Targets, Poller-Stats |
| Session Info | Session-ID, Token, Owned/Subscribed Targets |
| Update Target | Interval, Timeout, Retries, Buffer zur Laufzeit ändern |
| Get/Set Config | Runtime-Konfiguration anzeigen/ändern |
| Target Detail | Erweiterte Target-Statistiken (polls, timing) |

## Integration

### 1. Proto-Datei ersetzen

```bash
cp Proto/snmpproxy.proto /path/to/SNMPProxyClient/Proto/
```

### 2. Protobuf neu generieren

```bash
cd /path/to/SNMPProxyClient
make proto
```

### 3. Swift-Dateien kopieren

```bash
# ProxyClient mit neuen API-Methoden
cp Network/ProxyClient.swift /path/to/SNMPProxyClient/Network/

# Neue Views
cp Views/ServerStatusView.swift /path/to/SNMPProxyClient/Views/
cp Views/SessionInfoView.swift /path/to/SNMPProxyClient/Views/
cp Views/ConfigView.swift /path/to/SNMPProxyClient/Views/
cp Views/TargetDetailView.swift /path/to/SNMPProxyClient/Views/

# Aktualisierte ContentView mit Menü
cp Views/ContentView.swift /path/to/SNMPProxyClient/Views/
```

### 4. Neue Dateien in Xcode hinzufügen

In Xcode:
1. Rechtsklick auf Views-Gruppe → "Add Files to..."
2. Die neuen .swift Dateien auswählen
3. Build & Run

## Neue ProxyClient API-Methoden

```swift
// Server Status
let status = try await proxyClient.getServerStatus()
print("Uptime: \(status.uptimeMs)ms")

// Session Info
let session = try await proxyClient.getSessionInfo()
print("Owned: \(session.ownedTargets)")

// Update Target
let resp = try await proxyClient.updateTarget(
    targetID: "abc123",
    intervalMs: 500,      // 0 = don't change
    bufferSize: 7200
)

// Get Config
let config = try await proxyClient.getConfig()
print("Min interval: \(config.minIntervalMs)")

// Set Config
let resp = try await proxyClient.setConfig(
    defaultTimeoutMs: 3000,
    minIntervalMs: 200
)
```

## UI-Zugang

Die neuen Features sind über das "..." Menü in der Toolbar erreichbar:

- **Server Status** - Server-Informationen und Statistiken
- **Session Info** - Aktuelle Session-Details
- **Configuration** - Runtime-Konfiguration bearbeiten

Target-Details sind über Rechtsklick → "Show Details" in der Sidebar erreichbar.

## Dateien

```
swift-client/
├── Makefile                      # Proto-Generation
├── Proto/
│   └── snmpproxy.proto          # Aktualisiert (Server-kompatibel)
├── Network/
│   └── ProxyClient.swift        # Mit neuen API-Methoden
└── Views/
    ├── ContentView.swift        # Mit Menü-Integration
    ├── ServerStatusView.swift   # NEU
    ├── SessionInfoView.swift    # NEU
    ├── ConfigView.swift         # NEU
    └── TargetDetailView.swift   # NEU (mit Edit-Sheet)
```
