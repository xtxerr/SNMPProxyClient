import Foundation
import SwiftUI

// MARK: - Metric Formatter

/// Formats metric values according to a MetricConfig
struct MetricFormatter {
    let config: MetricConfig
    
    // Standard SI prefixes
    private static let siPrefixes = ["", "K", "M", "G", "T", "P", "E"]
    
    // IEC binary prefixes
    private static let iecPrefixes = ["", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei"]
    
    // MARK: - Format Value
    
    /// Format a raw value according to the configuration
    /// - Parameter rawValue: The raw value (rate for counters, direct value for gauges)
    /// - Returns: Formatted string with unit
    func format(_ rawValue: Double) -> String {
        // 1. Apply transformation
        let transformed = transform(rawValue)
        
        // 2. Determine scaling
        let (scaledValue, prefix) = autoScale(transformed)
        
        // 3. Format number
        let sign = (config.showPlusSign && scaledValue > 0) ? "+" : ""
        let number = formatNumber(scaledValue)
        let unit = unitString(prefix: prefix)
        
        // 4. Combine
        if unit.isEmpty {
            return "\(sign)\(number)"
        } else {
            return "\(sign)\(number) \(unit)"
        }
    }
    
    /// Format just the number without unit
    func formatNumberOnly(_ rawValue: Double) -> String {
        let transformed = transform(rawValue)
        let (scaledValue, _) = autoScale(transformed)
        return formatNumber(scaledValue)
    }
    
    /// Get the unit string for the current scale
    func formatUnitOnly(_ rawValue: Double) -> String {
        let transformed = transform(rawValue)
        let (_, prefix) = autoScale(transformed)
        return unitString(prefix: prefix)
    }
    
    // MARK: - Transformation
    
    /// Apply transformation formula: (rawValue × multiplier / divisor) + offset
    func transform(_ rawValue: Double) -> Double {
        return (rawValue * config.multiplier / config.divisor) + config.offset
    }
    
    /// Reverse transformation (for axis labels, thresholds)
    func reverseTransform(_ displayValue: Double) -> Double {
        return ((displayValue - config.offset) * config.divisor) / config.multiplier
    }
    
    // MARK: - Auto Scaling
    
    /// Automatically determine the best scale tier for a value
    private func autoScale(_ value: Double) -> (Double, String) {
        // Fixed scaling?
        if let tier = config.forceScaleTier {
            return applyTier(value, tier: tier)
        }
        
        // Get scale parameters
        let base = scaleBase
        let prefixes = prefixList
        
        // No scaling?
        if base <= 1 || prefixes.count <= 1 {
            return (value, prefixes.first ?? "")
        }
        
        // Auto-scale
        let absValue = abs(value)
        var tier = 0
        var scaled = absValue
        
        while scaled >= Double(base) && tier < prefixes.count - 1 {
            scaled /= Double(base)
            tier += 1
        }
        
        // Apply the same scaling to the original value (preserving sign)
        let divisor = pow(Double(base), Double(tier))
        return (value / divisor, prefixes[tier])
    }
    
    /// Apply a specific scale tier
    private func applyTier(_ value: Double, tier: ScaleTier) -> (Double, String) {
        let base = Double(scaleBase)
        let prefixes = prefixList
        let index = min(tier.index, prefixes.count - 1)
        let divisor = pow(base, Double(index))
        return (value / divisor, prefixes[index])
    }
    
    // MARK: - Unit Helpers
    
    /// Get the scale base (1000, 1024, or 1)
    private var scaleBase: Int {
        switch config.unit {
        case .preset(let preset):
            return preset.scaleBase
        case .custom(let custom):
            return custom.useAutoScale ? custom.scaleBase.rawValue : 1
        }
    }
    
    /// Get the prefix list
    private var prefixList: [String] {
        switch config.unit {
        case .preset(let preset):
            return preset.prefixes
        case .custom(let custom):
            if !custom.useAutoScale {
                return [""]
            }
            return custom.prefixes
        }
    }
    
    /// Build the unit string with prefix
    private func unitString(prefix: String) -> String {
        switch config.unit {
        case .preset(let preset):
            return "\(prefix)\(preset.baseUnit)"
        case .custom(let custom):
            return "\(prefix)\(custom.baseUnit)"
        }
    }
    
    /// Format the number with the configured decimal places
    private func formatNumber(_ value: Double) -> String {
        // Handle special cases
        if value.isNaN {
            return "NaN"
        }
        if value.isInfinite {
            return value > 0 ? "∞" : "-∞"
        }
        
        // Use fewer decimal places for larger numbers
        let absValue = abs(value)
        let decimals: Int
        if absValue >= 100 {
            decimals = min(config.decimalPlaces, 1)
        } else if absValue >= 10 {
            decimals = min(config.decimalPlaces, 2)
        } else {
            decimals = config.decimalPlaces
        }
        
        return String(format: "%.\(decimals)f", value)
    }
    
    // MARK: - Threshold Color
    
    /// Get the color for a value based on thresholds
    func color(for rawValue: Double) -> Color {
        guard let thresholds = config.colorThresholds else {
            return .primary
        }
        
        let transformed = transform(rawValue)
        switch thresholds.level(for: transformed) {
        case .critical: return .red
        case .warning: return .orange
        case .normal: return .green
        }
    }
    
    /// Get the threshold level for a value
    func thresholdLevel(for rawValue: Double) -> ThresholdLevel {
        guard let thresholds = config.colorThresholds else {
            return .normal
        }
        return thresholds.level(for: transform(rawValue))
    }
}

// MARK: - Rate Calculator

/// Calculates rates from counter values
struct RateCalculator {
    let config: MetricConfig
    
