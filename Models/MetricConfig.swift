import Foundation

// MARK: - Metric Configuration

/// Complete configuration for how a metric value is processed and displayed
struct MetricConfig: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    
    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: 1. DATA TYPE - How the raw value is processed
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// How to interpret the raw SNMP value
    var metricType: MetricType = .counter
    
    /// Counter bit width for wrap detection
    var counterBits: CounterBits = .bits64
    
    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: 2. TRANSFORMATION - Raw value → Display value
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// Multiplier applied to raw value (e.g., 8 for octets→bits)
    var multiplier: Double = 1.0
    
    /// Divisor applied to raw value (e.g., 1024 for bytes→KiB)
    var divisor: Double = 1.0
    
    /// Offset added after multiply/divide (e.g., -273.15 for Kelvin→Celsius)
    var offset: Double = 0.0
    
    // Formula: displayValue = (rawValue × multiplier / divisor) + offset
    
    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: 3. UNIT & SCALING
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// Unit configuration (preset or custom)
    var unit: UnitConfig = .preset(.bitsPerSec)
    
    /// Force a specific scale tier (nil = auto)
    var forceScaleTier: ScaleTier? = nil
    
    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: 4. DISPLAY OPTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// Number of decimal places (0-6)
    var decimalPlaces: Int = 2
    
    /// Show "+" for positive values
    var showPlusSign: Bool = false
    
    /// Optional color thresholds for visual feedback
    var colorThresholds: ColorThresholds? = nil
    
    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: 5. GRAPH OPTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// Graph display configuration
    var graphConfig: GraphConfig = GraphConfig()
    
    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: 6. METADATA
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// Custom display name (overrides OID-based display)
    var displayName: String? = nil
    
    /// Description for tooltips/info
    var description: String? = nil
}

// MARK: - Metric Type

/// How to interpret the raw SNMP value
enum MetricType: String, Codable, CaseIterable, Identifiable {
    /// Monotonically increasing counter - calculate rate (delta/time)
    case counter
    
    /// Absolute value that can go up or down - display directly
    case gauge
    
    /// Like counter but can decrease (rare, e.g., TCP retransmits)
    case derive
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .counter: return "Counter"
        case .gauge: return "Gauge"
        case .derive: return "Derive"
        }
    }
    
    var description: String {
        switch self {
        case .counter: return "Monotonically increasing (e.g., bytes transferred)"
        case .gauge: return "Absolute value (e.g., CPU %, temperature)"
        case .derive: return "Like counter, but can decrease"
        }
    }
}

// MARK: - Counter Bits

/// Bit width for counter wrap detection
enum CounterBits: Int, Codable, CaseIterable, Identifiable {
    case bits32 = 32  // Max: 4,294,967,295 (older MIBs, e.g., ifInOctets)
    case bits64 = 64  // Max: 18,446,744,073,709,551,615 (HC counters)
    
    var id: Int { rawValue }
    
    var maxValue: UInt64 {
        switch self {
        case .bits32: return UInt64(UInt32.max)
        case .bits64: return UInt64.max
        }
    }
    
    var displayName: String {
        switch self {
        case .bits32: return "32-bit (Standard)"
        case .bits64: return "64-bit (HC Counter)"
        }
    }
}

// MARK: - Unit Configuration

/// Unit display configuration - either a preset or custom
enum UnitConfig: Codable, Hashable {
    case preset(PresetUnit)
    case custom(CustomUnit)
    
    var displayName: String {
        switch self {
        case .preset(let unit): return unit.displayName
        case .custom(let unit): return unit.baseUnit
        }
    }
}

