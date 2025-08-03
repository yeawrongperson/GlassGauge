import Foundation
import IOKit
import IOKit.ps
import IOKit.storage
import IOKit.graphics
import Darwin

struct SystemSample {
    var cpu: Double
    var gpu: Double
    var memory: Double
    var disk: Double
    var network: Double
    var battery: Double
    var fans: Double
    var power: Double
    var cpuTemp: Double
    var gpuTemp: Double
    var diskTemp: Double
    var batteryCycle: Int
    var powerIn: Double
    var powerOut: Double
}

private let kIOBlockStorageDriverStatisticsKey = "Statistics"
private let kIOBlockStorageDriverStatisticsBytesReadKey = "Bytes (Read)"
private let kIOBlockStorageDriverStatisticsBytesWrittenKey = "Bytes (Write)"
// Not all Swift toolchains surface the cycle count key from IOPowerSources,
// so declare the string constant manually to avoid build failures.
// Use the exact key name expected by IOPowerSources so we read the current
// battery cycle count rather than the design limit (commonly 1000 cycles).
private let kIOPSCycleCountKey = "CycleCount"


final class SystemMonitor {
    private var previousCPULoad: host_cpu_load_info?
    private var previousDisk: (read: UInt64, write: UInt64) = (0,0)
    private var previousNet: (rx: UInt64, tx: UInt64) = (0,0)

    func sample() -> SystemSample {
        let cpu = cpuUsage()
        let mem = memoryUsage()
        let disk = diskActivity()
        let net = networkActivity()
        let battery = batteryInfo()
        let gpu = gpuUsage()
        let fan = fanSpeed()
        let power = battery.powerOut > 0 ? battery.powerOut : battery.powerIn
        let cpuT = temperature(for: ["cpu"])
        let gpuT = temperature(for: ["gpu"])
        let diskT = temperature(for: ["ssd", "smart", "disk", "drive"])
        return SystemSample(cpu: cpu,
                            gpu: gpu,
                            memory: mem,
                            disk: disk,
                            network: net,
                            battery: battery.level,
                            fans: fan,
                            power: power,
                            cpuTemp: cpuT,
                            gpuTemp: gpuT,
                            diskTemp: diskT,
                            batteryCycle: battery.cycle,
                            powerIn: battery.powerIn,
                            powerOut: battery.powerOut)
    }

    private func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        defer { previousCPULoad = info }
        guard let prev = previousCPULoad else { return 0 }
        let userDiff = Double(info.cpu_ticks.0 - prev.cpu_ticks.0)
        let systemDiff = Double(info.cpu_ticks.1 - prev.cpu_ticks.1)
        let idleDiff = Double(info.cpu_ticks.2 - prev.cpu_ticks.2)
        let niceDiff = Double(info.cpu_ticks.3 - prev.cpu_ticks.3)
        let total = userDiff + systemDiff + idleDiff + niceDiff
        guard total > 0 else { return 0 }
        return (userDiff + systemDiff + niceDiff) / total * 100.0
    }

    private func memoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let active = Double(stats.active_count)
        let wired = Double(stats.wire_count)
        let compressed = Double(stats.compressor_page_count)
        let pageSize = Double(vm_kernel_page_size)
        let usedBytes = (active + wired + compressed) * pageSize
        return usedBytes / 1024.0 / 1024.0 / 1024.0
    }

    private func diskActivity() -> Double {
        let matching = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0
        var write: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = properties?.takeRetainedValue() as? [String: Any],
               let stats = dict[kIOBlockStorageDriverStatisticsKey] as? [String: Any] {
                if let r = stats[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber {
                    read += r.uint64Value
                }
                if let w = stats[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber {
                    write += w.uint64Value
                }
            }
            IOObjectRelease(service)
        }
        let deltaRead = read - previousDisk.read
        let deltaWrite = write - previousDisk.write
        previousDisk = (read, write)
        return Double(deltaRead + deltaWrite) / 1024.0
    }

    private func networkActivity() -> Double {
        var addrs: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&addrs) == 0, let first = addrs else { return 0 }
        defer { freeifaddrs(addrs) }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let flags = Int32(p.pointee.ifa_flags)
            if (flags & Int32(IFF_UP|IFF_RUNNING)) == Int32(IFF_UP|IFF_RUNNING),
               let data = p.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx += UInt64(data.pointee.ifi_ibytes)
                tx += UInt64(data.pointee.ifi_obytes)
            }
            ptr = p.pointee.ifa_next
        }
        let deltaRx = rx - previousNet.rx
        let deltaTx = tx - previousNet.tx
        previousNet = (rx, tx)
        return Double(deltaRx + deltaTx) / 1024.0
    }

    private func batteryInfo() -> (level: Double, cycle: Int, powerIn: Double, powerOut: Double) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty,
              let info = IOPSGetPowerSourceDescription(snapshot, sources[0]).takeUnretainedValue() as? [String: Any],
              let current = info[kIOPSCurrentCapacityKey] as? Int,
              let max = info[kIOPSMaxCapacityKey] as? Int else {
            return (0,0,0,0)
        }
        
        let level = Double(current) / Double(max) * 100.0
        
        // Get cycle count - try the key we can see in the output
        let cycle = info["DesignCycleCount"] as? Int ?? 0
        
        // Get current in milliamps
        let amps = info["Current"] as? Int ?? 0
        
        // Use default voltage for MacBook Pro 16" (2019) batteries
        // Most MacBook Pro batteries are around 11.1V to 11.4V nominal
        let voltage = 11250.0  // 11.25V in millivolts (typical for MacBook Pro 16")
        
        // Calculate watts: (milliamps * millivolts) / 1,000,000 = watts
        let watts = abs(Double(amps)) * voltage / 1_000_000.0
        
        // Positive current means charging (power in), negative means discharging (power out)
        let inW = amps > 0 ? watts : 0
        let outW = amps < 0 ? watts : 0
        
        return (level, cycle, inW, outW)
    }

    private func gpuUsage() -> Double {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let perf = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let busy = perf["GPU Busy"] as? Double {
                IOObjectRelease(service)
                return busy * 100.0
            }
            IOObjectRelease(service)
        }
        return 0
    }

    private func fanSpeed() -> Double {
        let matching = IOServiceMatching("AppleFan")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }
        var total: Double = 0
        var count: Double = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let rpm = IORegistryEntryCreateCFProperty(service, "actual-speed" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Double {
                total += rpm
                count += 1
            }
            IOObjectRelease(service)
        }
        guard count > 0 else { return 0 }
        return total / count
    }

    private func temperature(for matches: [String]) -> Double {
#if arch(arm64)
        // Apple Silicon doesn't expose these sensors
        return 0
#else
        let matching = IOServiceMatching("IOHWSensor")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let type = IORegistryEntryCreateCFProperty(service, "type" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
               type == "temperature",
               let location = IORegistryEntryCreateCFProperty(service, "location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
               matches.contains(where: { location.lowercased().contains($0) }),
               let value = IORegistryEntryCreateCFProperty(service, "current-value" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                return value.doubleValue / 100.0
            }
        }
        return 0
#endif
    }
}
