import SwiftUI

struct CalibrateView: View {
    @EnvironmentObject private var dial: DialController
    @State private var turns = 3

    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            DialIndicator(
                angle: Double(dial.totalCounts) / dial.calibration.effectiveCountsPerRevolution * 360,
                measuring: dial.measurement != nil
            )
            .frame(width: 220, height: 220)

            VStack(alignment: .leading, spacing: 16) {
                Text("Counts per revolution").font(.title2).bold()
                Text("Mark a starting point on the dial's rim. Press Start, turn the dial exactly the chosen number of full turns in one direction, then press Finish. More turns gives a more accurate result.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let m = dial.measurement {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Turn the dial \(m.turns) full turn\(m.turns == 1 ? "" : "s")…").font(.headline)
                        Text("\(dial.measuredCounts) counts")
                            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        if dial.driverEnabled {
                            Text("Scrolling is paused while measuring.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("Finish") { dial.finishMeasurement() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(dial.measuredCounts == 0)
                        Button("Cancel") { dial.cancelMeasurement() }
                            .keyboardShortcut(.cancelAction)
                    }
                } else {
                    Picker("Turns", selection: $turns) {
                        ForEach([1, 3, 5, 10], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    Button("Start Measuring") { dial.startMeasurement(turns: turns) }
                        .disabled(dial.deviceName == nil)
                }

                Divider()

                HStack {
                    Text("Counts per revolution:")
                    TextField("", value: $dial.calibration.countsPerRevolution, format: .number.precision(.fractionLength(0...1)))
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                    if !dial.calibration.isCalibrated {
                        Label("Not calibrated — assuming \(Int(Calibration.fallbackCountsPerRevolution))",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Text("Check: after calibrating, one physical turn of the dial should spin the indicator exactly once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
    }
}

private struct DialIndicator: View {
    let angle: Double
    let measuring: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.quaternary.opacity(0.6))
            Circle()
                .strokeBorder(measuring ? Color.accentColor : .secondary.opacity(0.5), lineWidth: 6)
            ForEach(0..<24) { i in
                Rectangle()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 1.5, height: i % 6 == 0 ? 14 : 7)
                    .offset(y: -96)
                    .rotationEffect(.degrees(Double(i) * 15))
            }
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 6, height: 80)
                .offset(y: -40)
                .rotationEffect(.degrees(-angle))
            Circle().fill(Color.accentColor).frame(width: 14, height: 14)
        }
        .animation(.linear(duration: 0.05), value: angle)
    }
}
