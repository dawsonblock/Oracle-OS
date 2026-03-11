public final class RecoveryRegistry {

    private var strategies: [FailureClass: any RecoveryStrategy] = [:]

    public func register(
        failure: FailureClass,
        strategy: any RecoveryStrategy
    ) {
        strategies[failure] = strategy
    }

    public func strategy(
        for failure: FailureClass
    ) -> (any RecoveryStrategy)? {
        strategies[failure]
    }
}