/// Predefined unit types with automatic scaling
enum PresetUnit: String, Codable, CaseIterable, Identifiable {
    case bitsPerSec      // bps, Kbps, Mbps, Gbps, Tbps
    case bytesPerSec     // B/s, KB/s, MB/s, GB/s (decimal, 1000)
    case bytesPerSecIEC  // B/s, KiB/s, MiB/s, GiB/s (binary, 1024)
    case packetsPerSec   // pps, Kpps, Mpps
    case percent         // % (no scaling)
    case celsius         // °C (no scaling)
    case fahrenheit      // °F (no scaling)
    case watts           // W, kW, MW
    case hertz           // Hz, kHz, MHz, GHz
    case bytes           // B, KB, MB, GB (decimal)
    case bytesIEC        // B, KiB, MiB, GiB (binary)
    case count           // (none), K, M, G
    case countPerSec     // /s, K/s, M/s
    case milliseconds    // ms (no scaling)
    case seconds         // s (no scaling)
    case raw             // No unit, just the number
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .bitsPerSec: return "Bits/sec (bps, Kbps, Mbps...)"
        case .bytesPerSec: return "Bytes/sec (B/s, KB/s, MB/s...)"
        case .bytesPerSecIEC: return "Bytes/sec IEC (B/s, KiB/s, MiB/s...)"
        case .packetsPerSec: return "Packets/sec (pps, Kpps...)"
        case .percent: return "Percent (%)"
        case .celsius: return "Celsius (°C)"
        case .fahrenheit: return "Fahrenheit (°F)"
        case .watts: return "Watts (W, kW, MW)"
        case .hertz: return "Hertz (Hz, kHz, MHz, GHz)"
        case .bytes: return "Bytes (B, KB, MB, GB)"
        case .bytesIEC: return "Bytes IEC (B, KiB, MiB, GiB)"
        case .count: return "Count (K, M, G)"
        case .countPerSec: return "Count/sec (/s, K/s, M/s)"
        case .milliseconds: return "Milliseconds (ms)"
        case .seconds: return "Seconds (s)"
        case .raw: return "Raw (no unit)"
        }
    }
    
    var baseUnit: String {
        switch self {
        case .bitsPerSec: return "bps"
        case .bytesPerSec, .bytesPerSecIEC: return "B/s"
        case .packetsPerSec: return "pps"
        case .percent: return "%"
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        case .watts: return "W"
        case .hertz: return "Hz"
        case .bytes, .bytesIEC: return "B"
        case .count: return ""
        case .countPerSec: return "/s"
        case .milliseconds: return "ms"
        case .seconds: return "s"
        case .raw: return ""
        }
    }
    
    var scaleBase: Int {
        switch self {
        case .bytesPerSecIEC, .bytesIEC: return 1024
        case .percent, .celsius, .fahrenheit, .milliseconds, .seconds, .raw: return 1  // No scaling
        default: return 1000
        }
    }
    
    var prefixes: [String] {
        switch self {
        case .bytesPerSecIEC, .bytesIEC:
            return ["", "Ki", "Mi", "Gi", "Ti", "Pi"]
        case .percent, .celsius, .fahrenheit, .milliseconds, .seconds, .raw:
            return [""]  // No scaling
        default:
            return ["", "K", "M", "G", "T", "P"]
        }
    }
}

/// Custom unit configuration
struct CustomUnit: Codable, Hashable {
    /// Base unit string (e.g., "IOPS", "req", "°F")
    var baseUnit: String
    
    /// Enable automatic scaling
    var useAutoScale: Bool = true
    
    /// Scale base (1000 for SI, 1024 for IEC)
    var scaleBase: ScaleBase = .decimal
    
    /// Custom prefixes (nil = use default SI/IEC prefixes)
    var customPrefixes: [String]? = nil
    
    var prefixes: [String] {
        if let custom = customPrefixes {
            return custom
        }
        return scaleBase == .binary 
            ? ["", "Ki", "Mi", "Gi", "Ti", "Pi"]
            : ["", "K", "M", "G", "T", "P"]
    }
}

/// Scale base for custom units
enum ScaleBase: Int, Codable, CaseIterable, Identifiable {
    case decimal = 1000  // SI: K, M, G, T
    case binary = 1024   // IEC: Ki, Mi, Gi, Ti
    case none = 1        // No scaling
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .decimal: return "Decimal (1000)"
        case .binary: return "Binary (1024)"
        case .none: return "None"
        }
    }
}

// MARK: - Scale Tier

/// Force a specific scale tier
enum ScaleTier: String, Codable, CaseIterable, Identifiable {
    case base   // bps, B/s
    case kilo   // Kbps, KB/s
    case mega   // Mbps, MB/s
    case giga   // Gbps, GB/s
    case tera   // Tbps, TB/s
    case peta   // Pbps, PB/s
    
    var id: String { rawValue }
    
