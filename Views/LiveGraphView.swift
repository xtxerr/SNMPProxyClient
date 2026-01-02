import SwiftUI
import Charts
import Combine

struct LiveGraphView: View {
    let series: [TimeSeries]
    let timeWindow: TimeInterval
    
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var now = Date()
    
    var body: some View {
        Chart {
            ForEach(series) { timeSeries in
                ForEach(timeSeries.dataPoints(lastSeconds: timeWindow)) { point in
                    if let rate = point.rate {
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Rate", rate * 8) // Convert to bits
                        )
                        .foregroundStyle(by: .value("Target", timeSeries.displayName))
                        .interpolationMethod(.monotone)
                    }
                }
            }
            
            // Show current time marker
            RuleMark(x: .value("Now", now))
                .foregroundStyle(.gray.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
        .chartXScale(domain: (now.addingTimeInterval(-timeWindow))...now)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rate = value.as(Double.self) {
                        Text(formatRate(rate))
                    }
                }
            }
        }
        .chartLegend(position: .top)
        .onReceive(timer) { _ in
            now = Date()
        }
    }
    
    private func formatRate(_ bps: Double) -> String {
        if bps >= 1_000_000_000 {
            return String(format: "%.1fG", bps / 1_000_000_000)
        } else if bps >= 1_000_000 {
            return String(format: "%.1fM", bps / 1_000_000)
        } else if bps >= 1_000 {
            return String(format: "%.1fK", bps / 1_000)
        } else {
            return String(format: "%.0f", bps)
        }
    }
}

// MARK: - Mini Sparkline for Sidebar

struct SparklineView: View {
    @ObservedObject var series: TimeSeries
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        let points = series.dataPoints(lastSeconds: 60)
        
        Chart(points) { point in
            if let rate = point.rate {
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Rate", rate)
                )
                .foregroundStyle(.blue.gradient)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(width: width, height: height)
    }
}

// MARK: - Preview

#Preview("Live Graph") {
    let store = TimeSeriesStore()
    let series = store.getOrCreate(targetID: "test", displayName: "Test Target")
    
    // Add some sample data
    for i in 0..<60 {
        var sample = Snmpproxy_V1_Sample()
        sample.targetID = "test"
        sample.timestampMs = Int64(Date().timeIntervalSince1970 * 1000) - Int64((60 - i) * 1000)
        sample.counter = UInt64(i * 1_000_000 + Int.random(in: 0...100_000))
        sample.valid = true
        series.addSample(sample)
    }
    
    return LiveGraphView(series: [series], timeWindow: 300)
        .frame(height: 300)
        .padding()
}
