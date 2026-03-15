import SwiftUI

struct ControlPanel: View {
    @Environment(AppState.self) private var state
    @Environment(DSConnection.self) private var connection

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {

            // MARK: Enable / Disable
            VStack(spacing: 8) {
                Button {
                    state.isEnabled = true
                } label: {
                    Text("Enable")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!canEnable)

                Button {
                    state.isEnabled = false
                } label: {
                    Text("Disable")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
                .disabled(!state.isEnabled)
            }
            .padding()

            Divider()

            // MARK: Mode
            VStack(alignment: .leading, spacing: 4) {
                Text("Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                ForEach(RobotMode.allCases) { mode in
                    Button {
                        state.mode = mode
                        state.isEnabled = false
                    } label: {
                        HStack {
                            Image(systemName: state.mode == mode ? "circle.fill" : "circle")
                                .foregroundStyle(state.mode == mode ? Color.accentColor : Color.secondary)
                            Text(mode.label)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)

            Divider()

            // MARK: Alliance station
            VStack(alignment: .leading, spacing: 4) {
                Text("Alliance Station")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Picker("", selection: $state.allianceStation) {
                    ForEach(AllianceStation.allCases) { station in
                        Text(station.label).tag(station)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // MARK: Robot actions
            VStack(spacing: 8) {
                Button {
                    state.pendingReboot = true
                } label: {
                    Label("Reboot RoboRIO", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!state.robotCommsOK)

                Button {
                    state.pendingRestartCode = true
                } label: {
                    Label("Restart Code", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!state.robotCommsOK)
            }
            .padding()

            Spacer()

            Divider()

            // MARK: E-STOP
            Button {
                state.isEStopped = true
                state.isEnabled  = false
            } label: {
                Text("E-STOP")
                    .font(.system(.title2, weight: .black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(state.isEStopped ? Color.red.opacity(0.6) : Color.red)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding()
            .help("Emergency Stop — robot cannot be re-enabled until connection is restarted")
        }
    }

    private var canEnable: Bool {
        state.robotCommsOK && !state.isEStopped
    }
}
