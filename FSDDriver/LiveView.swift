import Charts
import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var dial: DialController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Spin the dial slowly, then quickly. If **counts / report** rises with speed, the hardware is reporting speed correctly and the mapping on the Response tab controls how it scrolls.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                StatTile(title: "Speed", value: String(format: "%.2f", dial.revsPerSecond), unit: "rev/s")
                StatTile(title: "Gain", value: String(format: "%.2f×", dial.currentGain), unit: "acceleration")
                StatTile(title: "Reports", value: String(format: "%.0f", dial.reportsPerSecond), unit: "per second")
                StatTile(title: "Counts / report", value: String(format: "%.1f", dial.countsPerReport),
                         unit: "max \(dial.maxCountsPerReport)")
                StatTile(title: "Total", value: "\(dial.totalCounts)", unit: "counts")
            }

            HStack(spacing: 14) {
                LiveChart(title: "Rotation speed (rev/s)", samples: dial.history, value: \.revsPerSecond)
                LiveChart(title: "Scroll output (px/s)", samples: dial.history, value: \.pixelsPerSecond)
            }
            .frame(height: 170)

            Text("Raw HID reports").font(.headline)
            ScrollView {
                Text(dial.rawLog.isEmpty ? "Waiting for input…" : dial.rawLog.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding()
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .rounded).monospacedDigit()).bold()
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LiveChart: View {
    let title: String
    let samples: [VelocitySample]
    let value: KeyPath<VelocitySample, Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Chart(samples) { s in
                LineMark(x: .value("Time", s.time), y: .value(title, s[keyPath: value]))
                    .interpolationMethod(.monotone)
            }
            .chartXScale(domain: -DialController.historySeconds...0)
            .chartXAxis {
                AxisMarks(values: .stride(by: 1)) { v in
                    AxisGridLine()
                    AxisValueLabel { Text("\(v.as(Double.self).map { Int($0) } ?? 0)s") }
                }
            }
        }
    }
}
