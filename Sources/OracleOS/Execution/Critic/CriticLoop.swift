// CriticLoop.swift — Self-evaluation after every executed action.
//
// Every action must be followed by a critic pass.
//
//   Input:   state_before, action, state_after
//   Output:  SUCCESS | PARTIAL_SUCCESS | FAILURE | UNKNOWN
//
// The planner receives a recovery signal when the critic detects
// FAILURE or UNKNOWN, closing the observe→plan→execute→evaluate
// feedback loop.

import Foundation

// MARK: - Outcome classification

/// Result of the critic's evaluation of a single action step.
public enum CriticOutcome: String, Sendable, Codable, CaseIterable {
    /// Expected state change observed.
    case success
    /// Some expected changes observed, but not all.
    case partialSuccess = "partial_success"
    /// Expected state change did not occur.
    case failure
    /// Unable to determine outcome.
    case unknown
}

// MARK: - Critic verdict

/// Full verdict produced by the critic for one execution step.
public struct CriticVerdict: Sendable, Codable {
    public let outcome: CriticOutcome
    public let preStateHash: String
    public let postStateHash: String
    public let actionName: String
    public let stateChanged: Bool
    public let expectedConditionsMet: Int
    public let expectedConditionsTotal: Int
    public let notes: [String]
    public let timestamp: TimeInterval

    public init(
        outcome: CriticOutcome,
        preStateHash: String,
        postStateHash: String,
        actionName: String,
        stateChanged: Bool,
        expectedConditionsMet: Int = 0,
        expectedConditionsTotal: Int = 0,
        notes: [String] = [],
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.outcome = outcome
        self.preStateHash = preStateHash
        self.postStateHash = postStateHash
        self.actionName = actionName
        self.stateChanged = stateChanged
        self.expectedConditionsMet = expectedConditionsMet
        self.expectedConditionsTotal = expectedConditionsTotal
        self.notes = notes
        self.timestamp = timestamp
    }

    /// Whether recovery should be triggered.
    public var needsRecovery: Bool {
        outcome == .failure || outcome == .unknown
    }

    public func toDict() -> [String: Any] {
        [
            "outcome": outcome.rawValue,
            "pre_state_hash": preStateHash,
            "post_state_hash": postStateHash,
            "action_name": actionName,
            "state_changed": stateChanged,
            "expected_conditions_met": expectedConditionsMet,
            "expected_conditions_total": expectedConditionsTotal,
            "needs_recovery": needsRecovery,
            "notes": notes,
            "timestamp": timestamp,
        ]
    }
}

// MARK: - Critic

/// Evaluates every executed action by comparing pre- and post-state,
/// checking postconditions from the action's ``ActionSchema``, and
/// classifying the outcome.
///
/// Usage:
///
///     let critic = CriticLoop()
///     let verdict = critic.evaluate(
///         preState: ..., postState: ...,
///         schema: ..., actionResult: ...
///     )
///     if verdict.needsRecovery { /* trigger recovery planner */ }
///
public struct CriticLoop: Sendable {
    public init() {}

