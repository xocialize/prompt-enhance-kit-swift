# Third-party notices

The kit is MIT-licensed (`LICENSE`). Two model profiles carry vendor prompt text verbatim, under the Apache License 2.0
(`LICENSES/Apache-2.0.txt`). Both are in `Sources/PromptEnhanceKit/VendorPrompts.swift`, extracted mechanically from the
pinned sources below.

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
