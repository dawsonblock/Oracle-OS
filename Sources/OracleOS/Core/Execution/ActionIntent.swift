public struct ActionIntent: Sendable, Codable {

    public let app: String
    public let name: String
    public let action: String
    public let query: String?
    public let text: String?
    public let role: String?
    public let domID: String?
    public let x: Double?
    public let y: Double?
    public let button: String?
    public let count: Int?
    public let postconditions: [Postcondition]

    public var elementID: String? { domID }
    public var targetQuery: String? { query }

    public init(
        app: String,
        name: String? = nil,
        action: String,
        query: String? = nil,
        text: String? = nil,
        role: String? = nil,
        domID: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        button: String? = nil,
        count: Int? = nil,
        postconditions: [Postcondition] = []
    ) {
        self.app = app
        self.name = name ?? "\(action) \(query ?? "")"
        self.action = action
        self.query = query
        self.text = text
        self.role = role
        self.domID = domID
        self.x = x
        self.y = y
        self.button = button
        self.count = count
        self.postconditions = postconditions
    }
    public static func click(
        app: String?,
        query: String? = nil,
        role: String? = nil,
        domID: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        button: String? = nil,
        count: Int? = nil,
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            app: app ?? "unknown",
            name: "click \(query ?? domID ?? "")",
            action: "click",
            query: query,
            text: nil,
            role: role,
            domID: domID,
            x: x,
            y: y,
            button: button,
            count: count,
            postconditions: postconditions
        )
    }

    public static func type(
        app: String?,
        into: String? = nil,
        domID: String? = nil,
        text: String,
        clear: Bool = false,
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            app: app ?? "unknown",
            name: "type into \(into ?? domID ?? "")",
            action: "type",
            query: into,
            text: text,
            domID: domID,
            postconditions: postconditions
        )
    }

    public static func focus(
        app: String,
        windowTitle: String? = nil,
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            app: app,
            name: "focus \(app)",
            action: "focus",
            query: windowTitle ?? app,
            text: nil,
            postconditions: postconditions
        )
    }

    public static func press(
        app: String?,
        key: String,
        modifiers: [String]? = nil,
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            app: app ?? "unknown",
            name: "press \(modifiers.map { $0.joined(separator: "+") + "+" } ?? "")\(key)",
            action: "press",
            query: key,
            text: nil,
            role: modifiers?.joined(separator: "+"),
            postconditions: postconditions
        )
    }
}
