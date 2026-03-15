import SwiftUI

struct StatusIndicators: View {
    let robotComms: Bool
    let robotCode:  Bool
    let joysticks:  Bool

    var body: some View {
        HStack(spacing: 24) {
            indicator(label: "Robot Comms", ok: robotComms)
            indicator(label: "Robot Code",  ok: robotCode)
            indicator(label: "Joysticks",   ok: joysticks)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func indicator(label: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 12, height: 12)
                .shadow(color: ok ? .green.opacity(0.6) : .red.opacity(0.4), radius: 4)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
