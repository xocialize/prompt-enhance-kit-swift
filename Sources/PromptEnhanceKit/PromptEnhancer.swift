import MLXToolKit

/// Builds a `.promptEnhance` `LLMRequest` from a task template and runs it on a caller-supplied
/// `Runner` (which wraps the engine — so the kit stays backbone/engine-agnostic, depending only on
/// `MLXToolKit`). It ALWAYS falls back to the raw prompt — on a missing template, a thrown error,
/// or an empty result — because enhancement is strictly optional and must never block generation.
///
/// Usage (the runner wraps `engine.run`):
/// ```swift
/// let enhancer = PromptEnhancer()
/// let rich = await enhancer.enhance(brief, capability: .textToVideo, task: .textToVideo) { req in
///     (try await engine.run(req) as? LLMResponse)?.text ?? ""
/// }
/// ```
public struct PromptEnhancer: Sendable {
    public let library: TemplateLibrary
    public var parameters: LLMParameters

    public init(library: TemplateLibrary = TemplateLibrary(),
                parameters: LLMParameters = LLMParameters(temperature: 0.7, maxTokens: 512)) {
        self.library = library
        self.parameters = parameters
    }

    /// "Run an `LLMRequest`, return its text." Wraps whatever drives the engine.
    public typealias Runner = @Sendable (LLMRequest) async throws -> String

    /// Enhance `prompt` for `(capability, task)`. Returns the enhanced text, or `prompt` unchanged
    /// when there is no template, the runner throws, or the result is empty.
    public func enhance(_ prompt: String,
                        capability: Capability,
                        task: EnhanceTask,
                        targetSize: (width: Int, height: Int)? = nil,
                        run: Runner) async -> String {
        guard let template = library.template(for: capability, task: task) else { return prompt }
        let request = makeRequest(prompt, template: template, targetSize: targetSize)
        do {
            let text = try await run(request).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? prompt : text
        } catch {
            return prompt
        }
    }

    /// The exact `.promptEnhance` request the enhancer would run — exposed for inspection/testing.
    /// The size hint rides the user turn (backbone-agnostic) rather than `metaData`, so any `.llm`
    /// package honors it without knowing a package-specific convention.
    public func makeRequest(_ prompt: String,
                            template: PromptEnhanceTemplate,
                            targetSize: (width: Int, height: Int)? = nil) -> LLMRequest {
        var user = prompt
        if let s = targetSize { user += "\n\nTarget resolution: \(s.width)x\(s.height)." }
        return LLMRequest(
            messages: [
                ChatMessage(role: .system, content: template.system),
                ChatMessage(role: .user, content: user),
            ],
            parameters: parameters,
            mode: .promptEnhance)
    }
}
