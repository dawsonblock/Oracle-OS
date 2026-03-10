public enum Postcondition: Codable, Sendable {

    case elementFocused(String)
    case elementValueEquals(String, String)
    case elementAppeared(String)
    case elementDisappeared(String)

    public enum Kind: String, Codable, Sendable {
        case elementFocused = "element_focused"
        case elementValueEquals = "element_value_equals"
        case elementAppeared = "element_appeared"
        case elementDisappeared = "element_disappeared"
    }

    public var kind: Kind {
        switch self {
        case .elementFocused: return .elementFocused
        case .elementValueEquals: return .elementValueEquals
        case .elementAppeared: return .elementAppeared
        case .elementDisappeared: return .elementDisappeared
        }
    }

    public var target: String {
        switch self {
        case .elementFocused(let id): return id
        case .elementValueEquals(let id, _): return id
        case .elementAppeared(let id): return id
        case .elementDisappeared(let id): return id
        }
    }

    public var expected: String? {
        switch self {
        case .elementValueEquals(_, let value): return value
        default: return nil
        }
    }
}
