import SwiftUI
import Charts

// MARK: - Live Graph View

/// Displays live graph for selected time series
struct LiveGraphView: View {
    let series: [TimeSeries]
    let timeWindow: TimeInterval
    
    @State private var selectedPoint: (series: TimeSeries, point: GraphPoint)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if series.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Select targets to view their graphs")
                )
            } else {
                // Chart
                chartView
                
                // Legend
                legendView
                
                // Statistics
                if series.count == 1, let single = series.first {
                    statisticsView(for: single)
                }
            }
        }
    }
    
    // MARK: - Chart View
    
    private var chartView: some View {
        Chart {
            ForEach(series) { s in
                let points = s.graphPoints(in: timeWindow)
                let config = s.metricConfig
                
                ForEach(points) { point in
                    if config.graphConfig.fillArea {
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(by: .value("Series", s.displayName))
                        .opacity(0.3)
                    }
                    
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(by: .value("Series", s.displayName))
                    .lineStyle(StrokeStyle(lineWidth: config.graphConfig.lineWidth))
                }
                
                // Show baseline if configured
                if config.graphConfig.showBaseline {
                    RuleMark(y: .value("Baseline", 0))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                if let doubleValue = value.as(Double.self) {
                    AxisValueLabel {
                        Text(formatYAxisLabel(doubleValue))
                    }
                }
            }
        }
        .chartYScale(domain: yAxisDomain)
        .chartLegend(position: .bottom)
        .frame(minHeight: 200)
    }
    
    // MARK: - Y-Axis Formatting
    
    private var yAxisDomain: ClosedRange<Double> {
        // Collect all points from all series
        var allValues: [Double] = []
        for s in series {
            let points = s.graphPoints(in: timeWindow)
            allValues.append(contentsOf: points.map { $0.value })
        }
        
        guard !allValues.isEmpty else {
            return 0...100
        }
        
        // Get configured bounds from first series (or use auto)
        let config = series.first?.metricConfig.graphConfig ?? GraphConfig()
        
        let dataMin = allValues.min() ?? 0
        let dataMax = allValues.max() ?? 100
        
        let min = config.yAxisMin ?? (config.showBaseline ? Swift.min(0, dataMin) : dataMin * 0.9)
        let max = config.yAxisMax ?? Swift.max(dataMax * 1.1, min + 1)
        
        return min...max
    }
    
    private func formatYAxisLabel(_ value: Double) -> String {
        // Use first series config for formatting
        guard let config = series.first?.metricConfig else {
            return String(format: "%.1f", value)
        }
        
        let formatter = MetricFormatter(config: config)
        return formatter.format(value)
    }
    
    // MARK: - Legend View
    
    private var legendView: some View {
        HStack(spacing: 16) {
            ForEach(series) { s in
                HStack(spacing: 4) {
                    Circle()
                        .fill(seriesColor(for: s))
                        .frame(width: 8, height: 8)
                    
                    Text(s.displayName)
                        .font(.caption)
                    
                    if let current = s.currentDisplayValue {
                        Text(current)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    private func seriesColor(for series: TimeSeries) -> Color {
        // Return color based on threshold if configured
        if let rate = series.currentRate {
            return series.metricConfig.formatter.color(for: rate)
        }
        return .blue
    }
    
    // MARK: - Statistics View
    
    private func statisticsView(for series: TimeSeries) -> some View {
        let stats = series.statistics
        let formatter = series.metricConfig.formatter
        
        return HStack(spacing: 24) {
            StatBox(title: "Current", value: formatter.format(stats.current))
            StatBox(title: "Average", value: formatter.format(stats.avg))
            StatBox(title: "Min", value: formatter.format(stats.min))
            StatBox(title: "Max", value: formatter.format(stats.max))
        }
        .padding(.top, 8)
    }
}

// MARK: - Stat Box

private struct StatBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}

// MARK: - Multi-Series Graph View

/// Graph view optimized for multiple series with different units
struct MultiSeriesGraphView: View {
    let series: [TimeSeries]
    let timeWindow: TimeInterval
    
    var body: some View {
        if hasMultipleUnits {
            // Split into separate charts by unit type
            VStack(spacing: 16) {
                ForEach(seriesByUnit, id: \.key) { unit, seriesGroup in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        LiveGraphView(series: seriesGroup, timeWindow: timeWindow)
                    }
                }
            }
        } else {
            LiveGraphView(series: series, timeWindow: timeWindow)
        }
    }
    
    private var hasMultipleUnits: Bool {
        let units = Set(series.map { $0.metricConfig.unit.displayName })
        return units.count > 1
    }
    
    private var seriesByUnit: [(key: String, value: [TimeSeries])] {
        let grouped = Dictionary(grouping: series) { $0.metricConfig.unit.displayName }
        return grouped.sorted { $0.key < $1.key }
    }
}

// MARK: - Sparkline View

/// Small inline sparkline for target row
struct SparklineView: View {
    let series: TimeSeries
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        let points = series.graphPoints(in: 60) // Last minute
        
        if points.count >= 2 {
            Chart(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(lineColor)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(width: width, height: height)
        } else {
            Rectangle()
                .fill(.quaternary)
                .frame(width: width, height: height)
        }
    }
    
    private var lineColor: Color {
        if let rate = series.currentRate {
            return series.metricConfig.formatter.color(for: rate)
        }
        return .blue
    }
}

// MARK: - Preview

#Preview {
    let store = TimeSeriesStore()
    
    return VStack {
        LiveGraphView(series: [], timeWindow: 300)
    }
    .frame(width: 600, height: 400)
    .padding()
}
