import Foundation
import Darwin
import SwiftUI

enum Metric: String, CaseIterable, Identifiable {
    case disk, swapIn, swap, memory
    var id: String { rawValue }
    var title: String {
        switch self { case .disk: "Free disk"; case .swapIn: "Swap in"; case .swap: "Swap used"; case .memory: "Available RAM" }
    }
    var symbol: String {
        switch self { case .disk: "internaldrive"; case .swapIn: "arrow.down.circle"; case .swap: "arrow.left.arrow.right"; case .memory: "memorychip" }
    }
    var lowIsBad: Bool { self == .disk || self == .memory }
    var unit: String { self == .swapIn ? "MiB/s" : "GiB" }
    var defaultWarning: Double {
        switch self { case .disk: 30; case .swapIn: 1; case .swap: 4; case .memory: 4 }
    }
    var defaultCritical: Double {
        switch self { case .disk: 10; case .swapIn: 10; case .swap: 8; case .memory: 1 }
    }
    func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(self == .swapIn ? 2 : 1))) + " " + unit
    }
}

enum Severity: String {
    case healthy = "Healthy", warning = "Warning", critical = "Critical", unavailable = "Unavailable"
    var color: Color {
        switch self { case .healthy: .green; case .warning: .yellow; case .critical: .red; case .unavailable: .gray }
    }
}

@MainActor final class Preferences: ObservableObject {
    @Published var width: Double { didSet { defaults.set(width, forKey: "width") } }
    @Published var height: Double { didSet { defaults.set(height, forKey: "height") } }
    @Published var interval: Double { didSet { defaults.set(interval, forKey: "interval") } }
    @Published var historyDuration: Double { didSet { defaults.set(historyDuration, forKey: "historyDuration") } }
    static let historyDurations: [Double] = [30, 60, 120, 300, 600, 900, 1800, 3600]
    static func historyLabel(_ seconds: Double) -> String {
        seconds < 60 ? "\(Int(seconds)) sec" : "\(Int(seconds / 60)) min"
    }
    @Published var thresholds: [String: Double] { didSet { defaults.set(thresholds, forKey: "thresholds") } }
    private let defaults = UserDefaults.standard
    init() {
        width = defaults.object(forKey: "width") as? Double ?? 320
        height = defaults.object(forKey: "height") as? Double ?? 360
        interval = defaults.object(forKey: "interval") as? Double ?? 1
        let storedDuration = defaults.object(forKey: "historyDuration") as? Double ?? 120
        historyDuration = Self.historyDurations.contains(storedDuration) ? storedDuration : 120
        thresholds = defaults.dictionary(forKey: "thresholds") as? [String: Double] ?? [:]
        width = min(600, max(260, width)); height = min(700, max(300, height))
        interval = min(5, max(0.5, interval))
    }
    func threshold(_ metric: Metric, critical: Bool) -> Double {
        thresholds[metric.rawValue + (critical ? ".critical" : ".warning")] ?? (critical ? metric.defaultCritical : metric.defaultWarning)
    }
    func set(_ value: Double, metric: Metric, critical: Bool) {
        guard value.isFinite, value >= 0 else { return }
        thresholds[metric.rawValue + (critical ? ".critical" : ".warning")] = value
        let warning = threshold(metric, critical: false), danger = threshold(metric, critical: true)
        if metric.lowIsBad ? danger > warning : danger < warning {
            thresholds[metric.rawValue + (critical ? ".warning" : ".critical")] = value
        }
    }
    func severity(_ metric: Metric, value: Double?) -> Severity {
        guard let value else { return .unavailable }
        if metric.lowIsBad {
            if value <= threshold(metric, critical: true) { return .critical }
            if value <= threshold(metric, critical: false) { return .warning }
        } else {
            if value >= threshold(metric, critical: true) { return .critical }
            if value >= threshold(metric, critical: false) { return .warning }
        }
        return .healthy
    }
}

struct Sample: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double?
}

@MainActor final class Monitor: ObservableObject {
    @Published private(set) var history: [Metric: [Sample]] = [:]
    @Published private(set) var details: [Metric: String] = [:]
    @Published private(set) var updated: Date?
    private var previousSwap: (count: UInt64, time: TimeInterval)?
    private let gib = 1_073_741_824.0
    func value(_ metric: Metric) -> Double? { history[metric]?.last?.value }

    func sample() {
        let now = Date()
        let clock = ProcessInfo.processInfo.systemUptime
        var values: [Metric: Double] = [:]
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
            if let free = attributes[.systemFreeSize] as? NSNumber, let total = attributes[.systemSize] as? NSNumber {
                values[.disk] = free.doubleValue / gib
                details[.disk] = "Startup volume (/)\nFree: \(Metric.disk.formatted(free.doubleValue / gib)) of \(Metric.disk.formatted(total.doubleValue / gib))\nActual filesystem free space; excludes reclaimable storage. APFS volumes can share container space."
            }
        } catch { details[.disk] = "Disk information unavailable: \(error.localizedDescription)" }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            values[.swap] = Double(swap.xsu_used) / gib
            details[.swap] = "Swap used: \(Metric.swap.formatted(Double(swap.xsu_used) / gib))\nAllocated: \(Metric.swap.formatted(Double(swap.xsu_total) / gib))\nDisk space used for swapped-out memory."
        } else { details[.swap] = "Swap usage unavailable." }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        if result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS {
            // Speculative pages are included in free_count; do not add them twice.
            let available = Double(UInt64(stats.free_count) + UInt64(stats.inactive_count)) * Double(pageSize)
            values[.memory] = available / gib
            details[.memory] = "Estimated available: \(Metric.memory.formatted(available / gib))\nPhysical RAM: \(Metric.memory.formatted(Double(ProcessInfo.processInfo.physicalMemory) / gib))\nFree + inactive pages. Reclaimable estimate, not macOS memory pressure.\nCompressed: \(Metric.memory.formatted(Double(stats.compressor_page_count) * Double(pageSize) / gib))"
            if let previous = previousSwap, clock > previous.time, clock - previous.time < 30, stats.swapins >= previous.count {
                values[.swapIn] = Double(stats.swapins - previous.count) * Double(pageSize) / (clock - previous.time) / 1_048_576
            }
            previousSwap = (stats.swapins, clock)
            details[.swapIn] = "Pages read back from swap per second, converted to MiB/s.\nCumulative swap-ins since boot: \(stats.swapins.formatted()) pages\nPage size: \(pageSize) bytes\nFirst sample and wake from sleep require a new baseline."
        } else {
            previousSwap = nil
            details[.memory] = "RAM statistics unavailable."
            details[.swapIn] = "Swap-in statistics unavailable."
        }
        for metric in Metric.allCases {
            history[metric, default: []].append(Sample(time: now, value: values[metric]))
            // Keep an hour so changing the visible duration can reveal existing samples.
            history[metric]?.removeAll { now.timeIntervalSince($0.time) > 3600 }
        }
        updated = now
    }
}