    /// Calculate the rate between two samples
    /// - Parameters:
    ///   - currentCounter: Current counter value
    ///   - previousCounter: Previous counter value
    ///   - timeDelta: Time difference in seconds
    /// - Returns: Rate per second, or nil if invalid
    func calculateRate(
        currentCounter: UInt64,
        previousCounter: UInt64,
        timeDelta: TimeInterval
    ) -> Double? {
        guard timeDelta > 0 else { return nil }
        
        switch config.metricType {
        case .counter:
            return calculateCounterRate(
                current: currentCounter,
                previous: previousCounter,
                timeDelta: timeDelta
            )
            
        case .gauge:
            // Gauges don't need rate calculation - return the value directly
            return Double(currentCounter)
            
        case .derive:
            return calculateDeriveRate(
                current: currentCounter,
                previous: previousCounter,
                timeDelta: timeDelta
            )
        }
    }
    
    /// Calculate rate for a monotonically increasing counter (handles wraps)
    private func calculateCounterRate(
        current: UInt64,
        previous: UInt64,
        timeDelta: TimeInterval
    ) -> Double? {
        let counterDelta: UInt64
        
        if current >= previous {
            // Normal case: counter increased
            counterDelta = current - previous
        } else {
            // Counter wrapped
            let maxValue = config.counterBits.maxValue
            counterDelta = (maxValue - previous) + current + 1
            
            // Sanity check: if the "wrapped" delta is too large, it's probably
            // a counter reset or bad data, not a wrap
            let unwrappedDelta = previous - current
            if unwrappedDelta < counterDelta / 2 {
                // This looks like a reset, not a wrap
                return nil
            }
        }
        
        return Double(counterDelta) / timeDelta
    }
    
    /// Calculate rate for a derive counter (can decrease)
    private func calculateDeriveRate(
        current: UInt64,
        previous: UInt64,
        timeDelta: TimeInterval
    ) -> Double? {
        // Derive can go negative, so we use signed arithmetic
        let delta = Int64(bitPattern: current) - Int64(bitPattern: previous)
        return Double(delta) / timeDelta
    }
}

// MARK: - Convenience Extensions

extension MetricConfig {
    
    /// Create a formatter for this configuration
    var formatter: MetricFormatter {
        MetricFormatter(config: self)
    }
    
    /// Create a rate calculator for this configuration
    var rateCalculator: RateCalculator {
        RateCalculator(config: self)
    }
    
    /// Format a value using this configuration
    func format(_ value: Double) -> String {
        formatter.format(value)
    }
}

// MARK: - Graph Value Processor

/// Processes values for graph display
struct GraphValueProcessor {
    let config: MetricConfig
    
    /// Process a raw value for graph display
    /// - Parameter rawValue: Raw value (rate or gauge)
    /// - Returns: Value suitable for graph Y-axis
    func processForGraph(_ rawValue: Double) -> Double {
        let formatter = MetricFormatter(config: config)
        return formatter.transform(rawValue)
    }
    
    /// Get the Y-axis range for the graph
    /// - Parameter values: Array of raw values
    /// - Returns: (min, max) tuple for Y-axis
    func yAxisRange(for values: [Double]) -> (min: Double, max: Double) {
        let formatter = MetricFormatter(config: config)
        let transformedValues = values.map { formatter.transform($0) }
        
        let dataMin = transformedValues.min() ?? 0
        let dataMax = transformedValues.max() ?? 0
        
        // Apply configured bounds
        let min = config.graphConfig.yAxisMin ?? (config.graphConfig.showBaseline ? Swift.min(0, dataMin) : dataMin * 0.9)
        let max = config.graphConfig.yAxisMax ?? dataMax * 1.1
        
        return (min, max)
    }
    
    /// Format a Y-axis label
    func formatAxisLabel(_ value: Double) -> String {
        let formatter = MetricFormatter(config: config)
        return formatter.format(value)
    }
}

// MARK: - Preview Support

#if DEBUG
extension MetricFormatter {
    /// Preview formatter with sample values
    static var previewBits: MetricFormatter {
        MetricFormatter(config: .networkOctetsIn)
    }
    
    static var previewPercent: MetricFormatter {
        MetricFormatter(config: .cpuLoad)
    }
}
#endif
