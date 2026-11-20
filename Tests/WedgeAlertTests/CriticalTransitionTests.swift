import Testing
@testable import WedgeAlert

@Test func warningToCriticalAlertsOnceUntilRecovery() {
    var tracker = CriticalTransitionTracker()
    let readings: [Severity] = [.warning, .critical, .critical, .unavailable, .critical, .warning, .critical]
    let alerts = readings.map { tracker.record($0, for: .disk) }
    #expect(alerts == [false, true, false, false, false, false, true])
}

@Test func catchesSuddenDropsAndExistingCriticalConditions() {
    var tracker = CriticalTransitionTracker()
    let readings: [(Metric, Severity)] = [
        (.memory, .critical), (.swapIn, .healthy), (.swapIn, .critical),
        (.memory, .critical), (.swap, .critical)
    ]
    let alerts = readings.map { tracker.record($0.1, for: $0.0) }
    #expect(alerts == [true, false, true, false, true])
}
