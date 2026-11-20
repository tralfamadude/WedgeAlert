# WedgeAlert

WedgeAlert is an early warning system for Macs running macOS 15 or later. Its compact, always-on-top window helps you spot two problems before they interrupt your work: **running out of disk space** and **slowness associated with low available RAM and swapping**.

Running out of disk space can lead to a hard reboot. (Been there, done that. I did not know that Time Machine can make multi-gigabyte temporary files and wedge the system.)

Four live readings, color-coded borders, and sparklines make changing conditions visible at a glance. Hover over a chart for more detail. When a reading becomes critical, a foreground dialog records what happened and when, so you can see the event even if you were away from your desk.

## Spot a disk-space shortage

Watch **Free disk** for the startup volume. A downward trend can give you time to free space before there is too little room for saves, downloads, updates, or growing swap files.

The default border turns yellow at **30 GiB or less** and red at **10 GiB or less**. These are starting points: set thresholds that leave enough headroom for your workload. A critical alert includes the free-space reading and the threshold that was crossed.

## Spot memory-related slowness

Read the three memory indicators together:

- **Available RAM** estimates memory that is free or potentially reclaimable. A sustained decline suggests less room for active work.
- **Swap used** shows how much disk space is holding swapped-out memory. High swap usage alone does not establish that the Mac is currently slow.
- **Swap in** shows how quickly memory is being read back from swap. Sustained swap-in activity alongside low available RAM can help explain pauses when switching apps or returning to a large project.

Use the chart time window to distinguish a brief spike from a sustained trend. If the Mac is slowing down and these readings are worsening, review memory use in Activity Monitor and close unneeded apps or reduce the active workload. WedgeAlert reports system-wide symptoms; it does not identify a particular app as the cause, and it does not automatically quit apps or delete files.

## Critical alerts

When any metric moves from warning to critical, WedgeAlert activates and brings a separate alert dialog above the monitor and normal desktop windows. It also alerts on a jump directly from healthy to critical, or a critical condition found in the first valid sample.

Each incident includes:

- The metric and a plain-language explanation.
- The recorded value and critical threshold, with units.
- The detection date and time, including seconds and the local time zone.

The dialog remains visible until you acknowledge or close it, even if readings recover while you are away. Sampling continues while it is open. Additional critical crossings are added to the same dialog, newest first, with their own timestamps. **Acknowledge** clears the recorded incidents. Closing the dialog hides it; unacknowledged incidents remain in memory and reappear with the next critical incident.

A metric that stays critical does not generate an alert every refresh. It must produce a valid noncritical reading before another critical crossing triggers an alert; an unavailable reading does not reset it. Changing thresholds can cause an alert on the next sample if a metric newly becomes critical. Incidents are held in memory only and do not survive quitting the app.

Alerts are detected while the monitor is open and the Mac is awake. A timestamp records when WedgeAlert detected the condition, not an inferred time during sleep or while monitoring was stopped. The dialog cannot appear over the macOS lock screen; a detected incident remains available after you unlock.

## Install and launch

Build the app using Apple's Command Line Tools (`xcode-select --install`) or Xcode:

```sh
bash scripts/build-app.sh
open dist/WedgeAlert.app
```

Copy `dist/WedgeAlert.app` to **Applications** for everyday use, then double-click it. Quit an older running copy before opening the updated build. When rebuilding later, quit WedgeAlert and replace the copy in Applications with the new build.

To keep it in the Dock, right-click its Dock icon and select **Options → Keep in Dock**. To launch at login, add WedgeAlert from Applications under **System Settings → General → Login Items & Extensions → Open at Login**.

The build is locally ad-hoc signed. Distribution to other Macs requires Developer ID signing and notarization. For development, use `swift run` or open `Package.swift` in Xcode. The app uses native SwiftUI and Swift Charts, with no third-party dependencies or network requests.

## Monitor and settings

Drag the window background to reposition it. The monitor floats above normal windows across desktops. Hover over a card for 450 ms, or click it, to show measurement details, severity, and thresholds.

Open Settings using the gear, **Command-comma**, or the menu bar icon. Configure:

| Setting | Choices |
| --- | --- |
| Window width | 260–600 points |
| Window height | 300–700 points |
| Refresh interval | 0.5, 1, 2, or 5 seconds |
| Chart time window | 30 seconds; 1, 2, 5, 10, 15, 30, or 60 minutes |
| Severity thresholds | Warning and critical values for each metric |

Threshold entries place the numeric field immediately before its colored label. Free disk and available RAM trigger **at or below** their thresholds; swap used and swap in trigger **at or above** their thresholds. Thresholds stay ordered automatically when edited. Settings save immediately, and **Restore Defaults** resets them.

Borders show **green** for healthy, **yellow** for warning, **red** for critical, and **gray** for unavailable. Hover details also state the status in words.

Chart time-window changes rescale both axes immediately. Up to one hour of samples is retained in memory while monitoring; increasing the time window reveals any history already collected. History starts fresh after restarting the app. The default window is two minutes, with one-second sampling.

Close the monitor to hide it; use the menu bar's **Show Monitor** to reopen it. Monitoring runs while the monitor window is open. **Command-Q** quits. Window position and preferences persist locally. The original bundle identifier is retained so preferences survive the rename from DiskTrack.

## Measurements and default thresholds

| Metric | Source and interpretation | Warning | Critical |
| --- | --- | --- | --- |
| Free disk | Startup filesystem `/`, actual free bytes; excludes purgeable/reclaimable storage | ≤30 GiB | ≤10 GiB |
| Swap in | Change in `host_statistics64.swapins` × host page size, divided by actual elapsed seconds | ≥1 MiB/s | ≥10 MiB/s |
| Swap used | `sysctl vm.swapusage`, used bytes | ≥4 GiB | ≥8 GiB |
| Available RAM | Free + inactive VM pages; speculative pages already belong to free pages | ≤4 GiB | ≤1 GiB |

GiB and MiB are binary units. APFS volumes can share container space. Available RAM is a reclaimable-memory estimate, not Activity Monitor's memory-pressure score. Swap-ins measure reads from swap, not all page-ins or swap-outs. The first swap-in sample requires a baseline, and long sampling gaps after sleep reset that baseline. Rates use monotonic elapsed time. Historical readings stay raw, so changing thresholds recolors charts immediately.

## Development checks

```sh
swift test
bash scripts/build-app.sh
dist/WedgeAlert.app/Contents/MacOS/WedgeAlert --check-metrics
```

Transition tests cover warning-to-critical alerts, repeated critical samples, recovery and re-entry, unavailable samples, sudden drops, initial critical conditions, and independent metrics. The metrics check reads actual system counters and exits unsuccessfully if a reading is unavailable or invalid. An execution sandbox may restrict access to swap usage even though the normal desktop app can read it.
