import AppKit
import Darwin

// MARK: - CPU

struct CPULoad {
    var user: Double = 0
    var system: Double = 0
    var total: Double { user + system }
}

struct CoreGroup: Identifiable {
    let id: Int          // hw.perflevelN
    let name: String     // "Performance", "Efficiency", "Super"...
    let range: Range<Int>
}

final class CPUReader {
    private var prevTotal: host_cpu_load_info?
    private var prevCores: [UInt32] = []   // ticks planos: [user, system, idle, nice] * n
    let groups: [CoreGroup]
    let coreCount: Int

    init() {
        coreCount = ProcessInfo.processInfo.activeProcessorCount
        // En Apple Silicon los núcleos de menor rendimiento (perflevel más alto) vienen primero.
        let levels = Self.sysctlInt("hw.nperflevels") ?? 1
        var groups: [CoreGroup] = []
        var start = 0
        for level in stride(from: levels - 1, through: 0, by: -1) {
            let count = Self.sysctlInt("hw.perflevel\(level).logicalcpu") ?? coreCount
            let name = Self.sysctlString("hw.perflevel\(level).name") ?? "CPU"
            let end = min(start + count, coreCount)
            if end > start { groups.append(CoreGroup(id: level, name: name, range: start..<end)) }
            start = end
        }
        self.groups = groups.isEmpty ? [CoreGroup(id: 0, name: "CPU", range: 0..<coreCount)] : groups
    }

    func sampleTotal() -> CPULoad {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return CPULoad() }
        defer { prevTotal = info }
        guard let prev = prevTotal else { return CPULoad() }
        let user = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return CPULoad() }
        return CPULoad(user: (user + nice) / total, system: system / total)
    }

    func sampleCores() -> [Double] {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount) == KERN_SUCCESS,
              let infoArray else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let ticks = (0..<Int(infoCount)).map { UInt32(bitPattern: infoArray[$0]) }
        defer { prevCores = ticks }
        guard prevCores.count == ticks.count else { return Array(repeating: 0, count: Int(cpuCount)) }

        let states = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { cpu in
            let base = cpu * states
            let d = (0..<states).map { Double(ticks[base + $0] &- prevCores[base + $0]) }
            let total = d.reduce(0, +)
            let idle = d[Int(CPU_STATE_IDLE)]
            return total > 0 ? (total - idle) / total : 0
        }
    }

    static func loadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) > 0 ? loads[0] : 0
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}

// MARK: - Memoria

struct MemoryInfo {
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var pressure: Double = 0   // 0...1
    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used ? total - used : 0 }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func sample() -> MemoryInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var info = MemoryInfo()
        guard result == KERN_SUCCESS else { return info }
        let page = UInt64(vm_kernel_page_size)
        // Mismo cálculo que Monitor de Actividad: App + Wired + Comprimida.
        info.app = UInt64(stats.internal_page_count &- stats.purgeable_count) * page
        info.wired = UInt64(stats.wire_count) * page
        info.compressed = UInt64(stats.compressor_page_count) * page
        // kern.memorystatus_level = % de memoria "libre" según el kernel; la presión es el complemento.
        if let level = CPUReader.sysctlInt("kern.memorystatus_level") {
            info.pressure = max(0, min(1, Double(100 - level) / 100))
        }
        return info
    }
}

// MARK: - Procesos

struct ProcessEntry: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let value: Double
}

enum ProcessReader {
    private static var iconCache: [String: NSImage] = [:]
    private static let cacheLock = NSLock()

