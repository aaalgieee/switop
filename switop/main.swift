//
//  main.swift
//  switop
//
//  Created by Al Gabriel on 12/14/24.
//

import Foundation

// ANSI escape codes for colors and formatting
let CLEAR = "\u{001B}[2J\u{001B}[H"
let BOLD = "\u{001B}[1m"
let RESET = "\u{001B}[0m"
let GREEN = "\u{001B}[32m"
let YELLOW = "\u{001B}[33m"
let SAVE_CURSOR = "\u{001B}7"
let RESTORE_CURSOR = "\u{001B}8"
let HIDE_CURSOR = "\u{001B}[?25l"
let SHOW_CURSOR = "\u{001B}[?25h"
let RED = "\u{001B}[31m"
let BLUE = "\u{001B}[34m"
let CYAN = "\u{001B}[36m"
let WHITE = "\u{001B}[37m"
let CURSOR_UP = "\u{001B}[1A"
let CURSOR_DOWN = "\u{001B}[1B"

// Constants for commands
let powermetricsPath = "/usr/bin/powermetrics"
let vmstatPath = "/usr/bin/vm_stat"
let samplingInterval = 1000 // 1 second

// Add new constants for sampling
let SAMPLE_BUFFER_SIZE = 4096
let REFRESH_INTERVAL = 250_000  // 500ms in microseconds

// Add ProcessRunner helper class
class ProcessRunner {
    static func run(_ path: String, arguments: [String] = []) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

// Function to format metrics
func formatMetric(_ name: String, _ value: String) -> String {
    let padding = 30 - name.count
    return "\(name)\(String(repeating: " ", count: max(0, padding)))│ \(value)"
}

// Function to get memory usage
func getMemoryUsage() -> (memoryUsed: String, swapUsed: String) {
    // Get physical memory info
    let pageSize = Int64(vm_page_size)
    let totalMemory = Int64(ProcessInfo.processInfo.physicalMemory)
    
    // Get vm_stat data
    let vmStatOutput = ProcessRunner.run(vmstatPath)
    
    // Parse vm_stat output with all memory page types
    var pagesActive: Int64 = 0
    var pagesWired: Int64 = 0
    var pagesCompressed: Int64 = 0
    var pagesCached: Int64 = 0  // For file-backed pages
    
    vmStatOutput.enumerateLines { line, _ in
        if line.contains("Pages active:") {
            pagesActive = Int64(line.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "")) ?? 0
        } else if line.contains("Pages wired down:") {
            pagesWired = Int64(line.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "")) ?? 0
        } else if line.contains("Pages stored in compressor:") {
            pagesCompressed = Int64(line.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "")) ?? 0
        } else if line.contains("File-backed pages:") {
            pagesCached = Int64(line.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "")) ?? 0
        }
    }
    
    // Calculate memory usage following Activity Monitor's methodology
    let appMemory = Double((pagesActive + pagesWired) * pageSize)
    let compressedMemory = Double(pagesCompressed * pageSize)
    let cachedMemory = Double(pagesCached * pageSize)
    
    // Calculate total used memory (app memory + compressed - cached)
    let usedMemory = appMemory + compressedMemory + cachedMemory
    let totalMemoryGB = Double(totalMemory) / (1024 * 1024 * 1024)
    let usedMemoryGB = usedMemory / (1024 * 1024 * 1024)
    let totalUsedMemoryGB = usedMemoryGB - totalMemoryGB
    
    // Get swap usage
    let swapOutput = ProcessRunner.run("/usr/sbin/sysctl", arguments: ["-n", "vm.swapusage"])
    var swapUsedMB = 0.0
    
    if let usedRange = swapOutput.range(of: "used = \\d+\\.\\d+M", options: .regularExpression) {
        let usedString = String(swapOutput[usedRange]).components(separatedBy: "= ")[1].replacingOccurrences(of: "M", with: "")
        swapUsedMB = Double(usedString) ?? 0
    }
    
    return (
        memoryUsed: String(format: "%.2f GB used of %.2f GB", totalUsedMemoryGB, totalMemoryGB),
        swapUsed: String(format: "%.0f MB", swapUsedMB)
    )
}

