import CryptoKit
import Foundation

public struct PolicyEvaluationContext: Sendable {
    public let surface: RuntimeSurface
    public let toolName: String?
    public let appName: String?

    public init(surface: RuntimeSurface, toolName: String?, appName: String?) {
        self.surface = surface
        self.toolName = toolName
        self.appName = appName
    }
}

public enum PolicyRules {
    public static func appProtectionProfile(for appName: String?) -> AppProtectionProfile {
        let normalized = normalize(appName)

        if blockedApplicationPatterns.contains(where: { normalized.contains($0) }) {
            return .blocked
        }

        if confirmRiskyApplicationPatterns.contains(where: { normalized.contains($0) }) {
            return .confirmRisky
        }

        return .lowRiskAllowed
    }

    public static func protectedOperation(
        for intent: ActionIntent,
        context: PolicyEvaluationContext,
        appProtectionProfile: AppProtectionProfile
    ) -> ProtectedOperation? {
        let action = intent.action.lowercased()
        let target = riskText(for: intent, toolName: context.toolName)
        let appName = normalize(context.appName ?? intent.app)

        if appProtectionProfile == .blocked, action != "focus" {
            if appName.contains("system settings") {
                return .settingsChange
            }
            return .terminalControl
        }

        if target.contains("password")
            || target.contains("passcode")
            || target.contains("otp")
            || target.contains("2fa")
            || target.contains("one-time code")
        {
            return .credentialEntry
        }

        if target.contains("send") || target.contains("submit") || target.contains("publish") {
            return .send
        }

        if target.contains("purchase")
            || target.contains("checkout")
            || target.contains("payment")
            || target.contains("buy")
        {
            return .purchase
        }

        if target.contains("delete")
            || target.contains("trash")
            || target.contains("remove")
            || target.contains("move to trash")
        {
            return .delete
        }

        if target.contains("upload")
            || target.contains("share")
            || target.contains("export")
            || target.contains("download")
        {
            return .uploadShare
        }

        if target.contains("clipboard")
            || (action == "press" && intent.query?.lowercased() == "c" && (intent.role?.lowercased().contains("cmd") == true))
        {
            return .clipboardExfiltration
        }

        if target.contains("system settings")
            || target.contains("privacy")
            || target.contains("security")
            || target.contains("permissions")
        {
            return .settingsChange
        }

        return nil
    }

    public static func actionFingerprint(intent: ActionIntent, toolName: String?) -> String {
        let seed = [
            toolName ?? "runtime",
            intent.app,
            intent.action,
            intent.query ?? "",
            intent.role ?? "",
            intent.domID ?? "",
            coordinateFragment(x: intent.x, y: intent.y),
            redactedTextFragment(intent.text),
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func riskText(for intent: ActionIntent, toolName: String?) -> String {
        [
            toolName,
            intent.query,
            intent.domID,
            intent.role,
            redactText(intent.text),
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private static func coordinateFragment(x: Double?, y: Double?) -> String {
        guard let x, let y else { return "" }
        return "\(Int(x))x\(Int(y))"
    }

    private static func redactedTextFragment(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func redactText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }

        let lowered = text.lowercased()
        if lowered.contains("password")
            || lowered.contains("passcode")
            || lowered.contains("otp")
            || lowered.contains("2fa")
        {
            return "[redacted]"
        }

        return text
    }

    private static func normalize(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static let blockedApplicationPatterns = [
        "terminal",
        "iterm",
        "hyper",
        "system settings",
        "keychain",
        "securityagent",
    ]

    private static let confirmRiskyApplicationPatterns = [
        "chrome",
        "safari",
        "firefox",
        "arc",
        "brave",
        "mail",
        "outlook",
        "slack",
        "messages",
        "finder",
        "notes",
        "textedit",
        "xcode",
        "visual studio code",
        "cursor",
    ]
}