    var index: Int {
        switch self {
        case .base: return 0
        case .kilo: return 1
        case .mega: return 2
        case .giga: return 3
        case .tera: return 4
        case .peta: return 5
        }
    }
    
    var displayName: String {
        switch self {
        case .base: return "Base (no prefix)"
        case .kilo: return "Kilo (K)"
        case .mega: return "Mega (M)"
        case .giga: return "Giga (G)"
        case .tera: return "Tera (T)"
        case .peta: return "Peta (P)"
        }
    }
}

// MARK: - Color Thresholds

/// Color thresholds for visual feedback
struct ColorThresholds: Codable, Hashable {
    /// Value above which to show warning color (yellow)
    var warning: Double? = nil
    
    /// Value above which to show critical color (red)
    var critical: Double? = nil
    
    /// Invert logic: low values are bad (e.g., free disk space)
    var inverted: Bool = false
    
    /// Get the threshold level for a value
    func level(for value: Double) -> ThresholdLevel {
        let compareValue = inverted ? -value : value
        let warningCompare = inverted ? -(warning ?? Double.infinity) : (warning ?? Double.infinity)
        let criticalCompare = inverted ? -(critical ?? Double.infinity) : (critical ?? Double.infinity)
        
        if let crit = critical, inverted ? compareValue < criticalCompare : compareValue >= crit {
            return .critical
        }
        if let warn = warning, inverted ? compareValue < warningCompare : compareValue >= warn {
            return .warning
        }
        return .normal
    }
}

/// Threshold level for coloring
enum ThresholdLevel {
    case normal
    case warning
    case critical
}

// MARK: - Graph Configuration

/// Graph display options
struct GraphConfig: Codable, Hashable {
    /// Minimum Y-axis value (nil = auto)
    var yAxisMin: Double? = nil
    
    /// Maximum Y-axis value (nil = auto, e.g., 100 for percent)
    var yAxisMax: Double? = nil
    
    /// Show zero baseline
    var showBaseline: Bool = false
    
    /// Use logarithmic scale for large value ranges
    var logarithmic: Bool = false
    
    /// Stack multiple series (for area charts)
    var stacked: Bool = false
    
    /// Fill area under line
    var fillArea: Bool = true
    
    /// Line width
    var lineWidth: Double = 2.0
}

// MARK: - Preset Configurations

extension MetricConfig {
    
    // ─────────────────────────────────────────────────────────────────────────
    // Network Traffic
    // ─────────────────────────────────────────────────────────────────────────
    
    /// Network octets (bytes) in - displayed as Mbps
    static let networkOctetsIn = MetricConfig(
        metricType: .counter,
        counterBits: .bits64,
        multiplier: 8,  // Octets → Bits
        unit: .preset(.bitsPerSec),
        displayName: "Inbound Traffic",
        description: "Network traffic received (ifHCInOctets)"
    )
    
    /// Network octets (bytes) out - displayed as Mbps
    static let networkOctetsOut = MetricConfig(
        metricType: .counter,
        counterBits: .bits64,
        multiplier: 8,
        unit: .preset(.bitsPerSec),
        displayName: "Outbound Traffic",
        description: "Network traffic sent (ifHCOutOctets)"
    )
    
    /// Network packets per second
    static let networkPackets = MetricConfig(
        metricType: .counter,
        counterBits: .bits64,
        unit: .preset(.packetsPerSec),
        displayName: "Packets",
        description: "Network packets (ifHCInUcastPkts, etc.)"
    )
    
    /// Network errors per second
    static let networkErrors = MetricConfig(
        metricType: .counter,
        counterBits: .bits64,
        unit: .preset(.countPerSec),
        colorThresholds: ColorThresholds(warning: 1, critical: 10),
        displayName: "Errors",
        description: "Network errors (ifInErrors, ifOutErrors)"
    )
    
    // ─────────────────────────────────────────────────────────────────────────
    // CPU & Memory
    // ─────────────────────────────────────────────────────────────────────────
    
    /// CPU load percentage
    static let cpuLoad = MetricConfig(
        metricType: .gauge,
        unit: .preset(.percent),
        colorThresholds: ColorThresholds(warning: 70, critical: 90),
        graphConfig: GraphConfig(yAxisMin: 0, yAxisMax: 100),
        displayName: "CPU Load",
        description: "CPU utilization (hrProcessorLoad)"
    )
    