// Function to get system core counts
func getSystemCoreCounts() -> (eCores: Int, pCores: Int, gpuCores: Int) {
    let output = ProcessRunner.run("/usr/sbin/sysctl", arguments: ["-n", "hw.perflevel1.physicalcpu", "hw.perflevel0.physicalcpu"])
    let components = output.components(separatedBy: .newlines)
    
    let eCores = Int(components[0]) ?? 0
    let pCores = Int(components[1]) ?? 0
    
    // Cache GPU info as it's slow to fetch
    struct GPUInfo {
        static var cores: Int = -1
        static var lastUpdate = Date(timeIntervalSince1970: 0)
    }
    
    // Only update GPU info every 5 minutes
    if GPUInfo.cores == -1 || Date().timeIntervalSince(GPUInfo.lastUpdate) > 300 {
        let gpuOutput = ProcessRunner.run("/usr/sbin/system_profiler", arguments: ["SPDisplaysDataType"])
        if let coreRange = gpuOutput.range(of: "Total Number of Cores: \\d+", options: .regularExpression) {
            let coreString = String(gpuOutput[coreRange]).split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0"
            GPUInfo.cores = Int(coreString) ?? 0
            GPUInfo.lastUpdate = Date()
        }
    }
    
    return (eCores, pCores, GPUInfo.cores)
}

// Function to get chip info
func getChipInfo() -> String {
    let output = ProcessRunner.run("/usr/sbin/sysctl", arguments: ["-n", "machdep.cpu.brand_string"])
    
    // Get actual system core counts
    let (eCores, pCores, gpuCores) = getSystemCoreCounts()
    return "\(output) (cores: \(eCores)E+\(pCores)P+\(gpuCores)GPU)"
}

// Function to clear and draw header
func drawHeader() {
    print(CLEAR + HIDE_CURSOR)
    let chipInfo = getChipInfo()
    print("\(CYAN)\(BOLD)┌────────────────────────────────────────┐\(RESET)")
    print("\(CYAN)\(BOLD)│        System Performance Monitor      │\(RESET)")
    print("\(CYAN)\(BOLD)└────────────────────────────────────────┘\(RESET)\n")
    print("\(WHITE)\(BOLD)System: \(RESET)\(chipInfo)\n")
    print("\(RED)\(BOLD)Press Ctrl+C to exit\(RESET)\n")
}

