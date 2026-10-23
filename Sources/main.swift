import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Estado compartido

final class Monitor: ObservableObject {
    static let historyCapacity = 60

    let cpu = CPUReader()
    @Published var cpuLoad = CPULoad()
    @Published var cpuHistory: [CPULoad] = []
    @Published var coreLoads: [Double] = []
    @Published var loadAverage: Double = 0
    @Published var memory = MemoryInfo()
    @Published var cpuProcesses: [ProcessEntry] = []
    @Published var memoryProcesses: [ProcessEntry] = []
    let net = NetworkReader()
    @Published var network = NetworkRate()
    @Published var networkHistory: [NetworkRate] = []
    /// nil mientras nettop todavía no entregó la primera medición.
    @Published var networkProcesses: [ProcessEntry]?
    private lazy var netStream = NetworkProcessStream { [weak self] list in
        DispatchQueue.main.async { if self?.showingNetwork == true { self?.networkProcesses = list } }
    }

    /// Qué popover está abierto: los procesos sólo se leen mientras se ven.
    var showingCPU = false
    var showingMemory = false
    var showingNetwork = false {
        didSet {
            guard showingNetwork != oldValue else { return }
            if showingNetwork { networkProcesses = nil; netStream.start() } else { netStream.stop() }
        }
    }
    var onUpdate: (() -> Void)?

    private var ticks = 0
    private var loadingProcesses = false
    private let queue = DispatchQueue(label: "macmonitor.processes", qos: .utility)

    func start() {
        _ = cpu.sampleTotal()
        _ = cpu.sampleCores()
        _ = net.sample()
        // Primera lectura tras un intervalo real; con ~0 ms los deltas dan valores absurdos.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.tick() }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
    }

    func refreshProcessesNow() { ticks = 0; refreshProcesses() }

    private func tick() {
        let load = cpu.sampleTotal()
        cpuLoad = load
        cpuHistory.append(load)
        if cpuHistory.count > Self.historyCapacity { cpuHistory.removeFirst(cpuHistory.count - Self.historyCapacity) }
        coreLoads = cpu.sampleCores()
        loadAverage = CPUReader.loadAverage()
        memory = MemoryInfo.sample()
        network = net.sample()
        networkHistory.append(network)
        if networkHistory.count > Self.historyCapacity { networkHistory.removeFirst(networkHistory.count - Self.historyCapacity) }
        onUpdate?()

        ticks += 1
        if ticks % 2 == 0 { refreshProcesses() }
    }

    private func refreshProcesses() {
        guard !loadingProcesses, showingCPU || showingMemory else { return }
        loadingProcesses = true
        let wantCPU = showingCPU, wantMem = showingMemory
        queue.async { [weak self] in
            let cpuList = wantCPU ? ProcessReader.topCPU() : nil
            let memList = wantMem ? ProcessReader.topMemory() : nil
            DispatchQueue.main.async {
                guard let self else { return }
                if let cpuList { self.cpuProcesses = cpuList }
                if let memList { self.memoryProcesses = memList }
                self.loadingProcesses = false
            }
        }
    }
}

// MARK: - Ítem de la barra de menús ("MEM" arriba, "13%" abajo)

