import Foundation

public final class AppMemoryStore {

    private var controls: [String: KnownControl] = [:]
    private var failures: [FailurePattern] = []
    private var strategies: [StrategyRecord] = []
    private var protectedOperationCounts: [String: Int] = [:]
    private var approvalCounts: [String: Int] = [:]

    public init() {}

    public func recordControl(_ control: KnownControl) {
        controls[control.key] = control
    }

    public func getControl(key: String) -> KnownControl? {
        controls[key]
    }

    public func recordFailure(_ failure: FailurePattern) {
        failures.append(failure)
    }

    public func recordStrategy(_ record: StrategyRecord) {
        strategies.append(record)
    }

    public func controlsForApp(_ app: String) -> [KnownControl] {
        controls.values.filter { $0.app == app }
    }

    public func failuresForApp(_ app: String) -> [FailurePattern] {
        failures.filter { $0.app == app }
    }

    public func strategiesForApp(_ app: String) -> [StrategyRecord] {
        strategies.filter { $0.app == app }
    }

    public func recordProtectedOperation(app: String, operation: String) {
        protectedOperationCounts["\(app)|\(operation)", default: 0] += 1
    }

    public func recordApproval(app: String, operation: String) {
        approvalCounts["\(app)|\(operation)", default: 0] += 1
    }

    public func protectedOperationCount(app: String, operation: String) -> Int {
        protectedOperationCounts["\(app)|\(operation)", default: 0]
    }

    public func approvalCount(app: String, operation: String) -> Int {
        approvalCounts["\(app)|\(operation)", default: 0]
    }
}
