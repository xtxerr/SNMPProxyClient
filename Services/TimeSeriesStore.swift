import Foundation
import SwiftUI
import Combine

// MARK: - Time Series Store

/// Manages all time series data for monitored targets
@MainActor
class TimeSeriesStore: ObservableObject {
    /// All time series, keyed by target ID
    @Published var series: [String: TimeSeries] = [:]
    
    /// Currently selected series IDs for graph display
    @Published var selectedSeriesIDs: Set<String> = []
    
    /// Get selected series as array
    var selectedSeries: [TimeSeries] {
        selectedSeriesIDs.compactMap { series[$0] }
    }
    
    // MARK: - Series Management
    
    /// Add a sample from the server (proto message)
    func addSample(_ protoSample: Snmpproxy_V1_Sample) {
        guard let existingSeries = series[protoSample.targetID] else {
            // No series configured for this target - ignore
            // The series should be created via configureSeries() first
            return
        }
        
        let sample = SNMPSample(
            targetID: protoSample.targetID,
            name: existingSeries.displayName,
            oid: existingSeries.oid,
            counter: protoSample.counter,
            timestamp: Date(timeIntervalSince1970: TimeInterval(protoSample.timestampMs) / 1000.0)
        )
        
        existingSeries.addSample(sample)
    }
    
    /// Add a sample directly (for testing or internal use)
    func addSample(_ sample: SNMPSample) {
        if let existingSeries = series[sample.targetID] {
            existingSeries.addSample(sample)
        } else {
            // Create new series with default config (try OID auto-detection)
            let config = MetricConfig.preset(for: sample.oid) ?? .genericCounter
            let newSeries = TimeSeries(
                targetID: sample.targetID,
                displayName: sample.name ?? sample.targetID,
                oid: sample.oid,
                metricConfig: config
            )
            newSeries.addSample(sample)
            series[sample.targetID] = newSeries
        }
    }
    
    /// Create or update a series with explicit configuration
    func configureSeries(
        targetID: String,
        displayName: String,
        oid: String,
        config: MetricConfig
    ) {
        if let existingSeries = series[targetID] {
            existingSeries.displayName = displayName
            existingSeries.metricConfig = config
        } else {
            let newSeries = TimeSeries(
                targetID: targetID,
                displayName: displayName,
                oid: oid,
                metricConfig: config
            )
            series[targetID] = newSeries
        }
    }
    
    /// Update metric configuration for a series
    func updateConfig(targetID: String, config: MetricConfig) {
        series[targetID]?.metricConfig = config
        // Recalculate all display values
        series[targetID]?.recalculateDisplayValues()
    }
    
    /// Remove a series
    func remove(targetID: String) {
        series.removeValue(forKey: targetID)
        selectedSeriesIDs.remove(targetID)
    }
    
    /// Clear all series
    func clear() {
        series.removeAll()
        selectedSeriesIDs.removeAll()
    }
}

// MARK: - Time Series

/// A single time series with samples and configuration
class TimeSeries: ObservableObject, Identifiable {
    let id: String
    let targetID: String
    let oid: String
    
    @Published var displayName: String
    @Published var metricConfig: MetricConfig
    @Published private(set) var samples: [ProcessedSample] = []
    @Published private(set) var currentRate: Double?
    @Published private(set) var currentDisplayValue: String?
    
    /// Maximum samples to keep in memory
    var maxSamples: Int = 3600
    
    init(targetID: String, displayName: String, oid: String, metricConfig: MetricConfig) {
        self.id = targetID
        self.targetID = targetID
        self.displayName = displayName
        self.oid = oid
        self.metricConfig = metricConfig
    }
    
    // MARK: - Sample Processing
    
    func addSample(_ sample: SNMPSample) {
        let processed = processSample(sample)
        
        samples.append(processed)
        
        // Trim old samples
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        
        // Update current values
        if let rate = processed.rate {
            currentRate = rate
            currentDisplayValue = metricConfig.formatter.format(rate)
        }
    }
    
    private func processSample(_ sample: SNMPSample) -> ProcessedSample {
        var rate: Double? = nil
        
        // Calculate rate if we have a previous sample
        if let previousSample = samples.last {
            let timeDelta = sample.timestamp.timeIntervalSince(previousSample.timestamp)
            
            if timeDelta > 0 {
                let calculator = metricConfig.rateCalculator
                rate = calculator.calculateRate(
                    currentCounter: sample.counter,
                    previousCounter: previousSample.rawCounter,
                    timeDelta: timeDelta
                )
            }
        }
        
        return ProcessedSample(
            timestamp: sample.timestamp,
            rawCounter: sample.counter,
            rate: rate
        )
    }
    
    /// Recalculate all display values after config change
    func recalculateDisplayValues() {
        guard samples.count > 1 else { return }
        
        var newSamples: [ProcessedSample] = []
        let calculator = metricConfig.rateCalculator
        
        for i in 0..<samples.count {
            var sample = samples[i]
            
            if i > 0 {
                let previous = samples[i - 1]
                let timeDelta = sample.timestamp.timeIntervalSince(previous.timestamp)
                
                if timeDelta > 0 {
                    sample.rate = calculator.calculateRate(
                        currentCounter: sample.rawCounter,
                        previousCounter: previous.rawCounter,
                        timeDelta: timeDelta
                    )
                }
            }
            
            newSamples.append(sample)
        }
        
        samples = newSamples
        
        // Update current display
        if let lastRate = samples.last?.rate {
            currentRate = lastRate
            currentDisplayValue = metricConfig.formatter.format(lastRate)
        }
    }
    
    // MARK: - Data Access
    
    /// Get samples within a time window
    func samples(in timeWindow: TimeInterval) -> [ProcessedSample] {
        let cutoff = Date().addingTimeInterval(-timeWindow)
        return samples.filter { $0.timestamp >= cutoff }
    }
    
    /// Get graph points for a time window
    func graphPoints(in timeWindow: TimeInterval) -> [GraphPoint] {
        let windowSamples = samples(in: timeWindow)
        let processor = GraphValueProcessor(config: metricConfig)
        
        return windowSamples.compactMap { sample in
            guard let rate = sample.rate else { return nil }
            return GraphPoint(
                timestamp: sample.timestamp,
                value: processor.processForGraph(rate)
            )
        }
    }
    
    /// Get statistics for the current data
    var statistics: SeriesStatistics {
        let rates = samples.compactMap { $0.rate }
        guard !rates.isEmpty else {
            return SeriesStatistics()
        }
        
        let sum = rates.reduce(0, +)
        let avg = sum / Double(rates.count)
        
        return SeriesStatistics(
            min: rates.min() ?? 0,
            max: rates.max() ?? 0,
            avg: avg,
            current: rates.last ?? 0,
            count: rates.count
        )
    }
}

// MARK: - Supporting Types

/// Raw SNMP sample from the server
struct SNMPSample {
    let targetID: String
    let name: String?
    let oid: String
    let counter: UInt64
    let timestamp: Date
}

/// Processed sample with calculated rate
struct ProcessedSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let rawCounter: UInt64
    var rate: Double?
}

/// Point for graph display
struct GraphPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

/// Statistics for a series
struct SeriesStatistics {
    var min: Double = 0
    var max: Double = 0
    var avg: Double = 0
    var current: Double = 0
    var count: Int = 0
}

// MARK: - Identifiable Conformance

extension TimeSeries: Hashable {
    static func == (lhs: TimeSeries, rhs: TimeSeries) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
