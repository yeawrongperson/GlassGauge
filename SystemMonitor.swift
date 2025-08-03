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
    var network: Double        // Keep for compatibility
    var networkIn: Double      // NEW: Incoming traffic
    var networkOut: Double     // NEW: Outgoing traffic
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
private let kIOPSCycleCountKey = "CycleCount"

enum TemperatureType {
    case cpu, gpu
}

// Temperature reading system with fallback tiers
struct TemperatureReader {
    private static var lastCPUTemp: Double = 0
    private static var lastGPUTemp: Double = 0
    private static var lastCPUUsage: Double = 0
    private static var lastGPUUsage: Double = 0
    private static var lastReadTime: Date = Date.distantPast
    private static let cacheTimeout: TimeInterval = 3.0 // Cache for 3 seconds
    
    // Main temperature reading method with fallback chain
    static func readTemperature(type: TemperatureType, currentUsage: Double) -> Double {
        // Update usage cache
        if type == .cpu {
            lastCPUUsage = currentUsage
        } else {
            lastGPUUsage = currentUsage
        }
        
        // Use cached value if recent
        let now = Date()
        if now.timeIntervalSince(lastReadTime) < cacheTimeout {
            return type == .cpu ? lastCPUTemp : lastGPUTemp
        }
        
        var temperature: Double = 0
        
        // Tier 1: Try IOKit thermal sensors (works on some Intel Macs)
        temperature = tryIOKitThermal(type: type)
        if temperature > 0 {
            updateCache(cpu: type == .cpu ? temperature : lastCPUTemp,
                       gpu: type == .gpu ? temperature : lastGPUTemp)
            return temperature
        }
        
        // Tier 2: Try PowerMetrics (no sudo, limited data)
        temperature = tryPowerMetricsLight(type: type)
        if temperature > 0 {
            updateCache(cpu: type == .cpu ? temperature : lastCPUTemp,
                       gpu: type == .gpu ? temperature : lastGPUTemp)
            return temperature
        }
        
        // Tier 3: Use thermal pressure + usage estimation
        temperature = estimateFromThermalPressure(type: type)
        if temperature > 0 {
            updateCache(cpu: type == .cpu ? temperature : lastCPUTemp,
                       gpu: type == .gpu ? temperature : lastGPUTemp)
            return temperature
        }
        
        // Tier 4: Pure usage-based estimation (always works)
        temperature = estimateFromUsage(type: type)
        updateCache(cpu: type == .cpu ? temperature : lastCPUTemp,
                   gpu: type == .gpu ? temperature : lastGPUTemp)
        return temperature
    }
    
    private static func updateCache(cpu: Double, gpu: Double) {
        lastCPUTemp = cpu
        lastGPUTemp = gpu
        lastReadTime = Date()
    }
    
    // Tier 1: IOKit thermal sensors (works on some Intel Macs)
    private static func tryIOKitThermal(type: TemperatureType) -> Double {
        let matching = IOServiceMatching("IOHWSensor")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }
        
        let searchTerms = type == .cpu ? ["cpu", "core", "package"] : ["gpu", "graphics", "radeon", "nvidia"]
        
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            
            if let sensorType = IORegistryEntryCreateCFProperty(service, "type" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
               sensorType == "temperature",
               let location = IORegistryEntryCreateCFProperty(service, "location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
               let value = IORegistryEntryCreateCFProperty(service, "current-value" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                
                let locationLower = location.lowercased()
                let hasMatch = searchTerms.contains { term in
                    locationLower.contains(term)
                }
                
                if hasMatch {
                    let temp = value.doubleValue / 100.0
                    if temp > 0 && temp < 150 {
                        print("IOKit \(type): \(temp)°C from \(location)")
                        return temp
                    }
                }
            }
        }
        return 0
    }
    
