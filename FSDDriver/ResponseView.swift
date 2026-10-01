import Charts
import SwiftUI

struct ResponseView: View {
    @EnvironmentObject private var dial: DialController

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Form {
                Section("Base speed") {
                    SliderRow(title: "Pixels per revolution", value: $dial.calibration.pixelsPerRevolution,
                              range: 100...6000, step: 50, format: "%.0f px")
                }
                Section("Acceleration") {
                    SliderRow(title: "Starts at", value: $dial.calibration.accelThreshold,
                              range: 0...3, step: 0.05, format: "%.2f rev/s")
                    SliderRow(title: "Strength", value: $dial.calibration.accelStrength,
                              range: 0...5, step: 0.05, format: "%.2f")
                    SliderRow(title: "Curve", value: $dial.calibration.accelExponent,
                              range: 0.5...3, step: 0.05, format: "^%.2f")
                    SliderRow(title: "Max gain", value: $dial.calibration.maxGain,
                              range: 1...20, step: 0.5, format: "%.1f×")
                    SliderRow(title: "Smoothing", value: $dial.calibration.smoothing,
                              range: 0.01...0.2, step: 0.005, format: "%.3f s")
                }
                Section("Direction & buttons") {
                    Toggle("Reverse vertical", isOn: $dial.calibration.reverseVertical)
                    Toggle("Reverse horizontal", isOn: $dial.calibration.reverseHorizontal)
                    Toggle("Forward buttons & pointer motion", isOn: $dial.calibration.forwardPointer)
                }
                Button("Reset response to defaults") {
                    let cpr = dial.calibration.countsPerRevolution
                    dial.calibration = Calibration()
                    dial.calibration.countsPerRevolution = cpr
                }
            }
            .formStyle(.grouped)
            .frame(width: 400)

            VStack(alignment: .leading, spacing: 12) {
                Text("Output vs. rotation speed").font(.headline)
                ResponseCurve(calibration: dial.calibration, current: dial.revsPerSecond)
                    .frame(height: 220)
                Text("Test area — enable the Driver and scroll here").font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(1...400, id: \.self) { i in
                            Text("Line \(i)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(i % 10 == 0 ? .primary : .secondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

private struct ResponseCurve: View {
    let calibration: Calibration
    let current: Double

    private struct Point: Identifiable {
        let id: Int
        let rps: Double
        let pps: Double
        let series: String
    }

    private var points: [Point] {
        let speeds = stride(from: 0.0, through: 4.0, by: 0.05).map { $0 }
        let curve = speeds.enumerated().map { i, v in
            Point(id: i, rps: v, pps: calibration.pixelsPerSecond(atRevsPerSecond: v), series: "With acceleration")
        }
        let linear = speeds.enumerated().map { i, v in
            Point(id: 1000 + i, rps: v, pps: v * calibration.pixelsPerRevolution, series: "Linear")
        }
        return curve + linear
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("rev/s", p.rps), y: .value("px/s", p.pps))
                    .foregroundStyle(by: .value("Series", p.series))
                    .lineStyle(p.series == "Linear" ? StrokeStyle(lineWidth: 1, dash: [4, 3]) : StrokeStyle(lineWidth: 2))
            }
            if current > 0 {
                RuleMark(x: .value("Now", min(current, 4)))
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .chartForegroundStyleScale(["With acceleration": Color.accentColor, "Linear": Color.secondary])
        .chartXAxisLabel("Rotation speed (rev/s)")
        .chartYAxisLabel("Scroll speed (px/s)")
    }
}