    /// Memory usage percentage
    static let memoryUsedPercent = MetricConfig(
        metricType: .gauge,
        unit: .preset(.percent),
        colorThresholds: ColorThresholds(warning: 80, critical: 95),
        graphConfig: GraphConfig(yAxisMin: 0, yAxisMax: 100),
        displayName: "Memory Used",
        description: "Memory utilization percentage"
    )
    
    /// Memory in bytes (absolute)
    static let memoryBytes = MetricConfig(
        metricType: .gauge,
        unit: .preset(.bytesIEC),
        displayName: "Memory",
        description: "Memory in bytes (hrStorageUsed × hrStorageAllocationUnits)"
    )
    
    // ─────────────────────────────────────────────────────────────────────────
    // Disk & Storage
    // ─────────────────────────────────────────────────────────────────────────
    
    /// Disk usage percentage
    static let diskUsedPercent = MetricConfig(
        metricType: .gauge,
        unit: .preset(.percent),
        colorThresholds: ColorThresholds(warning: 80, critical: 95),
        graphConfig: GraphConfig(yAxisMin: 0, yAxisMax: 100),
        displayName: "Disk Used",
        description: "Disk utilization percentage"
    )
    
    /// Disk free space (inverted threshold - low is bad)
    static let diskFreeBytes = MetricConfig(
        metricType: .gauge,
        unit: .preset(.bytesIEC),
        colorThresholds: ColorThresholds(warning: 10_737_418_240, critical: 1_073_741_824, inverted: true), // 10GB, 1GB
        displayName: "Disk Free",
        description: "Available disk space"
    )
    
    /// Disk IOPS
    static let diskIOPS = MetricConfig(
        metricType: .counter,
        unit: .custom(CustomUnit(baseUnit: "IOPS", useAutoScale: true)),
        displayName: "Disk IOPS",
        description: "Disk I/O operations per second"
    )
    
    /// Disk throughput
    static let diskThroughput = MetricConfig(
        metricType: .counter,
        unit: .preset(.bytesPerSec),
        displayName: "Disk Throughput",
        description: "Disk read/write bytes per second"
    )
    
    // ─────────────────────────────────────────────────────────────────────────
    // Temperature & Power
    // ─────────────────────────────────────────────────────────────────────────
    
    /// Temperature in Celsius
    static let temperatureCelsius = MetricConfig(
        metricType: .gauge,
        unit: .preset(.celsius),
        colorThresholds: ColorThresholds(warning: 60, critical: 80),
        displayName: "Temperature",
        description: "Temperature sensor reading"
    )
    
    /// Temperature in Fahrenheit
    static let temperatureFahrenheit = MetricConfig(
        metricType: .gauge,
        unit: .preset(.fahrenheit),
        colorThresholds: ColorThresholds(warning: 140, critical: 176),
        displayName: "Temperature",
        description: "Temperature sensor reading"
    )
    
    /// Power consumption
    static let powerWatts = MetricConfig(
        metricType: .gauge,
        unit: .preset(.watts),
        displayName: "Power",
        description: "Power consumption"
    )
    
    // ─────────────────────────────────────────────────────────────────────────
    // Response Time & Latency
    // ─────────────────────────────────────────────────────────────────────────
    
    /// Response time in milliseconds
    static let responseTimeMs = MetricConfig(
        metricType: .gauge,
        unit: .preset(.milliseconds),
        colorThresholds: ColorThresholds(warning: 100, critical: 500),
        displayName: "Response Time",
        description: "Response time in milliseconds"
    )
    
    /// Uptime in seconds
    static let uptimeSeconds = MetricConfig(
        metricType: .gauge,
        unit: .preset(.seconds),
        displayName: "Uptime",
        description: "System uptime (sysUpTime / 100)"
    )
    
    // ─────────────────────────────────────────────────────────────────────────
    // Generic
    // ─────────────────────────────────────────────────────────────────────────
    
    /// Generic counter (rate)
    static let genericCounter = MetricConfig(
        metricType: .counter,
        unit: .preset(.countPerSec),
        displayName: "Counter Rate",
        description: "Generic counter rate"
    )
    
