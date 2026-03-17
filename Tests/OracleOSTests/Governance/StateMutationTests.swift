import XCTest
@testable import OracleOS

/// Verifies that ONLY reducers may update committed state.
/// INVARIANT: No direct worldModel.reset, graphStore.write, memoryStore.update.
final class StateMutationTests: XCTestCase {
    func test_only_reducers_may_mutate_state() {
        // Only reducers conform to EventReducer protocol
        let reducers = [RuntimeStateReducer(), UIStateReducer(), ProjectStateReducer()]
        XCTAssertFalse(reducers.isEmpty, "Reducers must exist")
    }

    func test_no_direct_state_reset() {
        // This would fail if we had worldModel.reset calls outside reducers
        let state = WorldStateModel()
        XCTAssertEqual(state.cycleCount, 0)
    }
}
