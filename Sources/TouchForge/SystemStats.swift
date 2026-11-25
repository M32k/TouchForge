import Foundation
import IOKit.ps

/// 배터리 / CPU / 메모리 정보
enum SystemStats {
    struct Battery {
        var percent: Int
        var isCharging: Bool
        var onAC: Bool
    }

    static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as NSArray? else {
            return nil
        }
        for source in list {
            guard let unmanaged = IOPSGetPowerSourceDescription(info, source as CFTypeRef),
                  let description = unmanaged.takeUnretainedValue() as NSDictionary as? [String: Any] else {
                continue
            }
            let current = description["Current Capacity"] as? Int ?? 0
            let maximum = description["Max Capacity"] as? Int ?? 100
            let charging = description["Is Charging"] as? Bool ?? false
            let state = description["Power Source State"] as? String ?? ""
            let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
            return Battery(percent: percent, isCharging: charging, onAC: state == "AC Power")
        }
        return nil
    }

    typealias CPUTicks = (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3))
    }

    /// 두 시점의 틱 차이로 사용률(0~100)을 계산
    static func cpuPercent(from old: CPUTicks, to new: CPUTicks) -> Double {
        let user = Double(new.user &- old.user)
        let system = Double(new.system &- old.system)
        let idle = Double(new.idle &- old.idle)
        let nice = Double(new.nice &- old.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return (user + system + nice) / total * 100
    }

    /// (사용 중, 전체) 바이트 — 활성 상태 보기의 "사용된 메모리"와 비슷한 계산
    static func memory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)

        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0
        let used = (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (used, ProcessInfo.processInfo.physicalMemory)
    }
}
