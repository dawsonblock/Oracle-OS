public final class RecoveryRegistry {

    private var strategies: [FailureClass: RecoveryStrategy] = [:]

    public func register(
        failure: FailureClass,
        strategy: RecoveryStrategy
    ) {
        strategies[failure] = strategy
    }

    public func strategy(
        for failure: FailureClass
    ) -> RecoveryStrategy? {
        strategies[failure]
    }
}
