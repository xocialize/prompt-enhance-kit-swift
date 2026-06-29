import MLXToolKit

public extension Mode {
    /// Canonical mode tag for the prompt-enhance surface. `Mode` is a string-backed value
    /// (`ExpressibleByStringLiteral`), so this equals the same `"promptEnhance"` any `.llm`
    /// package keys on — the kit owns the canonical constant so consumers don't restate it.
    static let promptEnhance: Mode = "promptEnhance"
}
