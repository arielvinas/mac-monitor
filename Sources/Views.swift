import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Paleta

enum Palette {
    static let blue = Color(red: 0.23, green: 0.51, blue: 0.96)
    static let pink = Color(red: 0.91, green: 0.36, blue: 0.62)
    static let yellow = Color(red: 0.98, green: 0.78, blue: 0.25)
    static let track = Color.primary.opacity(0.12)
}

// MARK: - Piezas comunes

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.blue)
    }
}

struct LegendRow: View {
    let color: Color
    let label: String
    let value: String
    var unit: String = ""
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
            Spacer()
            ValueText(value: value, unit: unit)
        }
        .font(.system(size: 13))
    }
}

/// Número con la unidad más chica, estilo iStat ("14.4 GB", "86%").
struct ValueText: View {
    let value: String
    let unit: String
    var body: some View {
        (Text(value).monospacedDigit() + Text(unit.isEmpty ? "" : (unit == "%" ? unit : " " + unit)).font(.system(size: 10, weight: .medium)))
    }
}

struct ProcessList: View {
    let entries: [ProcessEntry]
    let format: (Double) -> (String, String)
    var placeholder = "Cargando…"
    var body: some View {
        Card {
            SectionTitle(text: "PROCESOS")
            if entries.isEmpty {
                Text(placeholder).font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
            ForEach(entries) { entry in
                HStack(spacing: 7) {
                    Image(nsImage: entry.icon).resizable().frame(width: 16, height: 16)
                    Text(entry.name).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    let (v, u) = format(entry.value)
                    ValueText(value: v, unit: u)
                }
                .font(.system(size: 13))
            }
        }
    }
}

struct Ring: View {
    /// Segmentos (fracción, color) dibujados en orden horario desde arriba.
    let segments: [(Double, Color)]
    var lineWidth: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: lineWidth)
            ForEach(Array(segmentRanges.enumerated()), id: \.offset) { _, seg in
                Circle()
                    .trim(from: seg.0, to: seg.1)
                    .stroke(seg.2, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
    }

    private var segmentRanges: [(CGFloat, CGFloat, Color)] {
        var start = 0.0
        return segments.map { frac, color in
            let f = max(0, min(1 - start, frac))
            defer { start += f }
            return (start, start + f, color)
        }
    }
}

struct Footer: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        HStack(spacing: 10) {
            Button("Monitor de Actividad") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            Toggle("Al iniciar", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Spacer()
            Button("Salir") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

// MARK: - CPU

struct CPUHistoryChart: View {
    let history: [CPULoad]
    let capacity: Int
    var body: some View {
        Canvas { ctx, size in
            let slot = size.width / CGFloat(capacity)
            let barW = max(1, slot * 0.72)
            let offset = capacity - history.count
            for (i, load) in history.enumerated() {
                let x = CGFloat(i + offset) * slot + (slot - barW) / 2
                let userH = CGFloat(min(1, load.user)) * size.height
                let sysH = CGFloat(min(1 - load.user, load.system)) * size.height
                // Mínimo visible para que se vea la "línea base" como en iStat.
                let u = max(userH, 1)
                ctx.fill(Path(CGRect(x: x, y: size.height - u, width: barW, height: u)), with: .color(Palette.blue))
                if sysH > 0 {
                    ctx.fill(Path(CGRect(x: x, y: size.height - u - sysH, width: barW, height: sysH)), with: .color(Palette.pink))
                }
            }
        }
    }
}

struct CPUView: View {
    @ObservedObject var monitor: Monitor

    var body: some View {
        VStack(spacing: 8) {
            Card {
                HStack {
                    SectionTitle(text: "CPU")
                    Spacer()
                    Text(String(format: "%d núcleos · carga %.2f", monitor.cpu.coreCount, monitor.loadAverage))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                CPUHistoryChart(history: monitor.cpuHistory, capacity: Monitor.historyCapacity)
                    .frame(height: 110)
                HStack(spacing: 14) {
                    LegendRow(color: Palette.blue, label: "Usuario", value: Fmt.percent(monitor.cpuLoad.user), unit: "%")
                    LegendRow(color: Palette.pink, label: "Sistema", value: Fmt.percent(monitor.cpuLoad.system), unit: "%")
                }
            }

            Card {
                let groups = monitor.cpu.groups
                let n = monitor.cpu.coreCount
                let perRow = n <= 12 ? n : (n + 1) / 2
                let rows = stride(from: 0, to: monitor.cpu.coreCount, by: perRow).map { $0..<min($0 + perRow, monitor.cpu.coreCount) }
                VStack(spacing: 5) {
                    ForEach(rows, id: \.lowerBound) { row in
                        HStack(spacing: 0) {
                            ForEach(row, id: \.self) { core in
                                Ring(segments: [(monitor.coreLoads[safe: core] ?? 0, color(forCore: core))], lineWidth: 3.5)
                                    .frame(width: 22, height: 22)
                                    .frame(maxWidth: .infinity)
                            }
                            ForEach(0..<(perRow - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 22) }
                        }
                    }
                }
                .padding(.bottom, 2)
                ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                    LegendRow(color: groupColor(idx), label: "Núcleos \(localized(group.name)) (\(group.range.count))",
                              value: Fmt.percent(average(group.range)), unit: "%")
                }
            }

            ProcessList(entries: monitor.cpuProcesses) { (String(format: "%.1f", $0), "%") }
            Footer()
        }
        .padding(10)
        .frame(width: 330)
    }

    private func groupColor(_ idx: Int) -> Color { idx == 0 && monitor.cpu.groups.count > 1 ? Palette.pink : Palette.blue }

    private func color(forCore core: Int) -> Color {
        let idx = monitor.cpu.groups.firstIndex { $0.range.contains(core) } ?? 0
        return groupColor(idx)
    }

    private func average(_ range: Range<Int>) -> Double {
        let values = range.compactMap { monitor.coreLoads[safe: $0] }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private func localized(_ name: String) -> String {
        switch name {
        case "Efficiency": return "de eficiencia"
        case "Performance": return "de rendimiento"
        case "Super": return "Super"
        default: return name
        }
    }
}

// MARK: - Memoria

struct BigRing: View {
    let segments: [(Double, Color)]
    let value: Double
    let caption: String
    var body: some View {
        ZStack {
            Ring(segments: segments, lineWidth: 9)
            VStack(spacing: 0) {
                (Text(Fmt.percent(value)).font(.system(size: 30, weight: .regular)).monospacedDigit()
                 + Text("%").font(.system(size: 16)))
                Text(caption).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 118, height: 118)
    }
}

struct MemoryView: View {
    @ObservedObject var monitor: Monitor

    var body: some View {
        let mem = monitor.memory
        let total = Double(max(mem.total, 1))
        VStack(spacing: 8) {
            Card {
                HStack {
                    Spacer()
                    BigRing(segments: [(mem.pressure, Palette.blue)], value: mem.pressure, caption: "PRESIÓN")
                    Spacer()
                    BigRing(segments: [(Double(mem.app) / total, Palette.blue),
                                       (Double(mem.wired) / total, Palette.pink),
                                       (Double(mem.compressed) / total, Palette.yellow)],
                            value: mem.usedFraction, caption: "MEMORIA")
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            Card {
                row(Palette.blue, "Apps", mem.app)
                row(Palette.pink, "Wired", mem.wired)
                row(Palette.yellow, "Comprimida", mem.compressed)
                row(Color.secondary.opacity(0.45), "Libre", mem.free)
            }
            ProcessList(entries: monitor.memoryProcesses) { Fmt.bytes($0) }
            Footer()
        }
        .padding(10)
        .frame(width: 330)
    }

    private func row(_ color: Color, _ label: String, _ bytes: UInt64) -> some View {
        let (v, u) = Fmt.bytes(Double(bytes))
        return LegendRow(color: color, label: label, value: v, unit: u)
    }
}

// MARK: - Red

struct NetworkHistoryChart: View {
    let history: [NetworkRate]
    let capacity: Int
    /// Escala compartida por ambas mitades: entrada hacia arriba, salida hacia abajo (como iStat).
    let scale: Double
    var body: some View {
        Canvas { ctx, size in
            let slot = size.width / CGFloat(capacity)
            let barW = max(1, slot * 0.72)
            let mid = size.height / 2
            let offset = capacity - history.count
            ctx.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(Palette.track))
            for (i, rate) in history.enumerated() {
                let x = CGFloat(i + offset) * slot + (slot - barW) / 2
                let inH = CGFloat(min(1, rate.inBps / scale)) * (mid - 1)
                let outH = CGFloat(min(1, rate.outBps / scale)) * (mid - 1)
                if inH > 0 { ctx.fill(Path(CGRect(x: x, y: mid - 0.5 - inH, width: barW, height: inH)), with: .color(Palette.blue)) }
                if outH > 0 { ctx.fill(Path(CGRect(x: x, y: mid + 0.5, width: barW, height: outH)), with: .color(Palette.pink)) }
            }
        }
    }
}

struct NetworkView: View {
    @ObservedObject var monitor: Monitor

    var body: some View {
        let rate = monitor.network
        let scale = niceScale(monitor.networkHistory.map { max($0.inBps, $0.outBps) }.max() ?? 0)
        VStack(spacing: 8) {
            Card {
                HStack {
                    SectionTitle(text: "RED")
                    Spacer()
                    let (v, u) = Fmt.rate(scale)
                    Text("escala \(v) \(u)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                NetworkHistoryChart(history: monitor.networkHistory, capacity: Monitor.historyCapacity, scale: scale)
                    .frame(height: 110)
                HStack(spacing: 14) {
                    rateRow(Palette.blue, "Entrada", rate.inBps)
                    rateRow(Palette.pink, "Salida", rate.outBps)
                }
            }
            Card {
                SectionTitle(text: "TOTAL DESDE QUE SE ABRIÓ")
                totalRow(Palette.blue, "Recibido", monitor.net.totalIn)
                totalRow(Palette.pink, "Enviado", monitor.net.totalOut)
            }
            ProcessList(entries: monitor.networkProcesses ?? [], format: Fmt.rate,
                        placeholder: monitor.networkProcesses == nil ? "Cargando…" : "Sin tráfico")
            Footer()
        }
        .padding(10)
        .frame(width: 330)
    }

    private func rateRow(_ color: Color, _ label: String, _ bps: Double) -> some View {
        let (v, u) = Fmt.rate(bps)
        return LegendRow(color: color, label: label, value: v, unit: u)
    }

    private func totalRow(_ color: Color, _ label: String, _ bytes: UInt64) -> some View {
        let (v, u) = Fmt.total(bytes)
        return LegendRow(color: color, label: label, value: v, unit: u)
    }

    /// Redondea el máximo hacia arriba a 1, 2 o 5 KB/MB/GB/s para que la escala sea legible.
    private func niceScale(_ peak: Double) -> Double {
        let steps = [1024.0, 1_048_576, 1_073_741_824].flatMap { unit in
            [1.0, 2, 5, 10, 20, 50, 100, 200, 500].map { $0 * unit }
        }
        return steps.first { $0 >= peak && $0 >= 10 * 1024 } ?? steps.last!
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