    /// Top de procesos por CPU (%). Agrupa helpers dentro del mismo .app.
    static func topCPU(limit: Int = 5) -> [ProcessEntry] {
        guard let out = run("/bin/ps", ["-Aeo", "pid=,pcpu="]) else { return [] }
        var rows: [(pid_t, Double)] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let pid = pid_t(parts[0]), let cpu = Double(parts[1]) else { continue }
            rows.append((pid, cpu))
        }
        return aggregate(rows, limit: limit)
    }

    /// Top de procesos por memoria (bytes, "footprint" como Monitor de Actividad).
    static func topMemory(limit: Int = 5) -> [ProcessEntry] {
        guard let out = run("/usr/bin/top", ["-l", "1", "-o", "mem", "-n", "300", "-stats", "pid,mem"]) else { return [] }
        var rows: [(pid_t, Double)] = []
        var inTable = false
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.first == "PID" { inTable = true; continue }
            guard inTable, parts.count >= 2, let pid = pid_t(parts[0]), let bytes = parseSize(String(parts[1])) else { continue }
            rows.append((pid, bytes))
        }
        return aggregate(rows, limit: limit)
    }

    private static func aggregate(_ rows: [(pid_t, Double)], limit: Int) -> [ProcessEntry] {
        var totals: [String: (name: String, path: String, value: Double)] = [:]
        for (pid, value) in rows where value > 0 {
            let (key, name, path) = identify(pid)
            totals[key, default: (name, path, 0)].value += value
        }
        return totals.sorted { $0.value.value > $1.value.value }.prefix(limit).map {
            ProcessEntry(id: $0.key, name: $0.value.name, icon: icon(for: $0.value.path), value: $0.value.value)
        }
    }

    /// Devuelve (clave de agrupación, nombre visible, ruta para el ícono).
    private static func identify(_ pid: pid_t) -> (String, String, String) {
        var buf = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        if len <= 0 {
            var nameBuf = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name = String(cString: nameBuf)
            return (pid == 0 ? "kernel_task" : "pid:\(name.isEmpty ? String(pid) : name)",
                    pid == 0 ? "kernel_task" : (name.isEmpty ? "PID \(pid)" : name), "")
        }
        let path = String(cString: buf)
        // El .app más externo agrupa helpers (p. ej. "Google Chrome Helper (Renderer)" → Google Chrome).
        if let range = path.range(of: ".app/") {
            let bundlePath = String(path[..<range.lowerBound]) + ".app"
            let name = FileManager.default.displayName(atPath: bundlePath).replacingOccurrences(of: ".app", with: "")
            return (bundlePath, name, bundlePath)
        }
        var name = (path as NSString).lastPathComponent
        // Binarios versionados (p. ej. ~/.local/share/claude/versions/2.1.284) → nombre del proceso.
        if name.first?.isNumber == true {
            let skip: Set<String> = ["versions", "bin", "libexec", "current"]
            name = (path as NSString).pathComponents.reversed()
                .first { !($0.first?.isNumber ?? true) && !skip.contains($0) && $0 != "/" } ?? name
        }
        return (path, name, "")
    }

    private static func icon(for path: String) -> NSImage {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = iconCache[path] { return cached }
        let image = path.isEmpty
            ? NSWorkspace.shared.icon(for: .unixExecutable)
            : NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        iconCache[path] = image
        return image
    }

    private static func parseSize(_ raw: String) -> Double? {
        var s = raw
        while let last = s.last, last == "+" || last == "-" { s.removeLast() }
        guard let unit = s.last else { return nil }
        let multipliers: [Character: Double] = ["B": 1, "K": 1024, "M": 1024 * 1024, "G": 1024 * 1024 * 1024, "T": 1024 * 1024 * 1024 * 1024]
        if let m = multipliers[unit], let v = Double(s.dropLast()) { return v * m }
        return Double(s)
    }

    private static func run(_ launchPath: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        task.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Formato

enum Fmt {
    static func percent(_ v: Double) -> String { String(format: "%.0f", max(0, v) * 100) }

    static func bytes(_ b: Double) -> (String, String) {
        let gb = b / 1_073_741_824
        if gb >= 1 { return (String(format: "%.1f", gb), "GB") }
        return (String(format: "%.0f", b / 1_048_576), "MB")
    }
}
