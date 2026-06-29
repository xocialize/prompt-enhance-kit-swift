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

## Use

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

The seed templates are neutral, original text (no copied or unlicensed content, no content-policy rules);
register model-tuned profiles for specific backbones as needed.

## License

MIT — see [LICENSE](LICENSE).
