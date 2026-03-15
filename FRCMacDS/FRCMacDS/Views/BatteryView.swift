import SwiftUI

struct BatteryView: View {
    let voltage: Double
    let history: [Double]

    private var color: Color {
        if voltage >= 12.0 { .green }
        else if voltage >= 10.5 { .yellow }
        else { .red }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(color)
                .font(.caption)
            Text(String(format: "%.2f V", voltage))
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(color)
        }
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