// Function to execute powermetrics command
func runPowermetrics() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: powermetricsPath)
    
    process.arguments = [
        "-i", String(samplingInterval),
        "--samplers", "cpu_power,gpu_power"
    ]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    
    signal(SIGINT) { _ in
        print(SHOW_CURSOR)
        exit(0)
    }
    
    do {
        try process.run()
        
        let fileHandle = pipe.fileHandleForReading
        var buffer = Data()
        
        fileHandle.readabilityHandler = { handle in
            autoreleasepool {
                if let data = try? handle.read(upToCount: SAMPLE_BUFFER_SIZE) {
                    buffer.append(data)
                    
                    // Process complete lines only
                    if let string = String(data: buffer, encoding: .utf8),
                       string.contains("\n") {
                        drawHeader()
                        
                        // CPU Usage Section
                        print("\(YELLOW)\(BOLD)┌─── CPU Metrics " + String(repeating: "─", count: 20) + "\(RESET)")
                        // Parse E-Cluster metrics
                        if let eFreq = string.range(of: "E-Cluster HW active frequency: \\d+ MHz", options: .regularExpression),
                           let eResidency = string.range(of: "E-Cluster HW active residency:\\s+\\d+\\.\\d+%", options: .regularExpression) {
                            let frequency = String(string[eFreq]).split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "N/A"
                            let residency = String(string[eResidency]).split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "N/A"
                            print(formatMetric("E-CORES Usage", "\(residency) @ \(frequency)"))
                        }
                        
                        // Parse P-Cluster metrics
                        if let pFreq = string.range(of: "P-Cluster HW active frequency: \\d+ MHz", options: .regularExpression),
                           let pResidency = string.range(of: "P-Cluster HW active residency:\\s+\\d+\\.\\d+%", options: .regularExpression) {
                            let frequency = String(string[pFreq]).split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "N/A"
                            let residency = String(string[pResidency]).split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "N/A"
                            print(formatMetric("P-CORES Usage", "\(residency) @ \(frequency)"))
                        }
                        
                        // GPU Usage Section
                        print("\n\(YELLOW)\(BOLD)┌─── GPU Metrics " + String(repeating: "─", count: 20) + "\(RESET)")
                        if let gpuFreq = string.range(of: "GPU HW active frequency: \\d+ MHz", options: .regularExpression),
                           let gpuResidency = string.range(of: "GPU HW active residency:\\s+\\d+\\.\\d+%", options: .regularExpression) {
                            let frequency = String(string[gpuFreq]).split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "N/A"
                            let residency = String(string[gpuResidency]).split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "N/A"
                            print(formatMetric("GPU Usage", "\(residency) @ \(frequency)"))
                        }
                        
                        // Memory Metrics section
                        let memoryUsage = getMemoryUsage()
                        print("\n\(YELLOW)\(BOLD)┌─── Memory Metrics " + String(repeating: "─", count: 20) + "\(RESET)")
                        print(formatMetric("Memory Used", memoryUsage.memoryUsed))
                        print(formatMetric("Swap Used", memoryUsage.swapUsed))
                        
                        // Power Consumption Section
                        print("\n\(YELLOW)\(BOLD)┌─── Power Metrics " + String(repeating: "─", count: 20) + "\(RESET)")
                        
                        // Parse CPU Power
                        if let cpuPower = string.range(of: "CPU Power: \\d+ mW", options: .regularExpression) {
                            let powerMW = Double(String(string[cpuPower]).split(separator: ":").last?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " mW", with: "") ?? "0") ?? 0
                            let powerW = powerMW / 1000.0
                            print(formatMetric("CPU Power", String(format: "%.2f W", powerW)))
                        }
                        
                        // Parse GPU Power
                        if let gpuPower = string.range(of: "GPU Power: \\d+ mW", options: .regularExpression) {
                            let powerMW = Double(String(string[gpuPower]).split(separator: ":").last?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " mW", with: "") ?? "0") ?? 0
                            let powerW = powerMW / 1000.0
                            print(formatMetric("GPU Power", String(format: "%.2f W", powerW)))
                        }
                        
                        // Parse ANE Power
                        if let anePower = string.range(of: "ANE Power: \\d+ mW", options: .regularExpression) {
                            let powerMW = Double(String(string[anePower]).split(separator: ":").last?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " mW", with: "") ?? "0") ?? 0
                            let powerW = powerMW / 1000.0
                            print(formatMetric("ANE Power", String(format: "%.2f W", powerW)))
                        }
                        
                        // Calculate and display combined power
                        let pattern = "\\d+"
                        let regex = try? NSRegularExpression(pattern: pattern)
                        var totalPowerMW = 0
                        
                        if let cpuPower = string.range(of: "CPU Power: \\d+ mW", options: .regularExpression),
                           let cpuMatch = regex?.firstMatch(in: String(string[cpuPower]), options: [], range: NSRange(location: 0, length: String(string[cpuPower]).utf16.count)) {
                            let cpuValue = Int(String(string[cpuPower])[Range(cpuMatch.range, in: String(string[cpuPower]))!]) ?? 0
                            totalPowerMW += cpuValue
                        }
                        
                        if let gpuPower = string.range(of: "GPU Power: \\d+ mW", options: .regularExpression),
                           let gpuMatch = regex?.firstMatch(in: String(string[gpuPower]), options: [], range: NSRange(location: 0, length: String(string[gpuPower]).utf16.count)) {
                            let gpuValue = Int(String(string[gpuPower])[Range(gpuMatch.range, in: String(string[gpuPower]))!]) ?? 0
                            totalPowerMW += gpuValue
                        }
                        
                        if let anePower = string.range(of: "ANE Power: \\d+ mW", options: .regularExpression),
                           let aneMatch = regex?.firstMatch(in: String(string[anePower]), options: [], range: NSRange(location: 0, length: String(string[anePower]).utf16.count)) {
                            let aneValue = Int(String(string[anePower])[Range(aneMatch.range, in: String(string[anePower]))!]) ?? 0
                            totalPowerMW += aneValue
                        }
                        
                        let totalPowerW = Double(totalPowerMW) / 1000.0
                        print(formatMetric("Combined Power", String(format: "%.2f W", totalPowerW)))
                        print()
                        usleep(UInt32(REFRESH_INTERVAL))
                        buffer.removeAll()
                    }
                }
            }
        }
        
        process.waitUntilExit()
    } catch {
        print(SHOW_CURSOR)
        print("Error: \(error)")
        exit(1)
    }
}

// Start monitoring
runPowermetrics()