    // Tier 2: PowerMetrics without sudo (limited but sometimes works)
    private static func tryPowerMetricsLight(type: TemperatureType) -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        process.arguments = ["--samplers", "smc", "-n", "1", "-i", "50"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            
            // Quick timeout
            let timeoutDate = Date().addingTimeInterval(1.5)
            while process.isRunning && Date() < timeoutDate {
                usleep(10000)
            }
            
            if process.isRunning {
                process.terminate()
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return 0 }
            
            let temp = parseTemperatureFromOutput(output: output, type: type)
            if temp > 0 {
                print("PowerMetrics \(type): \(temp)°C")
            }
            return temp
            
        } catch {
            return 0
        }
    }
    
    // Tier 3: Thermal pressure + usage estimation
    private static func estimateFromThermalPressure(type: TemperatureType) -> Double {
        var thermalPressure: Double = 0
        
        // Try to get system thermal pressure
        let matching = IOServiceMatching("IOPMrootDomain")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        if service != 0 {
            defer { IOObjectRelease(service) }
            
            if let pressure = IORegistryEntryCreateCFProperty(
                service,
                "ThermalPressure" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? NSNumber {
                thermalPressure = pressure.doubleValue
            }
        }
        
        // Only use if we have meaningful thermal pressure
        if thermalPressure > 0 {
            let usage = type == .cpu ? lastCPUUsage : lastGPUUsage
            let baseTemp = type == .cpu ? 45.0 : 42.0
            let pressureFactor = thermalPressure * 0.4  // Pressure contributes to temp
            let usageFactor = (usage / 100.0) * 35.0    // Usage contributes to temp
            
            let temp = baseTemp + pressureFactor + usageFactor
            print("Thermal pressure \(type): \(temp)°C (pressure: \(thermalPressure)%, usage: \(usage)%)")
            return temp
        }
        
        return 0
    }
    
    // Tier 4: Pure usage-based estimation (always works)
    private static func estimateFromUsage(type: TemperatureType) -> Double {
        let usage = type == .cpu ? lastCPUUsage : lastGPUUsage
        
        if type == .cpu {
            // CPU thermal curve for Intel MacBook Pro
            let idleTemp = 45.0
            let maxTemp = 85.0
            let curve = pow(usage / 100.0, 1.5) // Non-linear curve
            let temp = idleTemp + (curve * (maxTemp - idleTemp))
            print("Estimated CPU: \(temp)°C (usage: \(usage)%)")
            return temp
        } else {
            // GPU thermal curve
            let idleTemp = 42.0
            let maxTemp = 88.0
            let curve = pow(usage / 100.0, 1.3)
            let temp = idleTemp + (curve * (maxTemp - idleTemp))
            print("Estimated GPU: \(temp)°C (usage: \(usage)%)")
            return temp
        }
    }
    
    // Temperature parsing helper
    private static func parseTemperatureFromOutput(output: String, type: TemperatureType) -> Double {
        let lines = output.components(separatedBy: .newlines)
        let searchTerm = type == .cpu ? "cpu" : "gpu"
        
        for line in lines {
            let lowercaseLine = line.lowercased()
            if lowercaseLine.contains(searchTerm) &&
               (lowercaseLine.contains("temperature") || lowercaseLine.contains("temp")) &&
               !lowercaseLine.contains("pressure") {
                
                // Parse temperature value from line
                let components = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                for (i, component) in components.enumerated() {
                    // Look for temperature indicators
                    if component.lowercased() == "c" || component.lowercased() == "°c" {
                        if i > 0 {
                            let tempStr = components[i-1].replacingOccurrences(of: ":", with: "")
                            if let temp = Double(tempStr), temp > 0 && temp < 150 {
                                return temp
                            }
                        }
                    }
                    
                    // Try finding numeric value followed by C
                    if let temp = Double(component), temp > 0 && temp < 150 {
                        if i + 1 < components.count {
                            let nextComponent = components[i + 1].lowercased()
                            if nextComponent == "c" || nextComponent == "°c" {
                                return temp
                            }
                        }
                    }
                }
            }
        }
        
        // If specific CPU/GPU not found, try general die temperature for CPU
        if type == .cpu {
            for line in lines {
                let lowercaseLine = line.lowercased()
                if lowercaseLine.contains("die temperature") && !lowercaseLine.contains("gpu") {
                    let components = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                    for (i, component) in components.enumerated() {
                        if component.lowercased() == "c" && i > 0 {
                            let tempStr = components[i-1].replacingOccurrences(of: ":", with: "")
                            if let temp = Double(tempStr), temp > 0 && temp < 150 {
                                return temp
                            }
                        }
                    }
                }
            }
        }
        
        return 0
    }
}

