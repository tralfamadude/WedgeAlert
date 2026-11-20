import SwiftUI
import AppKit
import Charts

@main struct WedgeAlertApp: App {
    init() {
        if CommandLine.arguments.contains("--check-metrics") {
            let monitor = Monitor()
            monitor.sample()
            Thread.sleep(forTimeInterval: 0.1)
            monitor.sample()
            var failed = false
            for metric in Metric.allCases {
                if let value = monitor.value(metric), value.isFinite, value >= 0 {
                    print("\(metric.title): \(metric.formatted(value))")
                } else {
                    print("FAILED: \(metric.title) unavailable or invalid")
                    failed = true
                }
            }
            exit(failed ? 1 : 0)
        }
    }
    @StateObject private var preferences = Preferences()
    @StateObject private var monitor = Monitor()
    @StateObject private var alerts = CriticalAlertPresenter()
    var body: some Scene {
        Window("WedgeAlert", id: "monitor") {
            MonitorView()
                .environmentObject(preferences)
                .environmentObject(monitor)
                .environmentObject(alerts)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        Settings {
            SettingsView().environmentObject(preferences)
        }
        MenuBarExtra("WedgeAlert", systemImage: "waveform.path.ecg") {
            MenuContent()
        }
    }
}

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Button("Show Monitor") {
            openWindow(id: "monitor")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Settings…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit WedgeAlert") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct MonitorView: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var monitor: Monitor
    @EnvironmentObject private var alerts: CriticalAlertPresenter
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(.mint)
                Text("WEDGEALERT").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.5)
                Spacer()
                Text("LIVE").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                Circle().fill(.mint).frame(width: 4, height: 4)
                Button { openSettings(); NSApp.activate(ignoringOtherApps: true) } label: {
                    Image(systemName: "gearshape").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Settings (⌘,)")
            }.padding(.horizontal, 3).padding(.top, 4)
            ForEach(Metric.allCases) { metric in
                MetricCard(metric: metric)
            }
            HStack {
                Text("\(Preferences.historyLabel(preferences.historyDuration).uppercased()) HISTORY")
                Spacer()
                Text("\(preferences.interval.formatted())s refresh · hover for details")
            }.font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: preferences.width, height: preferences.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowBridge())
        .task(id: preferences.interval) {
            while !Task.isCancelled {
                monitor.sample()
                alerts.check(monitor: monitor, preferences: preferences)
                do { try await Task.sleep(for: .seconds(preferences.interval)) }
                catch { break }
            }
        }
    }
}

struct MetricCard: View {
    let metric: Metric
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var monitor: Monitor
    @State private var hovered = false
    @State private var showDetails = false
    private var severity: Severity { preferences.severity(metric, value: monitor.value(metric)) }
    private var visibleHistory: [Sample] {
        let start = (monitor.updated ?? Date()).addingTimeInterval(-preferences.historyDuration)
        return (monitor.history[metric] ?? []).filter { $0.time >= start }
    }
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Label(metric.title, systemImage: metric.symbol)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(monitor.value(metric).map { metric.formatted($0) } ?? "—")
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Chart(visibleHistory) { sample in
                if let value = sample.value {
                    AreaMark(x: .value("Time", sample.time), yStart: .value("Baseline", 0), yEnd: .value(metric.title, value))
                        .foregroundStyle(LinearGradient(colors: [severity.color.opacity(0.22), severity.color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", sample.time), y: .value(metric.title, value))
                        .foregroundStyle(severity.color).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartXScale(domain: (monitor.updated ?? Date()).addingTimeInterval(-preferences.historyDuration)...(monitor.updated ?? Date()))
            .chartYScale(domain: 0...max(visibleHistory.compactMap(\.value).max() ?? 1, 0.01) * 1.15)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxHeight: .infinity)
        .background(severity.color.opacity(hovered ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(severity.color.opacity(hovered ? 1 : 0.65), lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside; if !inside { showDetails = false } }
        .task(id: hovered) {
            guard hovered else { return }
            do { try await Task.sleep(for: .milliseconds(450)); showDetails = true } catch { }
        }
        .onTapGesture { showDetails.toggle() }
        .popover(isPresented: $showDetails, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(metric.title).font(.headline)
                    Spacer()
                    Text(severity.rawValue).foregroundStyle(severity.color).font(.caption.bold())
                }
                Text(monitor.details[metric] ?? "Collecting first sample…").font(.callout).fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("Warning \(metric.lowIsBad ? "≤" : "≥") \(metric.formatted(preferences.threshold(metric, critical: false)))\nCritical \(metric.lowIsBad ? "≤" : "≥") \(metric.formatted(preferences.threshold(metric, critical: true)))")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(width: 300).preferredColorScheme(.dark)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title), \(monitor.value(metric).map { metric.formatted($0) } ?? "Unavailable"), \(severity.rawValue)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showDetails.toggle() }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    var body: some View {
        Form {
            Section("Monitor window") {
                LabeledContent("Width") {
                    Slider(value: $preferences.width, in: 260...600, step: 10)
                    Text("\(Int(preferences.width)) pt").monospacedDigit().frame(width: 55)
                }
                LabeledContent("Height") {
                    Slider(value: $preferences.height, in: 300...700, step: 10)
                    Text("\(Int(preferences.height)) pt").monospacedDigit().frame(width: 55)
                }
                Picker("Refresh interval", selection: $preferences.interval) {
                    Text("0.5 seconds").tag(0.5)
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
                Picker("Chart time window", selection: $preferences.historyDuration) {
                    ForEach(Preferences.historyDurations, id: \.self) { duration in
                        Text(Preferences.historyLabel(duration)).tag(duration)
                    }
                }
                Text("Charts update immediately. History collects while the monitor is open and is kept in memory for up to one hour.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("The monitor stays above normal windows and appears on all desktops, including full-screen apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Severity thresholds") {
                ForEach(Metric.allCases) { metric in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(metric.title) (\(metric.unit))").font(.headline)
                        HStack {
                            thresholdField(metric, critical: false)
                            thresholdField(metric, critical: true)
                        }
                        Text(metric.lowIsBad ? "Triggers at or below these values." : "Triggers at or above these values.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 3)
                }
                Text("Green: healthy · Yellow: warning · Red: critical · Gray: unavailable. Thresholds stay ordered automatically. Changes save immediately.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Restore Defaults") {
                    preferences.thresholds = [:]
                    preferences.width = 320; preferences.height = 360; preferences.interval = 1
                    preferences.historyDuration = 120
                }
            }
        }.formStyle(.grouped).frame(width: 480, height: 650)
    }
    private func thresholdField(_ metric: Metric, critical: Bool) -> some View {
        HStack(spacing: 5) {
            TextField("Value", value: Binding(
                get: { preferences.threshold(metric, critical: critical) },
                set: { preferences.set($0, metric: metric, critical: critical) }
            ), format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 76)
                .accessibilityLabel("\(metric.title) \(critical ? "critical" : "warning") threshold in \(metric.unit)")
            Circle().fill(critical ? Color.red : Color.yellow).frame(width: 6, height: 6)
            Text(critical ? "Critical" : "Warning").font(.caption)
            Spacer(minLength: 0)
        }
    }
}

struct WindowBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FloatingView() }
    func updateNSView(_ nsView: NSView, context: Context) { }
    private final class FloatingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovableByWindowBackground = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.setFrameAutosaveName("WedgeAlertMonitor")
        }
    }
}
