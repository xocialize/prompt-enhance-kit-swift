# Third-party notices

The kit is MIT-licensed (`LICENSE`). Five model profiles carry vendor prompt text verbatim: four under the Apache License
2.0 (`LICENSES/Apache-2.0.txt`), and Ming-Image's under the MIT License (`LICENSES/MIT-Ming-Image.txt`). All are in
`Sources/PromptEnhanceKit/VendorPrompts.swift`, extracted mechanically from the pinned sources below. One vendor script,
MOSS-Image's layout compiler, is ported to Swift (`Sources/PromptEnhanceKit/MOSSLayout.swift`), under Apache-2.0.

## Z-Image prompt expander

- Source: https://huggingface.co/spaces/Tongyi-MAI/Z-Image-Turbo at commit `768cb50d847cdbba97c89533ae976be69cf5a5b8`,
  file `pe.py` (`prompt_template`).
- Licence: Apache-2.0 (the Space's declared licence). Copyright Tongyi-MAI (Alibaba).
- Used by: `ImageModelProfiles.zImage`.
- Changes: none to the text. The vendor sends a single space as the user turn; since profile v2 (kit 0.5.1) the profile
  sends one sentence of the kit's own there (`ImageModelProfiles.zImageNudge`, MIT; `zImageNudgeChinese` for a brief
  with CJK ideographs), asking for prose in the brief's language and only what is in the image. It's recorded in the
  profile's `source.adaptation`.

## Qwen-Image prompt rewriter

- Source: https://github.com/QwenLM/Qwen-Image at commit `3453042c9f35f284abce58c68302a1183f6b40f2`, file
  `src/examples/tools/prompt_utils.py` (`polish_prompt_en`, `polish_prompt_zh`: their `SYSTEM_PROMPT` and
  `magic_prompt`).
- Licence: Apache-2.0 (the repository's licence). Copyright the Qwen team (Alibaba).
- Used by: `ImageModelProfiles.qwenImage`.
- Changes: none to the text. The English quality suffix is joined to the rewrite with a space; the vendor appends it
  directly.

## SenseNova U1.5 image prompt enhancer

- Source: https://github.com/OpenSenseNova/SenseNova-U1 at commit `a62fd54afed7a8d4c1cb4e10f0c39253d1be6fde`, file
  `src/sensenova_u1_5/image_pe.py` (`IMAGE_PE_SYSTEM_PROMPT`). The text's SHA-256 is
  `f2229c6a22d04de0e6aa92cd5eb76484188a7295c1801df095b5990dc2748c44`.
- Licence: Apache-2.0 (the repository's licence; it has no NOTICE file and no copyright line). Published by OpenSenseNova.
- Used by: `ImageModelProfiles.senseNova`.
- Changes: none to the text. The vendor sends it as the Responses API's `instructions`, with the brief as `input`. Here
  they are the system and user turns. Its optional web-search addition isn't used.

## Ming-Image text-to-image rewriter

- Source: https://github.com/inclusionAI/Ming-Image at commit `578e21e081a7cd385b6c79e36df7e419155681b1`, file
  `assets/t2i_rewriter_system_prompt.txt`, without the file's final newline. The text's SHA-256 is
  `dd47af60155dfb8187b1fb4e915362b6d6e3d7b01c213167fbaf12c322613fbf`.
- Licence: MIT, Copyright (c) 2026 inclusionAI. The licence text is in `LICENSES/MIT-Ming-Image.txt`.
- Used by: `ImageModelProfiles.mingImage`, which isn't in the shipped library (see the README).
- Changes: none to the text. It is sent as the system turn, with the brief as the user turn.

## MOSS-Image prompt-enhancer skill and layout compiler

- Source: https://github.com/OpenMOSS/MOSS-Image at commit `6f9aabb9db61576838287a18b046383b5402fe26`, folder
  `skills/moss-image-prompt-enhancer`:
  - `SKILL.md`, without the file's final newline. The text's SHA-256 is
    `f559b9c40cca4c944f1b6dae8306928a92211afa5543ad1e83a0616fc63405d4`.
  - `references/layout.md`, without the file's final newline. The text's SHA-256 is
    `2bcde35aa763acd76941d87571edfd2b1cfd191dd5053b28b76f435f194c2cbc`.
  - `scripts/compile_prompt.py` (file SHA-256 `1d75780cf9f22f9ebed1a33d8100158f8d73ebfe59a5d435c1cc8c8e1374a8a3`),
    ported, with its tests (`scripts/test_compile_prompt.py`) ported to `Tests/PromptEnhanceKitTests/MOSSLayoutTests.swift`.
- Licence: Apache-2.0 (the repository's `LICENSE`, the stock Apache 2.0 text; the folder carries no other licence, and the
  repository has no NOTICE file and no copyright line). Published by the OpenMOSS team.
- Used by: `ImageModelProfiles.moss`, with `AnswerCompiler.mossImageLayout`.
- Changes:
  - **The texts:** none. The skill is written for an agent that reads `SKILL.md`, reads `references/layout.md` before a
    Layout draft, writes the draft to a file and runs the script on it. Here the two texts are the system turn, joined by
    one line of the kit's own (MIT). The user turn is the kit's own (MIT): it asks for a Layout, says there are no tools
    and that the answer is the draft, and carries the brief and the target resolution.
  - **The script:** translated from Python to Swift (`MOSSLayout`), with its checks, their order and messages, its
    rounding and its output (`json.dumps(..., ensure_ascii=False, separators=(",", ":"))`). It reads the backbone's
    answer (the whole text, or its first `{` to its last `}`) instead of a file and returns the prompt with the draft's
    canvas instead of writing a file. The kit adds one check of its own: a layout for another canvas than the host's
    target size fails.