    /// Evaluate a single action step.
    ///
    /// - Parameters:
    ///   - preState: Compressed UI state *before* the action.
    ///   - postState: Compressed UI state *after* the action.
    ///   - schema: The ``ActionSchema`` that was executed (may be nil for
    ///     actions that do not yet have schemas).
    ///   - actionResult: The ``ActionResult`` from the executor.
    /// - Returns: A ``CriticVerdict`` classifying the outcome.
    public func evaluate(
        preState: CompressedUIState,
        postState: CompressedUIState,
        schema: ActionSchema?,
        actionResult: ActionResult
    ) -> CriticVerdict {
        let preHash = stateFingerprint(preState)
        let postHash = stateFingerprint(postState)
        let stateChanged = preHash != postHash

        // If the executor already reports policy-blocked or hard failure,
        // short-circuit.
        if actionResult.blockedByPolicy {
            return CriticVerdict(
                outcome: .failure,
                preStateHash: preHash,
                postStateHash: postHash,
                actionName: schema?.name ?? "unknown",
                stateChanged: stateChanged,
                notes: ["action blocked by policy"]
            )
        }

        if !actionResult.success {
            return CriticVerdict(
                outcome: .failure,
                preStateHash: preHash,
                postStateHash: postHash,
                actionName: schema?.name ?? "unknown",
                stateChanged: stateChanged,
                notes: [actionResult.message ?? "action failed"]
            )
        }

        // If no schema is attached we can only do hash-level evaluation.
        guard let schema else {
            let outcome: CriticOutcome = stateChanged ? .success : .unknown
            return CriticVerdict(
                outcome: outcome,
                preStateHash: preHash,
                postStateHash: postHash,
                actionName: "unknown",
                stateChanged: stateChanged,
                notes: stateChanged ? ["state changed"] : ["no schema; state unchanged"]
            )
        }

        // Check expected postconditions against postState.
        let (met, total, notes) = checkPostconditions(
            schema.expectedPostconditions,
            in: postState
        )

        let outcome = classifyOutcome(
            stateChanged: stateChanged,
            conditionsMet: met,
            conditionsTotal: total,
            actionSuccess: actionResult.success,
            verified: actionResult.verified
        )

        return CriticVerdict(
            outcome: outcome,
            preStateHash: preHash,
            postStateHash: postHash,
            actionName: schema.name,
            stateChanged: stateChanged,
            expectedConditionsMet: met,
            expectedConditionsTotal: total,
            notes: notes
        )
    }

    // MARK: - Internal

    /// Classify the overall outcome from evidence.
    func classifyOutcome(
        stateChanged: Bool,
        conditionsMet: Int,
        conditionsTotal: Int,
        actionSuccess: Bool,
        verified: Bool
    ) -> CriticOutcome {
        // If postconditions are declared, use them as ground truth.
        if conditionsTotal > 0 {
            if conditionsMet == conditionsTotal { return .success }
            if conditionsMet > 0 { return .partialSuccess }
            return .failure
        }
        // No postconditions declared — fall back to state diff + executor verdict.
        if verified { return .success }
        if actionSuccess && stateChanged { return .success }
        if actionSuccess && !stateChanged { return .unknown }
        return .failure
    }

    /// Check each expected postcondition against the post state.
    func checkPostconditions(
        _ conditions: [SchemaCondition],
        in state: CompressedUIState
    ) -> (met: Int, total: Int, notes: [String]) {
        guard !conditions.isEmpty else { return (0, 0, []) }
        var met = 0
        var notes: [String] = []

        for condition in conditions {
            switch condition {
            case .elementExists(let kind, let label):
                if state.elements.contains(where: { $0.kind == kind && $0.label == label }) {
                    met += 1
                } else {
                    notes.append("missing \(kind.rawValue)(\(label))")
                }
            case .appFrontmost(let app):
                if state.app == app {
                    met += 1
                } else {
                    notes.append("app not frontmost: \(app)")
                }
            case .windowTitleContains(let value):
                if let title = state.windowTitle, title.contains(value) {
                    met += 1
                } else {
                    notes.append("window title missing: \(value)")
                }
            case .urlContains(let value):
                if let url = state.url, url.contains(value) {
                    met += 1
                } else {
                    notes.append("url missing: \(value)")
                }
            case .valueEquals(let label, let expected):
                // Cannot verify from CompressedUIState alone.
                notes.append("value check skipped for \(label)=\(expected)")
            case .custom(let description):
                // Custom predicates require external evaluation.
                notes.append("custom check skipped: \(description)")
            }
        }
        return (met, conditions.count, notes)
    }

    /// Simple fingerprint for change detection.
    func stateFingerprint(_ state: CompressedUIState) -> String {
        let parts = state.elements.map { "\($0.kind.rawValue)|\($0.label)" }
        let joined = parts.sorted().joined(separator: ";")
        let appPart = state.app ?? ""
        let titlePart = state.windowTitle ?? ""
        return "\(appPart)|\(titlePart)|\(joined)"
    }
}
