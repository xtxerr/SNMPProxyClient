import Foundation
import Combine
import SwiftProtobuf

/// A single data point with calculated rate
struct DataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let rawValue: UInt64
    let rate: Double?      // Calculated rate (e.g., bits/sec)
    let isValid: Bool
    let error: String?
    let pollMs: Int32
}

/// Time series data for a single target
class TimeSeries: ObservableObject, Identifiable {
    let id: String
    let targetID: String
    var displayName: String
    
    @Published private(set) var dataPoints: [DataPoint] = []
    @Published private(set) var currentRate: Double?
    @Published private(set) var maxRate: Double = 0
    @Published private(set) var minRate: Double = 0
    
    private let maxDataPoints: Int
    private var lastCounter: UInt64?
    private var lastTimestamp: Date?
    
    init(targetID: String, displayName: String, maxDataPoints: Int = 3600) {
        self.id = targetID
        self.targetID = targetID
        self.displayName = displayName
        self.maxDataPoints = maxDataPoints
    }
    
    /// Add a sample and calculate rate
    func addSample(_ sample: Snmpproxy_V1_Sample) {
        let timestamp = Date(timeIntervalSince1970: Double(sample.timestampMs) / 1000.0)
        
        var rate: Double? = nil
        
        if sample.valid, sample.text.isEmpty {
            // Counter value - calculate rate
            if let lastCounter = lastCounter, let lastTimestamp = lastTimestamp {
                let timeDelta = timestamp.timeIntervalSince(lastTimestamp)
                if timeDelta > 0 {
                    let counterDelta: UInt64
                    
                    // Handle counter wrap (64-bit)
                    if sample.counter >= lastCounter {
                        counterDelta = sample.counter - lastCounter
                    } else {
                        // Counter wrapped
                        counterDelta = (UInt64.max - lastCounter) + sample.counter + 1
                    }
                    
                    rate = Double(counterDelta) / timeDelta
                    
                    // Update min/max
                    if let r = rate {
                        currentRate = r
                        if r > maxRate { maxRate = r }
                        if minRate == 0 || r < minRate { minRate = r }
                    }
                }
            }
            
            lastCounter = sample.counter
            lastTimestamp = timestamp
        }
        
        let dataPoint = DataPoint(
            timestamp: timestamp,
            rawValue: sample.counter,
            rate: rate,
            isValid: sample.valid,
            error: sample.valid ? nil : sample.error,
            pollMs: sample.pollMs
        )
        
        dataPoints.append(dataPoint)
        
        // Trim old data
        if dataPoints.count > maxDataPoints {
            dataPoints.removeFirst(dataPoints.count - maxDataPoints)
        }
    }
    
    /// Get data points for a specific time window
    func dataPoints(lastSeconds: TimeInterval) -> [DataPoint] {
        let cutoff = Date().addingTimeInterval(-lastSeconds)
        return dataPoints.filter { $0.timestamp >= cutoff }
    }
    
    /// Reset statistics
    func reset() {
        dataPoints.removeAll()
        lastCounter = nil
        lastTimestamp = nil
        currentRate = nil
        maxRate = 0
        minRate = 0
    }
}

/// Store for managing multiple time series
@MainActor
class TimeSeriesStore: ObservableObject {
    @Published private(set) var series: [String: TimeSeries] = [:]
    @Published var selectedSeriesIDs: Set<String> = []
    
    /// Get or create a time series for a target
    func getOrCreate(targetID: String, displayName: String) -> TimeSeries {
        if let existing = series[targetID] {
            return existing
        }
        
        let newSeries = TimeSeries(targetID: targetID, displayName: displayName)
        series[targetID] = newSeries
        return newSeries
    }
    
    /// Add a sample to the appropriate series
    func addSample(_ sample: Snmpproxy_V1_Sample) {
        guard let timeSeries = series[sample.targetID] else { return }
        timeSeries.addSample(sample)
    }
    
    /// Remove a series
    func remove(targetID: String) {
        series.removeValue(forKey: targetID)
        selectedSeriesIDs.remove(targetID)
    }
    
    /// Get selected series for graphing
    var selectedSeries: [TimeSeries] {
        selectedSeriesIDs.compactMap { series[$0] }
    }
}