final class SystemMonitor {
    private var previousCPULoad: host_cpu_load_info?
    private var previousDisk: (read: UInt64, write: UInt64) = (0,0)
    private var previousNet: (rx: UInt64, tx: UInt64) = (0,0)
    
    // Store current usage for temperature calculations
    private var currentCPUUsage: Double = 0
    private var currentGPUUsage: Double = 0

    func sample() -> SystemSample {
        let cpu = cpuUsage()
        let mem = memoryUsage()
        let disk = diskActivity()
        let networkData = networkActivity()
        let battery = batteryInfo()
        let gpu = gpuUsage()
        let fan = fanSpeed()
        let power = battery.powerOut > 0 ? battery.powerOut : battery.powerIn
        
        // Update usage cache
        currentCPUUsage = cpu
        currentGPUUsage = gpu
        
        let cpuT = cpuTemperature()
        let gpuT = gpuTemperature()
        let diskT = temperature(for: ["ssd", "smart", "disk", "drive"])
        
        return SystemSample(cpu: cpu,
                            gpu: gpu,
                            memory: mem,
                            disk: disk,
                            network: networkData.total,
                            networkIn: networkData.incoming,
                            networkOut: networkData.outgoing,
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

    private func cpuTemperature() -> Double {
        #if arch(arm64)
        return 0
        #else
        return TemperatureReader.readTemperature(type: .cpu, currentUsage: currentCPUUsage)
        #endif
    }

    private func gpuTemperature() -> Double {
        #if arch(arm64)
        return 0
        #else
        return TemperatureReader.readTemperature(type: .gpu, currentUsage: currentGPUUsage)
        #endif
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

    private func networkActivity() -> (total: Double, incoming: Double, outgoing: Double) {
        var addrs: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0, 0) }
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
        
        let incoming = Double(deltaRx) / 1024.0
        let outgoing = Double(deltaTx) / 1024.0
        let total = incoming + outgoing
        
        return (total, incoming, outgoing)
    }

    private func batteryInfo() -> (level: Double, cycle: Int, powerIn: Double, powerOut: Double) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return (0,0,0,0)
        }

        // Find the internal battery source instead of assuming the first entry
        var batteryDetails: [String: Any]? = nil
        for ps in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any],
               let type = info[kIOPSTypeKey as String] as? String,
               type == kIOPSInternalBatteryType {
                batteryDetails = info
                break
            }
        }

        guard let info = batteryDetails,
              let current = info[kIOPSCurrentCapacityKey as String] as? Int,
              let max = info[kIOPSMaxCapacityKey as String] as? Int else {
            return (0,0,0,0)
        }

        let level = Double(current) / Double(max) * 100.0
        let cycle = info[kIOPSCycleCountKey as String] as? Int ?? 0

        let amps = info[kIOPSCurrentKey as String] as? Int ?? 0
        let voltage = info[kIOPSVoltageKey as String] as? Int ?? 11250

        // Convert to watts (mA * mV -> mW -> W)
        let watts = Double(abs(amps)) * Double(voltage) / 1_000_000.0

        // Determine direction using the charging flag when available
        let charging = info[kIOPSIsChargingKey as String] as? Bool ?? (amps > 0)
        let inW = charging ? watts : 0
        let outW = charging ? 0 : watts

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