    /// Generic gauge
    static let genericGauge = MetricConfig(
        metricType: .gauge,
        unit: .preset(.raw),
        displayName: "Gauge",
        description: "Generic gauge value"
    )
}

// MARK: - OID Auto-Detection

extension MetricConfig {
    
    /// Known OID prefixes and their default configurations
    static let oidPresets: [String: MetricConfig] = [
        // IF-MIB - Interface statistics (64-bit HC counters)
        "1.3.6.1.2.1.31.1.1.1.6":  .networkOctetsIn,   // ifHCInOctets
        "1.3.6.1.2.1.31.1.1.1.10": .networkOctetsOut,  // ifHCOutOctets
        "1.3.6.1.2.1.31.1.1.1.7":  .networkPackets,    // ifHCInUcastPkts
        "1.3.6.1.2.1.31.1.1.1.11": .networkPackets,    // ifHCOutUcastPkts
        
        // IF-MIB - 32-bit counters (legacy)
        "1.3.6.1.2.1.2.2.1.10": MetricConfig(
            metricType: .counter,
            counterBits: .bits32,
            multiplier: 8,
            unit: .preset(.bitsPerSec),
            displayName: "Inbound Traffic",
            description: "ifInOctets (32-bit)"
        ),
        "1.3.6.1.2.1.2.2.1.16": MetricConfig(
            metricType: .counter,
            counterBits: .bits32,
            multiplier: 8,
            unit: .preset(.bitsPerSec),
            displayName: "Outbound Traffic",
            description: "ifOutOctets (32-bit)"
        ),
        "1.3.6.1.2.1.2.2.1.14": .networkErrors,        // ifInErrors
        "1.3.6.1.2.1.2.2.1.20": .networkErrors,        // ifOutErrors
        
        // HOST-RESOURCES-MIB
        "1.3.6.1.2.1.25.3.3.1.2":  .cpuLoad,           // hrProcessorLoad
        "1.3.6.1.2.1.25.2.3.1.6":  .memoryBytes,       // hrStorageUsed
        
        // UCD-SNMP-MIB (Net-SNMP)
        "1.3.6.1.4.1.2021.11.9":   .cpuLoad,           // ssCpuUser
        "1.3.6.1.4.1.2021.11.10":  .cpuLoad,           // ssCpuSystem
        "1.3.6.1.4.1.2021.11.11":  .cpuLoad,           // ssCpuIdle
        "1.3.6.1.4.1.2021.4.6":    .memoryBytes,       // memAvailReal
        "1.3.6.1.4.1.2021.4.5":    .memoryBytes,       // memTotalReal
    ]
    
    /// Get a preset configuration for an OID, or nil if unknown
    static func preset(for oid: String) -> MetricConfig? {
        // Try exact match first
        if let config = oidPresets[oid] {
            return config
        }
        
        // Try prefix match (OID without instance)
        for (prefix, config) in oidPresets {
            if oid.hasPrefix(prefix + ".") {
                return config
            }
        }
        
        return nil
    }
}

// MARK: - Template List

extension MetricConfig {
    
    /// All available preset templates for UI picker
    static let allTemplates: [(name: String, config: MetricConfig)] = [
        // Network
        ("Network Traffic In (Mbps)", .networkOctetsIn),
        ("Network Traffic Out (Mbps)", .networkOctetsOut),
        ("Network Packets", .networkPackets),
        ("Network Errors", .networkErrors),
        
        // CPU & Memory
        ("CPU Load (%)", .cpuLoad),
        ("Memory Used (%)", .memoryUsedPercent),
        ("Memory (Bytes)", .memoryBytes),
        
        // Disk
        ("Disk Used (%)", .diskUsedPercent),
        ("Disk Free (Bytes)", .diskFreeBytes),
        ("Disk IOPS", .diskIOPS),
        ("Disk Throughput", .diskThroughput),
        
        // Temperature & Power
        ("Temperature (°C)", .temperatureCelsius),
        ("Temperature (°F)", .temperatureFahrenheit),
        ("Power (Watts)", .powerWatts),
        
        // Timing
        ("Response Time (ms)", .responseTimeMs),
        ("Uptime (seconds)", .uptimeSeconds),
        
        // Generic
        ("Generic Counter (rate)", .genericCounter),
        ("Generic Gauge", .genericGauge),
    ]
}
