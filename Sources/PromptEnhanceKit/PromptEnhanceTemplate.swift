import MLXToolKit

/// A task-aware enhance template: the system instruction handed to the LLM. Templates are DATA
/// (editable, retunable per backbone), not code.
///
/// The seed text below is **neutral, original prompting** that implements the *intent* of the
/// upstream enhancers (cinematic / concrete-visual expansion) — it is NOT a verbatim copy of any
/// source, carries NO content-policy rewrite rules, and reuses no unlicensed text. Consumers can
/// override with a model-specific profile (e.g. a Wan2.2-A14B-tuned set) via `TemplateLibrary`.
public struct PromptEnhanceTemplate: Sendable, Equatable {
    /// The system instruction. The user turn carries the raw brief (+ an optional size hint).
    public let system: String

    public init(system: String) {
        self.system = system
    }
}
