// MARK: - UICommand
import Foundation

public protocol UICommand: Command {}

public struct ClickElementCommand: UICommand {
    public let id: CommandID
    public let kind = "clickElement"
    public let metadata: CommandMetadata
    public let targetID: String
    public let applicationBundleID: String
    public let query: String?
    public let role: String?
    public let domID: String?
    public let x: Double?
    public let y: Double?
    public let button: String?
    public let count: Int?

    public init(
        id: CommandID = CommandID(),
        metadata: CommandMetadata,
        targetID: String,
        applicationBundleID: String,
        query: String? = nil,
        role: String? = nil,
        domID: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        button: String? = nil,
        count: Int? = nil
    ) {
        self.id = id
        self.metadata = metadata
        self.targetID = targetID
        self.applicationBundleID = applicationBundleID
        self.query = query
        self.role = role
        self.domID = domID
        self.x = x
        self.y = y
        self.button = button
        self.count = count
    }
}

public struct TypeTextCommand: UICommand {
    public let id: CommandID
    public let kind = "typeText"
    public let metadata: CommandMetadata
    public let targetID: String
    public let text: String
    public let applicationBundleID: String
    public let domID: String?
    public let clear: Bool

    public init(
        id: CommandID = CommandID(),
        metadata: CommandMetadata,
        targetID: String,
        text: String,
        applicationBundleID: String = "",
        domID: String? = nil,
        clear: Bool = false
    ) {
        self.id = id
        self.metadata = metadata
        self.targetID = targetID
        self.text = text
        self.applicationBundleID = applicationBundleID
        self.domID = domID
        self.clear = clear
    }
}

public struct FocusWindowCommand: UICommand {
    public let id: CommandID
    public let kind = "focusWindow"
    public let metadata: CommandMetadata
    public let applicationBundleID: String
    public let windowTitle: String?

    public init(
        id: CommandID = CommandID(),
        metadata: CommandMetadata,
        applicationBundleID: String,
        windowTitle: String? = nil
    ) {
        self.id = id
        self.metadata = metadata
        self.applicationBundleID = applicationBundleID
        self.windowTitle = windowTitle
    }
}

public struct ReadElementCommand: UICommand {
    public let id: CommandID
    public let kind = "readElement"
    public let metadata: CommandMetadata
    public let targetID: String
    public let applicationBundleID: String

    public init(
        id: CommandID = CommandID(),
        metadata: CommandMetadata,
        targetID: String,
        applicationBundleID: String = ""
    ) {
        self.id = id
        self.metadata = metadata
        self.targetID = targetID
        self.applicationBundleID = applicationBundleID
    }
}

public struct PressKeyCommand: UICommand {
    public let id: CommandID
    public let kind = "pressKey"
    public let metadata: CommandMetadata
    public let key: String
    public let modifiers: [String]
    public let applicationBundleID: String

    public init(
        id: CommandID = CommandID(),
        metadata: CommandMetadata,
        key: String,
        modifiers: [String] = [],
        applicationBundleID: String = ""
    ) {
        self.id = id
        self.metadata = metadata
        self.key = key
        self.modifiers = modifiers
        self.applicationBundleID = applicationBundleID
    }
}

public struct HotkeyCommand: UICommand {
    public let id: CommandID
    public let kind = "hotkey"
    public let metadata: CommandMetadata
    public let keys: [String]
    public let applicationBundleID: String

    public init(
        id: CommandID = CommandID(),
        metadata: CommandMetadata,
        keys: [String],
        applicationBundleID: String = ""
    ) {
        self.id = id
        self.metadata = metadata
        self.keys = keys
        self.applicationBundleID = applicationBundleID
    }
}

public struct ScrollCommand: UICommand {
    public let id: CommandID
    public let kind = "scrollElement"
    public let metadata: CommandMetadata
    public let direction: String
    public let amount: Int?
    public let applicationBundleID: String
    public let x: Double?
    public let y: Double?

    public init(
        id: CommandID = CommandID(),
        metadata: CommandMetadata,
        direction: String,
        amount: Int? = nil,
        applicationBundleID: String = "",
        x: Double? = nil,
        y: Double? = nil
    ) {
        self.id = id
        self.metadata = metadata
        self.direction = direction
        self.amount = amount
        self.applicationBundleID = applicationBundleID
        self.x = x
        self.y = y
    }
}

public struct ManageWindowCommand: UICommand {
    public let id: CommandID
    public let kind = "manageWindow"
    public let metadata: CommandMetadata
    public let action: String
    public let applicationBundleID: String
    public let windowTitle: String?
    public let x: Double?
    public let y: Double?
    public let width: Double?
    public let height: Double?

    public init(
        id: CommandID = CommandID(),
        metadata: CommandMetadata,
        action: String,
        applicationBundleID: String,
        windowTitle: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) {
        self.id = id
        self.metadata = metadata
        self.action = action
        self.applicationBundleID = applicationBundleID
        self.windowTitle = windowTitle
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
