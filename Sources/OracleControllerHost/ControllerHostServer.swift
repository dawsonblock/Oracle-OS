import Foundation
import OracleControllerShared

actor HostOutput {
    private let encoder: JSONEncoder
    private let handle: FileHandle

    init(handle: FileHandle = .standardOutput) {
        self.handle = handle
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
    }

    func send(response: ControllerHostResponse) {
        sendEnvelope(ControllerHostEnvelope(response: response))
    }

    func send(event: ControllerHostEvent) {
        sendEnvelope(ControllerHostEnvelope(event: event))
    }

    private func sendEnvelope(_ envelope: ControllerHostEnvelope) {
        guard let data = try? encoder.encode(envelope) else { return }
        handle.write(data)
        handle.write(Data("\n".utf8))
    }
}

actor ControllerHostServer {
    private let output: HostOutput
    private let bridge: ControllerRuntimeBridge
    private var monitoringTask: Task<Void, Never>?
    private var monitoringConfiguration = MonitoringConfiguration(enabled: false)
    private var lastHealth: HealthStatus?

    init(output: HostOutput, bridge: ControllerRuntimeBridge) {
        self.output = output
        self.bridge = bridge
    }

    func handle(_ request: ControllerHostRequest) async {
        switch request.command {
        case .bootstrap:
            let snapshot = await MainActor.run { bridge.refreshSnapshot(appName: request.appName) }
            let health = await MainActor.run { bridge.healthStatus() }
            lastHealth = health
            let monitoring = monitoringConfiguration
            let bootstrap = await MainActor.run {
                DashboardBootstrap(
                    session: bridge.currentSession(
                        autoRefreshEnabled: monitoring.enabled,
                        appName: request.appName
                    ),
                    snapshot: snapshot,
                    health: health,
                    recipes: bridge.listRecipes(),
                    traceSessions: bridge.listTraceSessions(),
                    approvals: bridge.listApprovalRequests()
                )
            }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                bootstrap: bootstrap
            ))

        case .refreshSnapshot:
            let snapshot = await MainActor.run { bridge.refreshSnapshot(appName: request.appName) }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                snapshot: snapshot
            ))

        case .getHealth:
            let health = await MainActor.run { bridge.healthStatus() }
            lastHealth = health
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                health: health
            ))

        case .performAction:
            guard let action = request.action else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing action payload"
                ))
                return
            }

            let stepCountBefore = await MainActor.run { bridge.recordedStepCount() }
            let monitoring = monitoringConfiguration
            let session = await MainActor.run {
                bridge.currentSession(autoRefreshEnabled: monitoring.enabled, appName: action.appName)
            }
            await output.send(event: ControllerHostEvent(kind: .actionStarted, session: session, message: action.displayTitle))
            let actionResult = await MainActor.run { bridge.performAction(action) }
            let newSteps = await MainActor.run { bridge.recordedSteps(since: stepCountBefore) }
            let approvals = await MainActor.run { bridge.listApprovalRequests() }

            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                actionResult: actionResult,
                approvals: approvals
            ))
            await output.send(event: ControllerHostEvent(kind: .actionCompleted, session: session, action: actionResult))
            await output.send(event: ControllerHostEvent(kind: .approvalsChanged, session: session, approvals: approvals))
            for step in newSteps {
                await output.send(event: ControllerHostEvent(kind: .traceStepAppended, session: session, traceStep: step))
            }

        case .listApprovalRequests:
            let approvals = await MainActor.run { bridge.listApprovalRequests() }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                approvals: approvals
            ))

        case .approveApprovalRequest:
            guard let approvalRequestID = request.approvalRequestID else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing approval request id"
                ))
                return
            }

            do {
                _ = try await MainActor.run { try bridge.approveApprovalRequest(id: approvalRequestID) }
                let approvals = await MainActor.run { bridge.listApprovalRequests() }
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: true,
                    approvals: approvals
                ))
                await output.send(event: ControllerHostEvent(kind: .approvalsChanged, approvals: approvals))
            } catch {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: error.localizedDescription
                ))
            }

        case .rejectApprovalRequest:
            guard let approvalRequestID = request.approvalRequestID else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing approval request id"
                ))
                return
            }

            do {
                try await MainActor.run { try bridge.rejectApprovalRequest(id: approvalRequestID) }
                let approvals = await MainActor.run { bridge.listApprovalRequests() }
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: true,
                    approvals: approvals
                ))
                await output.send(event: ControllerHostEvent(kind: .approvalsChanged, approvals: approvals))
            } catch {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: error.localizedDescription
                ))
            }

        case .listRecipes:
            let recipes = await MainActor.run { bridge.listRecipes() }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                recipes: recipes
            ))

        case .loadRecipe:
            guard let recipeName = request.recipeName else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing recipe name"
                ))
                return
            }

            let recipe = await MainActor.run { bridge.loadRecipe(named: recipeName) }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                recipe: recipe,
                errorMessage: recipe == nil ? "Recipe not found" : nil
            ))

        case .saveRecipe:
            guard let recipe = request.recipe else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing recipe payload"
                ))
                return
            }

            do {
                let saved = try await MainActor.run { try bridge.saveRecipe(recipe) }
                let recipes = await MainActor.run { bridge.listRecipes() }
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    recipe: saved
                ))
                await output.send(event: ControllerHostEvent(kind: .recipesChanged, recipes: recipes))
            } catch {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: error.localizedDescription
                ))
            }

        case .deleteRecipe:
            guard let recipeName = request.recipeName else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing recipe name"
                ))
                return
            }
            let deleted = await MainActor.run { bridge.deleteRecipe(named: recipeName) }
            let recipes = await MainActor.run { bridge.listRecipes() }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                acknowledged: deleted,
                errorMessage: deleted ? nil : "Recipe not found"
            ))
            await output.send(event: ControllerHostEvent(kind: .recipesChanged, recipes: recipes))

        case .runRecipe:
            guard let recipeName = request.recipeName else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing recipe name"
                ))
                return
            }
            let stepCountBefore = await MainActor.run { bridge.recordedStepCount() }
            let monitoring = monitoringConfiguration
            let session = await MainActor.run {
                bridge.currentSession(
                    autoRefreshEnabled: monitoring.enabled,
                    appName: monitoring.appName
                )
            }
            let runResult = await MainActor.run {
                bridge.runRecipe(named: recipeName, params: request.recipeParams ?? [:])
            }
            let newSteps = await MainActor.run { bridge.recordedSteps(since: stepCountBefore) }
            let approvals = await MainActor.run { bridge.listApprovalRequests() }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                recipeRun: runResult,
                approvals: approvals
            ))
            await output.send(event: ControllerHostEvent(kind: .approvalsChanged, session: session, approvals: approvals))
            for step in newSteps {
                await output.send(event: ControllerHostEvent(kind: .traceStepAppended, session: session, traceStep: step))
            }

        case .resumeRecipeRun:
            guard let resumeToken = request.resumeToken else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing resume token"
                ))
                return
            }
            let stepCountBefore = await MainActor.run { bridge.recordedStepCount() }
            let monitoring = monitoringConfiguration
            let session = await MainActor.run {
                bridge.currentSession(
                    autoRefreshEnabled: monitoring.enabled,
                    appName: monitoring.appName
                )
            }
            let runResult = await MainActor.run {
                bridge.resumeRecipe(resumeToken: resumeToken, approvalRequestID: request.approvalRequestID)
            }
            let approvals = await MainActor.run { bridge.listApprovalRequests() }
            let newSteps = await MainActor.run { bridge.recordedSteps(since: stepCountBefore) }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                recipeRun: runResult,
                approvals: approvals
            ))
            await output.send(event: ControllerHostEvent(kind: .approvalsChanged, session: session, approvals: approvals))
            for step in newSteps {
                await output.send(event: ControllerHostEvent(kind: .traceStepAppended, session: session, traceStep: step))
            }

        case .listTraceSessions:
            let traces = await MainActor.run { bridge.listTraceSessions() }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                traceSessions: traces
            ))

        case .loadTraceSession:
            guard let traceSessionID = request.traceSessionID else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing trace session id"
                ))
                return
            }
            let detail = await MainActor.run { bridge.loadTraceSession(id: traceSessionID) }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                traceDetail: detail,
                errorMessage: detail == nil ? "Trace session not found" : nil
            ))

        case .setMonitoring:
            monitoringConfiguration = request.monitoring ?? MonitoringConfiguration(enabled: false)
            restartMonitoringLoop()
            let monitoring = monitoringConfiguration
            let session = await MainActor.run {
                bridge.currentSession(
                    autoRefreshEnabled: monitoring.enabled,
                    appName: monitoring.appName
                )
            }
            let snapshot = await MainActor.run { bridge.refreshSnapshot(appName: monitoring.appName) }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                acknowledged: true
            ))
            await output.send(event: ControllerHostEvent(kind: .observationUpdated, session: session, snapshot: snapshot))

        case .ping:
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                acknowledged: true
            ))
        }
    }

    private func restartMonitoringLoop() {
        monitoringTask?.cancel()
        guard monitoringConfiguration.enabled else { return }

        let monitoring = monitoringConfiguration
        let interval = UInt64(max(250, monitoring.intervalMs)) * 1_000_000
        monitoringTask = Task {
            while !Task.isCancelled {
                let snapshot = await MainActor.run { bridge.refreshSnapshot(appName: monitoring.appName) }
                let health = await MainActor.run { bridge.healthStatus() }
                let session = await MainActor.run {
                    bridge.currentSession(
                        autoRefreshEnabled: monitoring.enabled,
                        appName: monitoring.appName
                    )
                }
                await output.send(event: ControllerHostEvent(kind: .observationUpdated, session: session, snapshot: snapshot))
                if health != lastHealth {
                    lastHealth = health
                    await output.send(event: ControllerHostEvent(kind: .healthChanged, session: session, health: health))
                }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }
}
