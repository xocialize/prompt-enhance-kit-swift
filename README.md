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

## Model profiles (v0.5, structured since v0.6)

Templates are the neutral, model-agnostic layer. A **profile** is one model's enhancer, as data. It holds:
- an instruction per task, with an optional Chinese variant chosen when the brief contains CJK ideographs;
- how to read the answer: text, optionally joined to one line, or JSON, constrained where the backbone supports it, and
  written out compact or indented in the backbone's own key order;
- where a JSON answer names the image's size (`sizeFields`, read into `EnhanceResult.suggestedSize`);
- a suffix;
- when to pass a prompt through as typed;
- the backbone class it needs;
- sampler overrides;
- where its text came from, and under what licence.

`ProfileLibrary` keys profiles by the model ids they serve. `ProfileLibrary.imageModels()` ships the image engine's
text-to-image profiles (AB-D-0155: the prose ones from E1, SenseNova's Render JSON from E3):

| Profile | Models | Policy | Text |
|---|---|---|---|
| `z-image` | z-image-turbo, z-image | optional (the vendor's demo ships it off) | Tongyi's expander, verbatim (Apache-2.0); since v2 a one-sentence user turn of ours asks for prose |
| `qwen-image` | qwen-image-flash | recommended | Qwen-Image's EN/ZH rewriter and suffix, verbatim (Apache-2.0) |
| `flux2-klein` | klein-4b, klein-4b-base | recommended | original, following BFL's guidance (v2: no closing "No text is present.") |
| `mage-flow` | mage-flow, mage-flow-turbo | optional | original |
| `sensenova-u1.5` | sensenova-u1, sensenova-u1-fast, sensenova-u1-fast-v1 | recommended, no word limit | SenseTime's Render JSON enhancer, verbatim (Apache-2.0); `large` backbone, compact JSON, canvas → `suggestedSize` |

**Structured profiles (v0.6, E3).** SenseNova U1.5 reads Render JSON as its prompt: subjects, scene, lighting,
composition, style, camera, the visible copy, a canvas and a negative. The profile asks the backbone for it (constrained
JSON, up to 4,096 tokens), reads the answer from its first `{` to its last `}` as the vendor does, and writes it out
compact in the backbone's key order. Its `canvas` names one of five 2K sizes, which comes back in `suggestedSize`. Pass
`targetSize` when the job has a size, and the profile is told it. On Qwen3.5-9B int4, 8 briefs × 2 seeds all came back
in the vendor's exact format: the eleven keys, a valid canvas row, and every quoted literal in `visible_copy`. That took
23 s per rewrite on average (prompt-enhance-e2e `--structured`).

`mingImage` (Ming-Image's layer JSON, inclusionAI's rewriter verbatim, MIT) is defined but **not shipped** in
`imageModels()`. On the same backbone, only 3 of 12 answers were in its format at temperature 0.7, and 6 of 12 at 0.3:
the backbone anchors layers at their corner rather than their centre. A host with a larger rewriter can register it.

FLUX 3 Klein has no profile: BFL's own upsampler runs inside flux3-klein-swift. The vendor texts' sources are pinned in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

```swift
let library = ProfileLibrary.imageModels()
guard let profile = library.profile(forModel: "qwen-image-flash") else { return }
let result = try await PromptEnhancer(parameters: LLMParameters(temperature: 0.7, maxTokens: 512, seed: jobSeed))
    .enhance(brief, profile: profile, task: .textToImage, mode: .auto, timeout: .seconds(60)) { request in
        (try await engine.run(request) as? LLMResponse)?.text ?? ""
    }
// result.prompt goes to the image model; result.outcome, .profileID/.profileVersion and .original are provenance.
```

A host that loads its backbone on demand can ask first, with no backbone and no I/O (since 0.5.1):

```swift
if let skip = PromptEnhancer.decision(brief, profile: profile, task: .textToImage, mode: .auto) {
    // Goes as typed; `enhance` would return `skip` without calling the backbone. Don't load it.
}
```

What `enhance(_:profile:...)` does:
- **`auto` follows the profile's policy.** `required` always enhances. `recommended` enhances a brief that isn't already
  detailed. `optional` leaves it alone. `always` enhances whenever there's an instruction.
- **A brief that is already JSON** (a layout, Render JSON) always goes through as typed.
- **Vision tasks pass through as typed** (`.needsVision`) until the kit has an image transport.
- **Cancellation propagates.** It rethrows `CancellationError`; the template overloads still answer with the raw
  prompt.
- **Failures fall back to the brief as typed**, with the outcome saying why: an error, an unreadable answer, an empty
  answer, or the `timeout` passing. Enhancement never blocks generation.

## License

MIT; see [LICENSE](LICENSE). The verbatim vendor prompts are Apache-2.0 (Z-Image, Qwen-Image, SenseNova) and MIT
(Ming-Image); see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
