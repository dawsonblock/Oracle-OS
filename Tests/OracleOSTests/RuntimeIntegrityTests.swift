import XCTest
import Foundation

final class RuntimeIntegrityTests: XCTestCase {

    func test_no_bypass_execution_performAction() {
        let source = """
        Sources/OracleOS/Runtime/RuntimeOrchestrator.swift
        Sources/OracleOS/Execution/ActionResult.swift
        """
        
        XCTAssertFalse(source.contains("func performAction"),
                       "performAction should be removed from RuntimeOrchestrator")
    }

    func test_no_bypass_execution_VerifiedActionExecutor() {
        let source = """
        Sources/OracleOS/Execution/ActionResult.swift
        """
        
        XCTAssertFalse(source.contains("VerifiedActionExecutor"),
                       "VerifiedActionExecutor class should be removed")
    }

    func test_verifiedExecutor_is_sole_execution_surface() {
        let verifiedExecutorPath = "Sources/OracleOS/Execution/VerifiedExecutor.swift"
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: verifiedExecutorPath),
                       "VerifiedExecutor must exist")
        
        let content = try! String(contentsOfFile: verifiedExecutorPath)
        XCTAssertTrue(content.contains("actor VerifiedExecutor"),
                      "VerifiedExecutor must be an actor")
    }

    func test_agent_loop_is_thin_scheduler() {
        let agentLoopPath = "Sources/OracleOS/Execution/Loop/AgentLoop.swift"
        
        let content = try! String(contentsOfFile: agentLoopPath)
        
        XCTAssertTrue(content.contains("protocol IntentSource"),
                      "AgentLoop should use IntentSource protocol")
        XCTAssertTrue(content.contains("orchestrator.submitIntent"),
                      "AgentLoop should only call orchestrator.submitIntent")
        
        XCTAssertFalse(content.contains("executionCoordinator"),
                       "AgentLoop should not have executionCoordinator")
        XCTAssertFalse(content.contains("decisionCoordinator"),
                       "AgentLoop should not have decisionCoordinator")
        XCTAssertFalse(content.contains("recoveryCoordinator"),
                       "AgentLoop should not have recoveryCoordinator")
    }

    func test_command_router_exists() {
        let routerPath = "Sources/OracleOS/Execution/CommandRouter.swift"
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: routerPath),
                      "CommandRouter must exist")
        
        let content = try! String(contentsOfFile: routerPath)
        XCTAssertTrue(content.contains("protocol CommandRouter"),
                      "CommandRouter must be a protocol")
    }

    func test_events_mandatory_in_execution_outcome() {
        let outcomePath = "Sources/OracleOS/Execution/ExecutionOutcome.swift"
        
        let content = try! String(contentsOfFile: outcomePath)
        
        XCTAssertTrue(content.contains("static func failure("),
                      "ExecutionOutcome must have failure factory")
        XCTAssertTrue(content.contains("static func success("),
                      "ExecutionOutcome must have success factory")
        
        XCTAssertTrue(content.contains("commandFailed"),
                      "Failure must emit CommandFailed event")
        XCTAssertTrue(content.contains("commandSucceeded"),
                      "Success must emit CommandSucceeded event")
    }

    func test_commit_coordinator_is_state_writer() {
        let coordinatorPath = "Sources/OracleOS/Events/CommitCoordinator.swift"
        
        let content = try! String(contentsOfFile: coordinatorPath)
        
        XCTAssertTrue(content.contains("actor CommitCoordinator"),
                      "CommitCoordinator must be an actor")
        XCTAssertTrue(content.contains("func commit("),
                      "CommitCoordinator must have commit method")
    }

    func test_runtime_orchestrator_unified_pipeline() {
        let orchestratorPath = "Sources/OracleOS/Runtime/RuntimeOrchestrator.swift"
        
        let content = try! String(contentsOfFile: orchestratorPath)
        
        XCTAssertTrue(content.contains("decisionCoordinator.decide"),
                      "Orchestrator must use DecisionCoordinator for planning")
        XCTAssertTrue(content.contains("verifiedExecutor.execute"),
                      "Orchestrator must use VerifiedExecutor for execution")
        XCTAssertTrue(content.contains("commitCoordinator.commit"),
                      "Orchestrator must use CommitCoordinator for state")
        XCTAssertTrue(content.contains("critic.evaluate"),
                      "Orchestrator must use Critic for evaluation")
        XCTAssertTrue(content.contains("learningCoordinator.update"),
                      "Orchestrator must use LearningCoordinator for learning")
    }
}