final class MetricItem: NSObject, NSPopoverDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let label: String
    private let popover = NSPopover()
    private let onShowChange: (Bool) -> Void

    private static let labelFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)

    init<V: View>(label: String, content: V, onShowChange: @escaping (Bool) -> Void) {
        self.label = label
        self.onShowChange = onShowChange
        super.init()
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.imagePosition = .imageOnly
    }

    func update(percent: Double) {
        statusItem.button?.image = render(value: Fmt.percent(percent) + "%")
    }

    private static let rateFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)

    /// Dos renglones chicos, estilo iStat: "↑ 12 KB/s" arriba (salida), "↓ 1.4 MB/s" abajo (entrada).
    func update(rate: NetworkRate) {
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.rateFont, .foregroundColor: NSColor.black]
        let line = { (arrow: String, bps: Double) -> String in
            let (v, u) = Fmt.rate(bps)
            return "\(arrow) \(v) \(u)"
        }
        let top = line("↑", rate.outBps), bottom = line("↓", rate.inBps)
        let height = max(NSStatusBar.system.thickness, 24)
        // Ancho fijo (el del texto más largo posible) para que la barra no "baile".
        let width = ceil(("↓ 999 KB/s" as NSString).size(withAttributes: attrs).width) + 2
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let lineH = Self.rateFont.capHeight + 3.5
            let bottomBaseline: CGFloat = 3.5
            (bottom as NSString).draw(at: NSPoint(x: 1, y: bottomBaseline + Self.rateFont.descender), withAttributes: attrs)
            (top as NSString).draw(at: NSPoint(x: 1, y: bottomBaseline + lineH + Self.rateFont.descender), withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        statusItem.button?.image = image
    }

    private func render(value: String) -> NSImage {
        let height = max(NSStatusBar.system.thickness, 24)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: Self.labelFont, .foregroundColor: NSColor.black, .kern: 0.3]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: Self.valueFont, .foregroundColor: NSColor.black]
        // Ancho fijo (el de "100%") para que la barra no "baile" al cambiar el número.
        let width = ceil(max(("100%" as NSString).size(withAttributes: valueAttrs).width,
                             (label as NSString).size(withAttributes: labelAttrs).width)) + 4

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let valueSize = (value as NSString).size(withAttributes: valueAttrs)
            let labelSize = (self.label as NSString).size(withAttributes: labelAttrs)
            // Posiciones por línea base: valor abajo, etiqueta arriba.
            let valueBaseline: CGFloat = 2
            let labelBaseline = valueBaseline + Self.valueFont.capHeight + 3.5
            (value as NSString).draw(at: NSPoint(x: (width - valueSize.width) / 2, y: valueBaseline + Self.valueFont.descender),
                                     withAttributes: valueAttrs)
            (self.label as NSString).draw(at: NSPoint(x: (width - labelSize.width) / 2, y: labelBaseline + Self.labelFont.descender),
                                          withAttributes: labelAttrs)
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            onShowChange(true)
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) { onShowChange(false) }
}

// MARK: - App

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor()
    private var cpuItem: MetricItem!
    private var memItem: MetricItem!
    private var netItem: MetricItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        enableLaunchAtLoginOnce()
        // El último ítem creado queda a la izquierda: NET y CPU primero para ver "MEM  CPU  NET".
        netItem = MetricItem(label: "NET", content: NetworkView(monitor: monitor)) { [weak self] shown in
            self?.monitor.showingNetwork = shown
        }
        cpuItem = MetricItem(label: "CPU", content: CPUView(monitor: monitor)) { [weak self] shown in
            self?.monitor.showingCPU = shown
            if shown { self?.monitor.refreshProcessesNow() }
        }
        memItem = MetricItem(label: "MEM", content: MemoryView(monitor: monitor)) { [weak self] shown in
            self?.monitor.showingMemory = shown
            if shown { self?.monitor.refreshProcessesNow() }
        }
        cpuItem.statusItem.autosaveName = "macmonitor.cpu"
        memItem.statusItem.autosaveName = "macmonitor.mem"
        netItem.statusItem.autosaveName = "macmonitor.net"

        monitor.onUpdate = { [weak self] in
            guard let self else { return }
            self.cpuItem.update(percent: self.monitor.cpuLoad.total)
            self.memItem.update(percent: self.monitor.memory.usedFraction)
            self.netItem.update(rate: self.monitor.network)
        }
        monitor.start()

        // Modo de depuración: `MacMonitor --snapshot <dir>` guarda los popovers como PNG.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count {
            let item = ["mem": memItem, "net": netItem][args[i + 1]] ?? cpuItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { item?.toggle() }
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            monitor.showingCPU = true
            monitor.showingMemory = true
            monitor.showingNetwork = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { self.snapshot(to: args[i + 1]) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { monitor.showingNetwork = false }

    /// La primera vez que corre desde /Applications se registra para abrirse al iniciar sesión.
    /// Si después lo desactivás con "Al iniciar", se respeta y no se vuelve a activar.
    private func enableLaunchAtLoginOnce() {
        let key = "launchAtLoginConfigured"
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !UserDefaults.standard.bool(forKey: key) else { return }
        if SMAppService.mainApp.status == .enabled || (try? SMAppService.mainApp.register()) != nil {
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    private func snapshot(to dir: String) {
        for (name, view) in [("cpu", AnyView(CPUView(monitor: monitor))), ("mem", AnyView(MemoryView(monitor: monitor))),
                           ("net", AnyView(NetworkView(monitor: monitor)))] {
            let renderer = ImageRenderer(content: view.background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 2
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            }
        }
        for (name, item) in [("bar-mem", memItem!), ("bar-cpu", cpuItem!), ("bar-net", netItem!)] {
            if let tiff = item.statusItem.button?.image?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            }
        }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
