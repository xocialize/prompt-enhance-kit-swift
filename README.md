# prompt-enhance-kit-swift

A backbone-agnostic, cross-engine **prompt enhancer** for MLXEngine — image *and* video.

Prompt enhancement is a portable engine `llm` mode (`Mode.promptEnhance` on `LLMRequest`), so this kit
is **not a model port**: it carries a task-aware **template library** and a thin enhance util that builds
a `.promptEnhance` request and runs it on a caller-supplied runner (which wraps the engine). It depends
only on `MLXToolKit` (the engine contract) — no MLX, no Qwen/Ernie coupling — so any registered `.llm` / VL
package backs it, and its text drives any `textToImage` / `textToVideo` / `characterAnimation` consumer.

## Pieces

- `Mode.promptEnhance` — the canonical mode tag.
- `EnhanceTask` — task keys (`t2i`/`i2i`/`r2i` · `t2v`/`i2v`/`v2v`/`r2v` · `replacement`) + `needsVision`.
- `PromptEnhanceTemplate` / `TemplateLibrary` — templates as editable data, seeded with neutral image +
  video templates; `register` to override with a model-specific profile.
- `PromptEnhancer` — builds the request, runs it on your `Runner`, and **always falls back to the raw
  prompt** (on no template, a thrown error, or an empty result) so enhancement never blocks generation.

## Reproducible enhancement

`PromptEnhancer.parameters` is caller-supplied and forwarded onto the request verbatim, so pinning
the enhancement is pinning the sampler:

```swift
let enhancer = PromptEnhancer(
    library: .ltxVideo(),
    parameters: LLMParameters(temperature: 0.7, maxTokens: 512, seed: 10))  // engine ≥ 0.45.0
```

The default is `LLMParameters(temperature: 0.7, maxTokens: 512)` — sampling on, **seed nil**, which
means the sampler is seeded from system entropy and the same brief returns a different enhancement
every call. That is not a detail: enhancement rewrites the prompt your generation then consumes, so
an unpinned enhancer makes the whole run irreproducible even when the generation seed is fixed —
the video changes because its prompt changed. Measured through the governed Gemma path
(`prompt-enhance-e2e-gemma --seed-gate`): seed 10 reproduces byte-identically across two separate
model loads, seed 4242 diverges at char 24, and two `nil`-seed runs diverge at char 36.

The seed rides the canonical `LLMParameters.seed` (contract 1.33.0) — no per-package `metaData`
dialect, so the same code pins whichever `.llm` package answers. Packages that decode greedily may
ignore it; their output does not vary anyway.

## Use

Engine-backed — any registered `.llm` package answers the request:

```swift
import PromptEnhanceKit
import MLXToolKit

let enhancer = PromptEnhancer()
let rich = await enhancer.enhance(
    "a red fox in snow", capability: .textToVideo, task: .textToVideo
) { req in
    (try await engine.run(req) as? LLMResponse)?.text ?? ""   // your engine wraps the Runner
}
```

Host-provided chat model — **no `.llm` package required.** If the host already carries a
chat-capable text model (e.g. LTX-2's text encoder is instruction-tuned Gemma-3), drive it directly
with the `generate:` overload; the kit hands you the assembled (system, user) turns:

```swift
let rich = await enhancer.enhance(
    "a red fox in snow", capability: .textToVideo, task: .textToVideo,
    targetDuration: 5
) { system, user in
    try await myChatModel.respond(system: system, user: user)   // e.g. mlx-swift-lm ChatSession
}
```

Both transports share the template selection, hint assembly, and the raw-prompt fallback.

> ⚠️ **Never let an enhancer integration force a VLM-capable model package into a host.**
> `mlx-swift-lm`'s model-type registry is process-global and probes VLM factories before LLM ones;
> a linked MLXVLM shadows architectures registered by both (e.g. `gemma3` then resolves to the
> multimodal `Gemma3` instead of `Gemma3TextModel`), breaking hosts that auto-dispatch text models —
> at **link time**, even if enhancement is never invoked. If the host has any text model of its own,
> prefer the `generate:` overload; if you register a backbone package, pick one that links MLXLLM
> only.

The seed templates are neutral, original text (no copied or unlicensed content, no content-policy rules);
register model-tuned profiles for specific backbones as needed (`TemplateLibrary.ltxVideo()` ships the
LTX-2.3 profile).

## License

MIT — see [LICENSE](LICENSE).
