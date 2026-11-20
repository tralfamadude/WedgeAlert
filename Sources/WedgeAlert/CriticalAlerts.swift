import AppKit
import SwiftUI

/// Missing samples do not re-arm an incident. A valid noncritical sample does.
struct CriticalTransitionTracker {
    private var previous: [Metric: Severity] = [:]

    mutating func record(_ severity: Severity, for metric: Metric) -> Bool {
        guard severity != .unavailable else { return false }
        let shouldAlert = severity == .critical && previous[metric] != .critical
        previous[metric] = severity
        return shouldAlert
    }
}

struct CriticalEvent: Identifiable {
    let id = UUID()
    let metric: Metric
    let value: Double
    let threshold: Double
    let time: Date

    var message: String {
        switch metric {
        case .disk: "Free disk space is critically low. Free up space to leave room for saves, updates, and swap."
        case .memory: "Estimated available RAM is critically low. Review memory use in Activity Monitor and close unneeded apps."
        case .swapIn: "Swap-in activity is critically high. Reading memory back from disk may be contributing to slowness."
        case .swap: "Swap usage is critically high. Review memory-heavy apps and check remaining disk space."
        }
    }
}

@MainActor final class CriticalAlertPresenter: ObservableObject {
    @Published private(set) var events: [CriticalEvent] = []
    private var tracker = CriticalTransitionTracker()
    private var panel: NSPanel?

    func check(monitor: Monitor, preferences: Preferences) {
        var added = false
        for metric in Metric.allCases {
            let value = monitor.value(metric)
            if tracker.record(preferences.severity(metric, value: value), for: metric), let value {
                events.append(CriticalEvent(metric: metric, value: value,
                                            threshold: preferences.threshold(metric, critical: true),
                                            time: monitor.updated ?? Date()))
                added = true
            }
        }
        guard added else { return }
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 490, height: 420),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "WedgeAlert — Critical resource alert"
            panel.level = .modalPanel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentViewController = NSHostingController(rootView: CriticalAlertView(presenter: self))
            panel.center()
            self.panel = panel
        }
        // A separate panel brings the incident above the floating monitor without
        // blocking the run loop: sampling and additional incident recording continue.
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        NSApp.requestUserAttention(.criticalRequest)
    }

    func acknowledge() {
        panel?.orderOut(nil)
        events.removeAll()
    }
}

private struct CriticalAlertView: View {
    @ObservedObject var presenter: CriticalAlertPresenter
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Critical resource alert", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold()).foregroundStyle(.red)
            Text("Recorded threshold crossings — readings may have changed since these events.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(presenter.events.reversed()) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.metric.title).font(.headline)
                            Text(event.time.formatted(.dateTime.year().month().day().hour().minute().second().timeZone()))
                                .font(.callout.bold()).textSelection(.enabled)
                            Text("Recorded: \(event.metric.formatted(event.value)) · Critical: \(event.metric.lowIsBad ? "≤" : "≥") \(event.metric.formatted(event.threshold))")
                                .font(.callout).monospacedDigit()
                            Text(event.message).font(.callout)
                        }
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Acknowledge") { presenter.acknowledge() }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 490, height: 420)
    }
}
