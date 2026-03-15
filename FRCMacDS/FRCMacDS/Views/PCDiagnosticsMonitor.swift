import Foundation
import IOKit
import Darwin
import Observation

@Observable
final class PCDiagnosticsMonitor {
    var batteryPct:  Double = 0   // 0–100, or –1 if no battery
    var isCharging:  Bool   = false
    var cpuUsage:    Double = 0   // 0–100 %

    private var prevTicks: CPUTicks?
    private var timer: Timer?

    func start() {
        updateBattery()
        prevTicks = CPUTicks.snapshot()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateBattery()
            self?.updateCPU()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Battery (via IORegistry AppleSmartBattery)

    private func updateBattery() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else {
            batteryPct = -1
            isCharging = false
            return
        }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: AnyObject] else {
            batteryPct = -1
            return
        }

        let current = dict["CurrentCapacity"] as? Int ?? 0
        let maximum = dict["MaxCapacity"]     as? Int ?? 100
        batteryPct  = maximum > 0 ? Double(current) / Double(maximum) * 100.0 : -1
        isCharging  = dict["IsCharging"]      as? Bool ?? false
    }

    // MARK: - CPU (two-snapshot Mach host_statistics)

    private func updateCPU() {
        let current = CPUTicks.snapshot()
        defer { prevTicks = current }
        guard let prev = prevTicks else { return }

        let dUser   = current.user   &- prev.user
        let dSys    = current.system &- prev.system
        let dIdle   = current.idle   &- prev.idle
        let dNice   = current.nice   &- prev.nice
        let total   = dUser &+ dSys &+ dIdle &+ dNice
        guard total > 0 else { return }
        cpuUsage = Double(dUser + dSys + dNice) / Double(total) * 100.0
    }
}

// MARK: - CPU tick snapshot

private struct CPUTicks {
    var user, system, idle, nice: UInt32

    static func snapshot() -> CPUTicks {
        var info  = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                _ = host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ptr, &count)
            }
        }
        return CPUTicks(
            user:   info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle:   info.cpu_ticks.2,
            nice:   info.cpu_ticks.3
        )
    }
}
