import AppKit
import Foundation
import Observation
import OracleControllerShared

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case control
    case recipes
    case traces
    case health
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .control: return "Control"
        case .recipes: return "Recipes"
        case .traces: return "Traces"
        case .health: return "Health"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .control: return "switch.2"
        case .recipes: return "text.badge.checkmark"
        case .traces: return "waveform.path.ecg.rectangle"
        case .health: return "cross.case"
        case .settings: return "slider.horizontal.3"
        }
    }
}

enum RecipeEditorMode: String, CaseIterable, Identifiable {
    case form
    case raw

    var id: String { rawValue }
}

struct ActionComposer {
    var kind: ActionKind = .focus
    var appName = ""
    var windowTitle = ""
    var query = ""
    var role = ""
    var domID = ""
    var text = ""
    var clearExisting = false
    var x = ""
    var y = ""
    var button = "left"
    var count = "1"
    var key = ""
    var modifiers = ""
    var direction = "down"
    var amount = "3"
    var waitCondition = "appFrontmost"
    var waitValue = ""
    var timeout = "10"
    var interval = "0.5"

    func makeRequest() -> ActionRequest {
        ActionRequest(
            kind: kind,
            appName: trimmedOrNil(appName),
            windowTitle: trimmedOrNil(windowTitle),
            query: trimmedOrNil(query),
            role: trimmedOrNil(role),
            domID: trimmedOrNil(domID),
            text: trimmedOrNil(text),
            clearExisting: clearExisting,
            x: doubleOrNil(x),
            y: doubleOrNil(y),
            button: trimmedOrNil(button),
            count: intOrNil(count),
            key: trimmedOrNil(key),
            modifiers: parsedModifiers,
            direction: trimmedOrNil(direction),
            amount: intOrNil(amount),
            waitCondition: trimmedOrNil(waitCondition),
            waitValue: trimmedOrNil(waitValue),
            timeout: doubleOrNil(timeout),
            interval: doubleOrNil(interval)
        )
    }

    mutating func hydrate(from snapshot: ControlSnapshot?) {
        guard let appName = snapshot?.observation.appName else { return }
        if self.appName.isEmpty {
            self.appName = appName
        }
    }

