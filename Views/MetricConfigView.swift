import SwiftUI

// MARK: - Metric Configuration View

/// Full metric configuration editor
struct MetricConfigView: View {
    @Binding var config: MetricConfig
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPreset: Int? = nil
    @State private var showAdvanced = false
    @State private var previewValue: String = "1234567890"
    
    var body: some View {
        Form {
            // ─────────────────────────────────────────────────────────────────
            // Preset Selection
            // ─────────────────────────────────────────────────────────────────
            Section("Quick Setup") {
                Picker("Template", selection: $selectedPreset) {
                    Text("Custom").tag(nil as Int?)
                    ForEach(Array(MetricConfig.allTemplates.enumerated()), id: \.offset) { index, template in
                        Text(template.name).tag(index as Int?)
                    }
                }
                .onChange(of: selectedPreset) { _, newValue in
                    if let index = newValue {
                        config = MetricConfig.allTemplates[index].config
                    }
                }
            }
            
            // ─────────────────────────────────────────────────────────────────
            // Data Type
            // ─────────────────────────────────────────────────────────────────
            Section("Data Type") {
                Picker("Metric Type", selection: $config.metricType) {
                    ForEach(MetricType.allCases) { type in
                        VStack(alignment: .leading) {
                            Text(type.displayName)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                
                Text(config.metricType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if config.metricType == .counter || config.metricType == .derive {
                    Picker("Counter Size", selection: $config.counterBits) {
                        ForEach(CounterBits.allCases) { bits in
                            Text(bits.displayName).tag(bits)
                        }
                    }
                }
            }
            
            // ─────────────────────────────────────────────────────────────────
            // Transformation
            // ─────────────────────────────────────────────────────────────────
            Section {
                HStack {
                    Text("Multiplier (×)")
                    Spacer()
                    TextField("1.0", value: $config.multiplier, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                
                HStack {
                    Text("Divisor (÷)")
                    Spacer()
                    TextField("1.0", value: $config.divisor, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                
                HStack {
                    Text("Offset (+)")
                    Spacer()
                    TextField("0.0", value: $config.offset, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                
                Text("Formula: value × \(formatNumber(config.multiplier)) ÷ \(formatNumber(config.divisor)) + \(formatNumber(config.offset))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Transformation")
            } footer: {
                Text("Example: For octets→bits, set multiplier to 8")
            }
            
            // ─────────────────────────────────────────────────────────────────
            // Unit & Scaling
            // ─────────────────────────────────────────────────────────────────
            Section("Unit & Scaling") {
                UnitConfigPicker(unit: $config.unit)
                
                Picker("Force Scale", selection: $config.forceScaleTier) {
                    Text("Auto").tag(nil as ScaleTier?)
                    ForEach(ScaleTier.allCases) { tier in
                        Text(tier.displayName).tag(tier as ScaleTier?)
                    }
                }
            }
            
            // ─────────────────────────────────────────────────────────────────
            // Display Options
            // ─────────────────────────────────────────────────────────────────
            Section("Display") {
                Stepper("Decimal Places: \(config.decimalPlaces)", value: $config.decimalPlaces, in: 0...6)
                
                Toggle("Show + for Positive", isOn: $config.showPlusSign)
                
                TextField("Display Name", text: Binding(
                    get: { config.displayName ?? "" },
                    set: { config.displayName = $0.isEmpty ? nil : $0 }
                ))
                
                TextField("Description", text: Binding(
                    get: { config.description ?? "" },
                    set: { config.description = $0.isEmpty ? nil : $0 }
                ))
            }
            
            // ─────────────────────────────────────────────────────────────────
            // Thresholds
            // ─────────────────────────────────────────────────────────────────
            Section("Color Thresholds") {
                Toggle("Enable Thresholds", isOn: Binding(
                    get: { config.colorThresholds != nil },
                    set: { enabled in
                        config.colorThresholds = enabled ? ColorThresholds() : nil
                    }
                ))
                
                if config.colorThresholds != nil {
                    HStack {
                        Circle().fill(.orange).frame(width: 12, height: 12)
                        Text("Warning")
                        Spacer()
                        TextField("Value", value: Binding(
                            get: { config.colorThresholds?.warning ?? 0 },
                            set: { config.colorThresholds?.warning = $0 > 0 ? $0 : nil }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Circle().fill(.red).frame(width: 12, height: 12)
                        Text("Critical")
                        Spacer()
                        TextField("Value", value: Binding(
                            get: { config.colorThresholds?.critical ?? 0 },
                            set: { config.colorThresholds?.critical = $0 > 0 ? $0 : nil }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                    }
                    
                    Toggle("Inverted (low = bad)", isOn: Binding(
                        get: { config.colorThresholds?.inverted ?? false },
                        set: { config.colorThresholds?.inverted = $0 }
                    ))
                    
                    Text("Inverted: warning when below threshold (e.g., free disk space)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // ─────────────────────────────────────────────────────────────────
            // Graph Options
            // ─────────────────────────────────────────────────────────────────
            Section("Graph") {
                HStack {
                    Text("Y-Axis Min")
                    Spacer()
                    TextField("Auto", value: $config.graphConfig.yAxisMin, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                
                HStack {
                    Text("Y-Axis Max")
                    Spacer()
                    TextField("Auto", value: $config.graphConfig.yAxisMax, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                
                Toggle("Show Zero Baseline", isOn: $config.graphConfig.showBaseline)
                Toggle("Logarithmic Scale", isOn: $config.graphConfig.logarithmic)
                Toggle("Fill Area", isOn: $config.graphConfig.fillArea)
            }
            
            // ─────────────────────────────────────────────────────────────────
            // Preview
            // ─────────────────────────────────────────────────────────────────
            Section("Preview") {
                HStack {
                    Text("Sample Value:")
                    TextField("Value", text: $previewValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
                
                if let value = Double(previewValue) {
                    let formatter = MetricFormatter(config: config)
                    
                    HStack {
                        Text("Displayed as:")
                        Spacer()
                        Text(formatter.format(value))
                            .font(.headline)
                            .foregroundStyle(formatter.color(for: value))
                    }
                    
                    HStack {
                        Text("Transformed:")
                        Spacer()
                        Text(String(format: "%.4f", formatter.transform(value)))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Metric Configuration")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value == Double(Int(value)) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

// MARK: - Unit Config Picker

struct UnitConfigPicker: View {
    @Binding var unit: UnitConfig
    
    @State private var isCustom: Bool = false
    @State private var customBaseUnit: String = ""
    @State private var customAutoScale: Bool = true
    @State private var customScaleBase: ScaleBase = .decimal
    
    var body: some View {
        Group {
            Toggle("Custom Unit", isOn: $isCustom)
                .onChange(of: isCustom) { _, newValue in
                    if newValue {
                        // Switch to custom
                        unit = .custom(CustomUnit(
                            baseUnit: customBaseUnit.isEmpty ? "units" : customBaseUnit,
                            useAutoScale: customAutoScale,
                            scaleBase: customScaleBase
                        ))
                    } else {
                        // Switch to preset
                        unit = .preset(.raw)
                    }
                }
            
            if isCustom {
                TextField("Unit Name", text: $customBaseUnit)
                    .onChange(of: customBaseUnit) { _, newValue in
                        if case .custom(var custom) = unit {
                            custom.baseUnit = newValue
                            unit = .custom(custom)
                        }
                    }
                
                Toggle("Auto-Scale", isOn: $customAutoScale)
                    .onChange(of: customAutoScale) { _, newValue in
                        if case .custom(var custom) = unit {
                            custom.useAutoScale = newValue
                            unit = .custom(custom)
                        }
                    }
                
                if customAutoScale {
                    Picker("Scale Base", selection: $customScaleBase) {
                        ForEach(ScaleBase.allCases) { base in
                            Text(base.displayName).tag(base)
                        }
                    }
                    .onChange(of: customScaleBase) { _, newValue in
                        if case .custom(var custom) = unit {
                            custom.scaleBase = newValue
                            unit = .custom(custom)
                        }
                    }
                }
            } else {
                Picker("Unit", selection: Binding(
                    get: {
                        if case .preset(let preset) = unit {
                            return preset
                        }
                        return .raw
                    },
                    set: { unit = .preset($0) }
                )) {
                    ForEach(PresetUnit.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
            }
        }
        .onAppear {
            // Initialize state from current unit
            if case .custom(let custom) = unit {
                isCustom = true
                customBaseUnit = custom.baseUnit
                customAutoScale = custom.useAutoScale
                customScaleBase = custom.scaleBase
            }
        }
    }
}

// MARK: - Compact Metric Config View

/// Compact inline metric configuration for AddTargetView
struct CompactMetricConfigView: View {
    @Binding var config: MetricConfig
    @State private var showFullConfig = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Quick preset picker
            Picker("Type", selection: Binding(
                get: { presetIndex(for: config) },
                set: { index in
                    if let idx = index, idx < MetricConfig.allTemplates.count {
                        config = MetricConfig.allTemplates[idx].config
                    }
                }
            )) {
                Text("Custom").tag(nil as Int?)
                ForEach(Array(MetricConfig.allTemplates.enumerated()), id: \.offset) { index, template in
                    Text(template.name).tag(index as Int?)
                }
            }
            
            // Quick type toggle
            HStack {
                Picker("", selection: $config.metricType) {
                    Text("Counter").tag(MetricType.counter)
                    Text("Gauge").tag(MetricType.gauge)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                Spacer()
                
                Button("Advanced...") {
                    showFullConfig = true
                }
                .buttonStyle(.link)
            }
            
            // Preview
            HStack {
                Text("Preview:")
                    .foregroundStyle(.secondary)
                Text(config.formatter.format(1_000_000))
                    .font(.caption.monospaced())
            }
        }
        .sheet(isPresented: $showFullConfig) {
            NavigationStack {
                MetricConfigView(config: $config)
            }
            .frame(minWidth: 500, minHeight: 600)
        }
    }
    
    private func presetIndex(for config: MetricConfig) -> Int? {
        // Try to find a matching preset
        for (index, template) in MetricConfig.allTemplates.enumerated() {
            if template.config.metricType == config.metricType &&
               template.config.unit == config.unit &&
               template.config.multiplier == config.multiplier {
                return index
            }
        }
        return nil
    }
}

// MARK: - Metric Badge View

/// Small badge showing current metric type
struct MetricTypeBadge: View {
    let config: MetricConfig
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(config.metricType.displayName)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor.opacity(0.2))
        .foregroundStyle(backgroundColor)
        .clipShape(Capsule())
    }
    
    private var iconName: String {
        switch config.metricType {
        case .counter: return "arrow.up.right"
        case .gauge: return "gauge.medium"
        case .derive: return "arrow.up.arrow.down"
        }
    }
    
    private var backgroundColor: Color {
        switch config.metricType {
        case .counter: return .blue
        case .gauge: return .green
        case .derive: return .orange
        }
    }
}

// MARK: - Preview

#Preview("Full Config") {
    NavigationStack {
        MetricConfigView(config: .constant(.networkOctetsIn))
    }
    .frame(width: 500, height: 700)
}

#Preview("Compact Config") {
    Form {
        Section("Metric") {
            CompactMetricConfigView(config: .constant(.cpuLoad))
        }
    }
    .frame(width: 400, height: 200)
}
