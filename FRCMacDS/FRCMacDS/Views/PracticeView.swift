import SwiftUI

struct PracticeView: View {
    @State private var autoSecs:    Double = 15
    @State private var teleopSecs:  Double = 135
    @State private var endgameSecs: Double = 20

    @State private var timeRemaining: Double = 0
    @State private var phase: Phase = .idle
    @State private var timer: Timer? = nil

    enum Phase: String {
        case idle     = "Ready"
        case auto     = "Autonomous"
        case teleop   = "Teleoperated"
        case endgame  = "Endgame"
        case done     = "Match Over"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Phase indicator
            Text(phase.rawValue)
                .font(.largeTitle.bold())
                .foregroundStyle(phaseColor)
                .animation(.easeInOut, value: phase)

            // Countdown
            Text(timeString(timeRemaining))
                .font(.system(size: 72, weight: .black, design: .monospaced))
                .foregroundStyle(phaseColor)
                .contentTransition(.numericText(countsDown: true))

            // Config sliders (only when idle)
            if phase == .idle || phase == .done {
                VStack(spacing: 12) {
                    TimerSlider(label: "Autonomous",  value: $autoSecs,    range: 0...30)
                    TimerSlider(label: "Teleoperated", value: $teleopSecs, range: 0...180)
                    TimerSlider(label: "Endgame",      value: $endgameSecs, range: 0...60)
                }
                .padding(.horizontal, 60)
            }

            // Controls
            HStack(spacing: 16) {
                if phase == .idle || phase == .done {
                    Button("Start Match") { startMatch() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Stop") { stopMatch() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var phaseColor: Color {
        switch phase {
        case .auto:    .blue
        case .teleop:  .green
        case .endgame: .orange
        case .done:    .secondary
        case .idle:    .secondary
        }
    }

    private func timeString(_ t: Double) -> String {
        let s = max(0, Int(t.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func startMatch() {
        phase         = .auto
        timeRemaining = autoSecs
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            tick()
        }
    }

    private func stopMatch() {
        timer?.invalidate()
        timer = nil
        phase = .idle
    }

    private func tick() {
        timeRemaining -= 0.1
        if timeRemaining <= 0 {
            advance()
        }
    }

    private func advance() {
        switch phase {
        case .auto:
            phase         = teleopSecs > endgameSecs ? .teleop : .endgame
            timeRemaining = teleopSecs
        case .teleop:
            if timeRemaining <= endgameSecs && phase == .teleop {
                phase = .endgame
            } else {
                phase         = .done
                timer?.invalidate()
                timer = nil
            }
        case .endgame:
            phase = .done
            timer?.invalidate()
            timer = nil
        default:
            break
        }
    }
}

private struct TimerSlider: View {
    let label:  String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .trailing)
                .font(.callout)
            Slider(value: $value, in: range, step: 5)
            Text("\(Int(value))s")
                .frame(width: 36)
                .font(.callout.monospacedDigit())
        }
    }
}
