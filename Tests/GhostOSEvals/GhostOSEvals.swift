import XCTest
@testable import GhostOS

/// Evaluation harness for GhostOS.
/// This module is designed to run benchmark tasks to measure performance and reliability.
@MainActor
final class GhostOSEvals: XCTestCase {

    override func setUp() async throws {
        // Setup initial state for evaluation runs.
        // E.g., ensure test apps are open, AX permissions are granted, etc.
    }

    override func tearDown() async throws {
        // Cleanup after evaluation.
    }

    func testBasicInteraction() async throws {
        // A placeholder for a benchmark task.
        // For example, finding a specific element and clicking it,
        // then measuring time-to-completion, success rate, and tracing fidelity.
        
        let expectation = XCTestExpectation(description: "Basic Interaction Evaluation")
        
        // Simulating the observe->execute->verify loop
        let intent = ActionIntent.click(
            app: "Finder",
            query: "Applications",
            role: nil,
            domID: nil,
            x: nil,
            y: nil,
            button: nil,
            count: nil,
            postconditions: []
        )
        
        let result = VerifiedActionExecutor.run(intent: intent) {
            return ToolResult(success: true, data: ["method": "mocked_for_eval"])
        }
        
        // Assert the evaluation criteria
        XCTAssertTrue(result.success, "Evaluation task should complete successfully")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    func testRecipeInductionFromTrace() throws {
        // Simulates taking a trace recording of a human operator to induce a repeatable recipe
        let t1 = TraceEvent(action: "click _Applications_", success: true, message: nil)
        let t2 = TraceEvent(action: "type \"Safari\" into _Search_", success: true, message: nil)
        let t3 = TraceEvent(action: "click _Safari App_", success: true, message: nil)
        
        let trace = [t1, t2, t3]
        
        // Mock observation
        let observation = Observation(app: "Finder", elements: [])
        
        // Induce recipe
        let recipe = RecipeInducer.induce(name: "Open Safari", trace: trace, observation: observation)
        
        // Validate induction extracted standard steps
        XCTAssertEqual(recipe.name, "Open Safari")
        XCTAssertEqual(recipe.steps.count, 3)
        // Note: induction might parameterize quoted strings if we use them
        XCTAssertEqual(recipe.steps[0].action, "click _Applications_")
        XCTAssertTrue(RecipeValidator.validate(recipe: recipe, state: WorldState(observation: Observation(app: "Finder", elements: []))))
    }
    
    func testVisionSidecarIntegrationMock() async throws {
        // Simulates an evaluation of the Vision Sidecar's endpoint latency and parsing fidelity
        let expectation = XCTestExpectation(description: "Vision Sidecar Integration Evaluation")
        
        // Mocking the result of hitting the `/parse` endpoint of the Python sidecar
        // In reality, this would use a URLSession roundtrip for the Evals framework
        let mockVisionResponse = """
        {
            "status": "success",
            "elements": [
                {"id": "yolo_btn_1", "type": "button", "confidence": 0.95, "x": 100, "y": 200, "width": 50, "height": 20, "source": "yolo"}
            ],
            "count": 1,
            "context": "Screen parsed successfully via vision detectors."
        }
        """
        
        let data = mockVisionResponse.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        
        XCTAssertNotNil(json)
        guard let elements = json?["elements"] as? [[String: Any]] else {
            XCTFail("Vision response missing elements array")
            return
        }
        
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0]["confidence"] as? Double, 0.95)
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
