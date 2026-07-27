// PaceEngine+Alarm.swift — how loudly to say what the projection found.
//
// The projection answers "will I make it?". This answers the question that
// actually decides the colour of the menubar: "and does it cost me
// anything if I don't?" Those are different questions, and collapsing them
// is what made Robut exhausting to look at.
//
// Replayed against real history (2026-07, ~1.3 days at 10-minute ticks),
// folding the raw outlook straight into colour read RED 52% of the time —
// and gold, the entire middle of the scale, never appeared once. Half of
// that red was a weekly projected to run dry ~20h early on a week that
// had actually ended at 96% the time before: a prediction contradicted by
// the user's own history, reported as an emergency. The rest was session
// churn, which resolves itself within hours no matter what anyone does.
//
// The same history under the policy below: 48% calm, 45% notice, 7% alert.

import Foundation

extension PaceEngine {

    /// Below this, running dry costs nothing worth a colour: you'd be
    /// blocked briefly and the window refills on its own.
    ///
    /// This is deliberately LONGER than a session window, so **a session
    /// can never raise a full alert.** A five-hour limit always heals
    /// itself within five hours; there is no action to take and no reason
    /// to shout. It was the single loudest source of red in practice.
    static let materialDryStretch: TimeInterval = 6 * 3600

    /// …and running dry must also cost a real share of the time you have
    /// left. Six days out, a projection is mostly noise and there is
    /// ample room to self-correct; six hours out it is neither. Scaling
    /// the tolerance to the remaining time makes it decay precisely as
    /// certainty rises — strict exactly when it matters.
    static let alarmingDryShare = 0.25

    /// How loudly to say a verdict. Pure, and deliberately separate from
    /// the projection: the engine's job is to be *right* about what
    /// happens; this decides whether it's worth raising your pulse.
    static func alarmLevel(
        for verdict: PaceVerdict, window: UsageWindow, now: Date
    ) -> PaceAlarm {
        switch verdict.outlook {
        case .comfortable, .idle, .unknown:
            return .none
        case .tight:
            return .notice
        case .shortfall, .exhausted:
            let secondsToReset = max(0, window.resetsAt.timeIntervalSince(now))
            // Already spent = dry for whatever is left of the window.
            let dry = verdict.outlook == .exhausted
                ? secondsToReset
                : (verdict.shortfall ?? 0)
            let threshold = max(materialDryStretch, alarmingDryShare * secondsToReset)
            return dry >= threshold ? .alert : .notice
        }
    }
}