    private var parsedModifiers: [String]? {
        let values = modifiers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func doubleOrNil(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func intOrNil(_ value: String) -> Int? {
        Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

@MainActor
@Observable
final class ControllerStore {
    var selectedSection: WorkspaceSection = .control
    var session: ControllerSession?
    var snapshot: ControlSnapshot?
    var health: HealthStatus?
    var recipes: [RecipeDocument] = []
    var traceSessions: [TraceSessionSummary] = []
    var traceDetail: TraceSessionDetail?
    var approvalQueue: [ApprovalRequestDocument] = []
    var currentActionResult: ActionRunResult?
    var recentActions: [ActionRunResult] = []
    var latestRecipeRun: RecipeRunResultDocument?

    var selectedElementID: String?
    var selectedRecipeName: String?
    var selectedTraceSessionID: String?
    var selectedTraceStepID: String?

    var actionComposer = ActionComposer()
    var recipeEditorMode: RecipeEditorMode = .form
    var draftRecipe = RecipeDocument(
        name: "new-recipe",
        description: "Operator workflow",
        steps: [RecipeStepDocument(id: 1, action: "focus")]
    )
    var rawRecipeText = ""
    var recipeRunParameters: [String: String] = [:]

    var monitorAppName = ""
    var autoRefreshEnabled = true
    var isBusy = false
    var isLoaded = false

    var errorMessage: String?
    var inlineMessage: String?

    var recipeSearchText = ""
    var traceSearchText = ""
    var elementSearchText = ""

    private var hostClient: HostProcessClient?

    var filteredElements: [ElementSnapshot] {
        let elements = snapshot?.observation.elements ?? []
        let query = elementSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return elements }
        return elements.filter {
            $0.label?.lowercased().contains(query) == true
                || $0.role?.lowercased().contains(query) == true
                || $0.value?.lowercased().contains(query) == true
        }
    }

    var filteredRecipes: [RecipeDocument] {
        let query = recipeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return recipes }
        return recipes.filter {
            $0.name.lowercased().contains(query)
                || $0.description.lowercased().contains(query)
                || ($0.app?.lowercased().contains(query) ?? false)
        }
    }

    var filteredTraceSessions: [TraceSessionSummary] {
        let query = traceSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return traceSessions }
        return traceSessions.filter { $0.id.lowercased().contains(query) }
    }

    var selectedElement: ElementSnapshot? {
        if let selectedElementID {
            return snapshot?.observation.elements.first(where: { $0.id == selectedElementID })
        }

        if let focusedElementID = snapshot?.observation.focusedElementID {
            return snapshot?.observation.elements.first(where: { $0.id == focusedElementID })
        }

        return snapshot?.observation.elements.first
    }

    var selectedTraceStep: TraceStepViewModel? {
        guard let selectedTraceStepID else { return traceDetail?.steps.first }
        return traceDetail?.steps.first(where: { $0.id == selectedTraceStepID })
    }

    init() {
        self.hostClient = HostProcessClient { [weak self] event in
            self?.handle(event)
        }
    }

    func start() async {
        guard !isLoaded else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let response = try await send(.init(command: .bootstrap, appName: monitorAppName.nilIfBlank))
            applyBootstrap(response.bootstrap)
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshNow() async {
        do {
            let response = try await send(.init(command: .refreshSnapshot, appName: currentMonitorApp))
            if let snapshot = response.snapshot {
                apply(snapshot: snapshot)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshHealth() async {
        do {
            let response = try await send(.init(command: .getHealth))
            if let health = response.health {
                self.health = health
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateMonitoring() async {
        do {
            _ = try await send(
                .init(
                    command: .setMonitoring,
                    monitoring: MonitoringConfiguration(
                        enabled: autoRefreshEnabled,
                        appName: currentMonitorApp,
                        intervalMs: 1000
                    )
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitAction() async {
        let request = actionComposer.makeRequest()
        await performAction(request)
    }

    func loadApprovalRequests() async {
        do {
            let response = try await send(.init(command: .listApprovalRequests))
            if let approvals = response.approvals {
                approvalQueue = approvals
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func approveApprovalRequest(_ approval: ApprovalRequestDocument) async {
        do {
            let response = try await send(.init(command: .approveApprovalRequest, approvalRequestID: approval.id))
            if let approvals = response.approvals {
                approvalQueue = approvals
            }
            if let pendingAction = currentActionResult,
               pendingAction.approvalStatus == "pending",
               pendingAction.approvalRequestID == approval.id
            {
                await performAction(requestForApprovedAction(from: pendingAction.request, approvalRequestID: approval.id))
                return
            }
            if latestRecipeRun?.paused == true,
               latestRecipeRun?.pendingApprovalRequestID == approval.id,
               let resumeToken = latestRecipeRun?.resumeToken
            {
                await resumeRecipeRun(resumeToken: resumeToken, approvalRequestID: approval.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rejectApprovalRequest(_ approval: ApprovalRequestDocument) async {
        do {
            let response = try await send(.init(command: .rejectApprovalRequest, approvalRequestID: approval.id))
            if let approvals = response.approvals {
                approvalQueue = approvals
            }
            if latestRecipeRun?.pendingApprovalRequestID == approval.id {
                inlineMessage = "Recipe approval rejected."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRecipes() async {
        do {
            let response = try await send(.init(command: .listRecipes))
            if let recipes = response.recipes {
                self.recipes = recipes
                syncSelectionAfterRecipeRefresh()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectRecipe(named name: String) async {
        do {
            let response = try await send(.init(command: .loadRecipe, recipeName: name))
            guard let recipe = response.recipe else {
                errorMessage = response.errorMessage ?? "Recipe not found"
                return
            }

            apply(recipe: recipe)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createRecipe() {
        let baseName = "untitled-recipe-\(Int(Date().timeIntervalSince1970))"
        draftRecipe = RecipeDocument(
            name: baseName,
            description: "Describe the workflow.",
            app: snapshot?.observation.appName,
            params: [:],
            preconditions: RecipePreconditionsDocument(appRunning: snapshot?.observation.appName),
            steps: [RecipeStepDocument(id: 1, action: "focus")]
        )
        rawRecipeText = ""
        selectedRecipeName = nil
        recipeRunParameters = [:]
        recipeEditorMode = .form
        selectedSection = .recipes
    }

    func duplicateSelectedRecipe() {
        var copy = draftRecipe
        copy.name = "\(draftRecipe.name)-copy"
        copy.rawJSON = nil
        draftRecipe = copy
        rawRecipeText = ""
        selectedRecipeName = nil
        recipeEditorMode = .form
    }

    func addRecipeStep() {
        let nextID = (draftRecipe.steps.map(\.id).max() ?? 0) + 1
        draftRecipe.steps.append(RecipeStepDocument(id: nextID, action: "click"))
    }

    func removeRecipeStep(id: Int) {
        draftRecipe.steps.removeAll { $0.id == id }
        if draftRecipe.steps.isEmpty {
            addRecipeStep()
        }
    }

    func addRecipeParam() {
        let nextIndex = (draftRecipe.params?.count ?? 0) + 1
        let name = "param\(nextIndex)"
        var params = draftRecipe.params ?? [:]
        params[name] = RecipeParamDocument(id: name, type: "string", description: "Parameter", required: true)
        draftRecipe.params = params
    }

    func removeRecipeParam(id: String) {
        draftRecipe.params?.removeValue(forKey: id)
    }

    func saveDraftRecipe() async {
        if recipeEditorMode == .raw {
            if rawRecipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Raw recipe JSON is empty."
                return
            }
            draftRecipe.rawJSON = rawRecipeText
        } else {
            draftRecipe.rawJSON = nil
        }

        if let validationError = validateDraftRecipe() {
            errorMessage = validationError
            return
        }

        do {
            let response = try await send(.init(command: .saveRecipe, recipe: draftRecipe))
            guard let recipe = response.recipe else {
                errorMessage = response.errorMessage ?? "Save failed"
                return
            }
            inlineMessage = "Saved \(recipe.name)"
            await loadRecipes()
            apply(recipe: recipe)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelectedRecipe() async {
        guard let selectedRecipeName else { return }
        do {
            let response = try await send(.init(command: .deleteRecipe, recipeName: selectedRecipeName))
            guard response.acknowledged else {
                errorMessage = response.errorMessage ?? "Delete failed"
                return
            }
            inlineMessage = "Deleted \(selectedRecipeName)"
            await loadRecipes()
            createRecipe()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runSelectedRecipe() async {
        let recipeName = selectedRecipeName ?? draftRecipe.name
        let params = recipeRunParameters.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[entry.key] = entry.value
        }

        do {
            isBusy = true
            defer { isBusy = false }
            let response = try await send(.init(command: .runRecipe, recipeName: recipeName, recipeParams: params))
            if let recipeRun = response.recipeRun {
                latestRecipeRun = recipeRun
                inlineMessage = recipeRun.paused ? "Recipe paused pending approval." : (recipeRun.success ? "Recipe completed." : "Recipe failed.")
                if let approvals = response.approvals {
                    approvalQueue = approvals
                }
                await loadTraceSessions()
                if let traceSessionID = recipeRun.traceSessionID {
                    await loadTraceSession(id: traceSessionID)
                }
            } else {
                errorMessage = response.errorMessage ?? "Recipe run failed"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTraceSessions() async {
        do {
            let response = try await send(.init(command: .listTraceSessions))
            if let traceSessions = response.traceSessions {
                self.traceSessions = traceSessions
                if selectedTraceSessionID == nil {
                    selectedTraceSessionID = traceSessions.first?.id
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTraceSession(id: String) async {
        do {
            let response = try await send(.init(command: .loadTraceSession, traceSessionID: id))
            guard let traceDetail = response.traceDetail else {
                errorMessage = response.errorMessage ?? "Trace not found"
                return
            }
            self.traceDetail = traceDetail
            self.selectedTraceSessionID = id
            self.selectedTraceStepID = traceDetail.steps.first?.id
            self.selectedSection = .traces
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openArtifact(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func revealArtifact(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func send(_ request: ControllerHostRequest) async throws -> ControllerHostResponse {
        guard let hostClient else {
            throw HostClientError.hostExited
        }
        return try await hostClient.send(request)
    }

    private func performAction(_ request: ActionRequest) async {
        do {
            isBusy = true
            defer { isBusy = false }
            let response = try await send(.init(command: .performAction, action: request))
            if let result = response.actionResult {
                record(result)
                if let resultingObservation = result.resultingObservation {
                    snapshot = ControlSnapshot(
                        capturedAt: Date(),
                        observation: resultingObservation,
                        screenshot: snapshot?.screenshot
                    )
                    selectedElementID = resultingObservation.focusedElementID
                }
                inlineMessage = result.approvalStatus == "pending"
                    ? (result.message ?? "Action pending approval.")
                    : (result.success ? (result.message ?? "Action completed.") : (result.message ?? "Action failed."))
                if let approvals = response.approvals {
                    approvalQueue = approvals
                }
            } else {
                errorMessage = response.errorMessage ?? "Action failed"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ event: ControllerHostEvent) {
        switch event.kind {
        case .actionStarted:
            isBusy = true
            inlineMessage = event.message
            session = event.session ?? session

        case .actionCompleted:
            isBusy = false
            session = event.session ?? session
            if let action = event.action {
                record(action)
            }

        case .observationUpdated:
            session = event.session ?? session
            if let snapshot = event.snapshot {
                apply(snapshot: snapshot)
            }

        case .traceStepAppended:
            if let traceStep = event.traceStep {
                append(traceStep)
            }

        case .healthChanged:
            session = event.session ?? session
            if let health = event.health {
                self.health = health
            }

        case .recipesChanged:
            if let recipes = event.recipes {
                self.recipes = recipes
                syncSelectionAfterRecipeRefresh()
            }

        case .approvalsChanged:
            if let approvals = event.approvals {
                approvalQueue = approvals
            }
        }
    }

    private func applyBootstrap(_ bootstrap: DashboardBootstrap?) {
        guard let bootstrap else { return }
        session = bootstrap.session
        snapshot = bootstrap.snapshot
        health = bootstrap.health
        recipes = bootstrap.recipes
        traceSessions = bootstrap.traceSessions
        approvalQueue = bootstrap.approvals
        selectedElementID = bootstrap.snapshot?.observation.focusedElementID
        actionComposer.hydrate(from: bootstrap.snapshot)
        if monitorAppName.isEmpty {
            monitorAppName = bootstrap.session.activeAppName ?? bootstrap.snapshot?.observation.appName ?? ""
        }
        if selectedRecipeName == nil, let recipe = bootstrap.recipes.first {
            apply(recipe: recipe)
        }
        if selectedTraceSessionID == nil {
            selectedTraceSessionID = bootstrap.traceSessions.first?.id
        }
    }

    private func apply(snapshot: ControlSnapshot) {
        self.snapshot = snapshot
        selectedElementID = snapshot.observation.focusedElementID ?? selectedElementID
        actionComposer.hydrate(from: snapshot)
    }

    private func apply(recipe: RecipeDocument) {
        selectedRecipeName = recipe.name
        draftRecipe = recipe
        rawRecipeText = recipe.rawJSON ?? ""
        recipeRunParameters = recipe.params?.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[entry.key] = partialResult[entry.key] ?? ""
        } ?? [:]
    }

    private func append(_ traceStep: TraceStepViewModel) {
        if traceSessions.contains(where: { $0.id == traceStep.sessionID }) {
            traceSessions = traceSessions.map {
                if $0.id == traceStep.sessionID {
                    return TraceSessionSummary(id: $0.id, stepCount: $0.stepCount + 1, lastUpdated: traceStep.timestamp)
                }
                return $0
            }.sorted { ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast) }
        } else {
            traceSessions.insert(
                TraceSessionSummary(id: traceStep.sessionID, stepCount: 1, lastUpdated: traceStep.timestamp),
                at: 0
            )
        }

        if selectedTraceSessionID == traceStep.sessionID {
            if traceDetail == nil {
                let summary = TraceSessionSummary(id: traceStep.sessionID, stepCount: 1, lastUpdated: traceStep.timestamp)
                traceDetail = TraceSessionDetail(summary: summary, steps: [traceStep])
            } else {
                let existingSteps = (traceDetail?.steps ?? []) + [traceStep]
                let summary = TraceSessionSummary(
                    id: traceStep.sessionID,
                    stepCount: existingSteps.count,
                    lastUpdated: traceStep.timestamp
                )
                traceDetail = TraceSessionDetail(summary: summary, steps: existingSteps)
            }
            selectedTraceStepID = traceStep.id
        }
    }

    private func record(_ action: ActionRunResult) {
        currentActionResult = action

        if recentActions.contains(where: { $0.id == action.id }) {
            return
        }

        recentActions.insert(action, at: 0)
        if recentActions.count > 8 {
            recentActions = Array(recentActions.prefix(8))
        }
    }

    private func syncSelectionAfterRecipeRefresh() {
        guard let selectedRecipeName else { return }
        if let refreshed = recipes.first(where: { $0.name == selectedRecipeName }) {
            if self.selectedRecipeName == draftRecipe.name {
                apply(recipe: refreshed)
            }
        } else {
            self.selectedRecipeName = nil
        }
    }

    private func validateDraftRecipe() -> String? {
        if recipeEditorMode == .raw {
            return nil
        }

        if draftRecipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Recipe name is required."
        }
        if draftRecipe.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Recipe description is required."
        }
        if draftRecipe.steps.isEmpty {
            return "At least one recipe step is required."
        }
        return nil
    }

    private var currentMonitorApp: String? {
        monitorAppName.nilIfBlank
    }

    private func requestForApprovedAction(from request: ActionRequest, approvalRequestID: String) -> ActionRequest {
        ActionRequest(
            kind: request.kind,
            appName: request.appName,
            windowTitle: request.windowTitle,
            query: request.query,
            role: request.role,
            domID: request.domID,
            text: request.text,
            clearExisting: request.clearExisting,
            x: request.x,
            y: request.y,
            button: request.button,
            count: request.count,
            key: request.key,
            modifiers: request.modifiers,
            direction: request.direction,
            amount: request.amount,
            waitCondition: request.waitCondition,
            waitValue: request.waitValue,
            timeout: request.timeout,
            interval: request.interval,
            approvalRequestID: approvalRequestID
        )
    }

    private func resumeRecipeRun(resumeToken: String, approvalRequestID: String) async {
        do {
            let response = try await send(
                .init(
                    command: .resumeRecipeRun,
                    approvalRequestID: approvalRequestID,
                    resumeToken: resumeToken
                )
            )
            if let recipeRun = response.recipeRun {
                latestRecipeRun = recipeRun
                inlineMessage = recipeRun.paused ? "Recipe still pending approval." : (recipeRun.success ? "Recipe completed." : "Recipe failed.")
            }
            if let approvals = response.approvals {
                approvalQueue = approvals
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
