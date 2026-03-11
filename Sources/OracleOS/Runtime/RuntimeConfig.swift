import Foundation

public struct RuntimeConfig: Sendable {
    public let policyMode: PolicyMode
    public let approvalRequiredSurfaces: Set<RuntimeSurface>
    public let blockedApplications: [String]
    public let protectedOperations: Set<ProtectedOperation>
    public let traceDirectory: URL
    public let recipesDirectory: URL
    public let controllerApprovalRequiredForRiskyActions: Bool
    public let approvalsDirectory: URL
    public let projectMemoryDirectory: URL
    public let experimentsDirectory: URL

    public init(
        policyMode: PolicyMode,
        approvalRequiredSurfaces: Set<RuntimeSurface>,
        blockedApplications: [String],
        protectedOperations: Set<ProtectedOperation>,
        traceDirectory: URL,
        recipesDirectory: URL,
        controllerApprovalRequiredForRiskyActions: Bool,
        approvalsDirectory: URL,
        projectMemoryDirectory: URL,
        experimentsDirectory: URL
    ) {
        self.policyMode = policyMode
        self.approvalRequiredSurfaces = approvalRequiredSurfaces
        self.blockedApplications = blockedApplications
        self.protectedOperations = protectedOperations
        self.traceDirectory = traceDirectory
        self.recipesDirectory = recipesDirectory
        self.controllerApprovalRequiredForRiskyActions = controllerApprovalRequiredForRiskyActions
        self.approvalsDirectory = approvalsDirectory
        self.projectMemoryDirectory = projectMemoryDirectory
        self.experimentsDirectory = experimentsDirectory
    }

    public static func live(policyMode: PolicyMode? = nil) -> RuntimeConfig {
        RuntimeConfig(
            policyMode: policyMode ?? PolicyEngine.defaultMode(),
            approvalRequiredSurfaces: [.controller, .mcp, .cli, .recipe],
            blockedApplications: ["Terminal", "iTerm", "Hyper", "System Settings", "Keychain Access"],
            protectedOperations: Set(ProtectedOperation.allCases),
            traceDirectory: TraceStore.traceRootDirectory(),
            recipesDirectory: URL(
                fileURLWithPath: NSString(string: GhostConstants.recipesDirectory).expandingTildeInPath,
                isDirectory: true
            ),
            controllerApprovalRequiredForRiskyActions: true,
            approvalsDirectory: URL(
                fileURLWithPath: NSString(string: GhostConstants.approvalsDirectory).expandingTildeInPath,
                isDirectory: true
            ),
            projectMemoryDirectory: URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            ).appendingPathComponent("ProjectMemory", isDirectory: true),
            experimentsDirectory: URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            ).appendingPathComponent(".oracle/experiments", isDirectory: true)
        )
    }
}
