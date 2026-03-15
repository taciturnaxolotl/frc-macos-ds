import SwiftUI
import Charts

struct TelemetryView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Battery chart
            VStack(alignment: .leading, spacing: 8) {
                Label("Robot Battery", systemImage: "bolt.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if state.batteryHistory.count > 1 {
                    Chart {
                        ForEach(Array(state.batteryHistory.suffix(300).enumerated()), id: \.offset) { i, v in
                            LineMark(x: .value("t", i), y: .value("V", v))
                                .foregroundStyle(batteryColor(v))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [8, 10, 12, 14]) {
                            AxisGridLine()
                            AxisValueLabel()
                        }
                    }
                    .chartYScale(domain: 8...14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Waiting for data…")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Text(String(format: "%.2f V", state.batteryVoltage))
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(batteryColor(state.batteryVoltage))
            }
            .padding()
            .frame(width: 240)

            Divider()

            // Robot metrics
            VStack(alignment: .leading, spacing: 12) {
                MetricBar(label: "CPU",  value: state.cpuUsage,       color: .blue)
                MetricBar(label: "RAM",  value: state.ramUsage,       color: .purple)
                MetricBar(label: "Disk", value: state.diskUsage,      color: .orange)
                MetricBar(label: "CAN",  value: state.canUtilization, color: .teal)

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                    GridRow {
                        Text("Trip Time").foregroundStyle(.secondary).font(.callout)
                        Text("\(state.tripTimeMs) ms").monospacedDigit().font(.callout)
                    }
                    GridRow {
                        Text("Packet Loss").foregroundStyle(.secondary).font(.callout)
                        Text(String(format: "%.1f%%", state.packetLoss)).monospacedDigit().font(.callout)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private func batteryColor(_ v: Double) -> Color {
        v >= 12 ? .green : v >= 10.5 ? .yellow : .red
    }
}

private struct MetricBar: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", value)).font(.callout.monospacedDigit())
            }
            ProgressView(value: value, total: 100).tint(color)
        }
    }
}
