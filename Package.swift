// swift-tools-version: 6.2
import PackageDescription

// prompt-enhance-kit-swift — a backbone-agnostic, cross-engine prompt enhancer (image + video).
//
// Prompt enhancement is already a portable engine `llm` MODE (`Mode.promptEnhance` on `LLMRequest`),
// so this kit is NOT a model port: it carries a task-aware TEMPLATE LIBRARY and a thin enhance util
// that builds a `.promptEnhance` request and runs it on a caller-supplied runner (which wraps the
// engine). It depends ONLY on `MLXToolKit` (the engine contract) — no MLX, no Qwen/Ernie coupling —
// so ANY registered `.llm`/VL package backs it.
//
// Home: mlxengine-think (the LLM-layer / reasoning-adjacent home, deliberately NOT named "LLM").
// Design: mlxengine-video/WAN_DEV/WAN_TESTING/companion/ENH-wan-prompt-enhancer.md (UPE0–UPE3).
let package = Package(
    name: "prompt-enhance-kit-swift",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "PromptEnhanceKit", targets: ["PromptEnhanceKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/xocialize/mlx-engine-swift", from: "0.9.1"),
    ],
    targets: [
        .target(
            name: "PromptEnhanceKit",
            dependencies: [
                .product(name: "MLXToolKit", package: "mlx-engine-swift"),
            ]
        ),
        .testTarget(
            name: "PromptEnhanceKitTests",
            dependencies: ["PromptEnhanceKit"]
        ),
    ]
)
