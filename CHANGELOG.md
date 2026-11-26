# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed

- **Every dependency is on its newest release, including four major migrations**: riverpod 2.6 → 3.4, go_router 13.2 → 18.1, freezed 2.5 → 4.0 and sherpa_onnx 1.13 → 2.0, among 83 upgraded packages.
  - Every controller moved off riverpod 2's `StateNotifier`/`StateProvider` onto `Notifier`, with `ref.mounted` and `ref.onDispose` replacing `mounted` and `dispose()`.
  - Riverpod 3's ten-attempt retry is switched off at the root `ProviderScope`, so a store that cannot open reports its error at once.
- **The runtime is llama.cpp b11819, built from a fork**: the app depends on `PradyX/llama_cpp_dart`, which keeps the package API but moves the pin from `b10182` to `b11819`.
  - `lib/src/ffi/bindings.dart` is regenerated, and the mtmd bitmap helpers, the DRY sampler and the penalties sampler follow the new API.
  - The runtime is a git ref rather than a published version, so a bump is a fork commit plus a rebuilt artifact.

### Added

- **Road Map 2 complete: local agentic workspace (all phases, user-end testing left)**: InstaLLM is a project workspace, not just a chat runtime.
  - *Phase 2.0 workspaces*: a workspace links bots, chats, skills, MCP servers, boards, a vault folder and a repo path, and bots only see assigned workspaces.
  - *Phase 2.1 context intelligence*: a stored compaction policy, a live inspector, per-conversation checkpoints and message pins that survive windowing.
  - *Phase 2.2 skills*: a `SKILL.md` frontmatter parser, a registry with enable/disable and bot assignment, four built-in skills and budgeted progressive loading.
  - *Phase 2.3 MCP*: remote-HTTP servers everywhere and stdio servers on desktop only, with a JSON-RPC client, per-tool allow/ask/read-only permissions and an 8-tool relevance cap.
  - *Phase 2.4 bots*: Researcher/Planner/Coder/Tester templates and custom bots with model, skill, MCP, permission, memory-scope and workspace editors.
  - *Phase 2.5 Obsidian*: vault registration, workspace folder links and permission-gated safe notes with containment, compare-and-swap writes and deletes off by default.
  - *Phase 2.6 Kanban*: tasks as Markdown notes with frontmatter, PL-001 numbering, a six-column board and shared bot operations.
  - *Phase 2.7 workflows*: a pure engine with explicit effects, persisted runs, approval gates, a 3-visit loop cap and a built-in Researcher→Planner→Coder→Tester flow.
  - *Phase 2.8 group chat*: rooms in manual, workflow and opt-in auto modes, mention-first routing and per-bot context.
  - *Phase 2.9/2.10*: conflict files with explicit resolution, an activity feed, a shared permission model and desktop Git status/log/commit with no push or rewrites.
- **Context budget: automatic or a manual limit (Road Map 2 Phase 2.1, unit 1)**: Settings → Chat → Context decides between the previous automatic budget and a 512 → 32768 token cap.
  - The cap is a request, not a guarantee: a smaller declared window wins and the screen names what lowered it.
  - The choice is stored as versioned JSON (`context/budget.json`), with clamped values, corrupt-file backup and read-only handling for a newer schema.
  - One resolver (`ContextBudget.resolvePolicy`) feeds the chat request, the composer projection and bounded agent runs, so the arithmetic lives in one place.
- **A collection can answer from embeddings (Roadmap Phase 6, the last deferred piece)**: the embedding → vector index → retrieval path is opt-in per collection, with `bge-small-en-v1.5` as the default and lexical BM25 as the fallback.
  - Vectors live in index schema v3, and ranking fuses BM25 and cosine by reciprocal rank so switching chat models does not change meaning.
  - A missing model, partial vectors or an unembeddable question degrades to term search instead of failing the turn.
- **Reading a reply aloud can now be held and continued (Roadmap Phase 7)**: `stts` pauses and resumes the system synthesizer, so a long answer continues where it stopped instead of restarting.
  - The bubble being read gains Pause/Resume beside Stop, and a refused hold is reported on the turn rather than leaving a button that lies.
- **Each chat can choose its own local documents (Roadmap Phase 6B)**: a conversation pins a collection to itself or turns local documents off, stored as additive JSON on the conversation.
  - A single resolver (`DocumentScope.resolve`) decides what a request reads, and a pinned collection that was removed falls back to the app-wide one and says so.
- **PDF text extraction (closes the Phase 6A gap)**: `PdfDocumentExtractor` reads a PDF's selectable text through `syncfusion_flutter_pdf` and marks page boundaries for citations.
  - A 300-page cap is stated in the text, an image-only page is reported as a scan, and cancellation is honoured between pages.
- **Portable backup and restore (Roadmap section 15)**: Settings → Data → Backup and restore writes one versioned JSON file of conversations, personas, profiles, settings and benchmark history.
  - Model weights are never copied; a restore reports the models the imported chats were written with instead of failing.
  - A file from a newer build is refused, an unreadable file is refused before anything is touched, and existing items are added as copies rather than overwritten.
- **A device test runs the real engine against installed weights (2026-10-08)**: `integration_test/device_inference_smoke_test.dart` runs a completion, a parsed tool call and an agent goal on the machine's own CPU.
- **Conversation & data architecture (Roadmap Phase 1)**: conversations are independent from models.
  - Create, rename, delete, search and pin multiple local conversations, and switch the active model without losing or duplicating history.
  - Every assistant message records the model that generated it plus per-message generation stats.
  - Export and import conversations as versioned JSON, and migrate per-model threads into conversations on upgrade with the legacy entry kept as a backup.
  - Conversations persist in a versioned file store (`conversations/index.json` plus one file per conversation).
- **Model management (Roadmap Phase 2)**: models can be imported from the device or downloaded from Hugging Face.
  - An import is *managed* (`Copy to app`) or *external* (`Keep in place`), and removing an external record never deletes its source file.
  - Duplicate detection warns before importing, and an import never overwrites an existing model file.
  - A GGUF inspector reads architecture, parameter count, quantization, context length, tokenizer, chat template and projector information from the file itself.
  - A Hugging Face browser lists quantization variants with sizes and downloads through the resumable downloader, paired projectors included.
  - A Model Details screen shows source, storage and parsed metadata, and models saved before Phase 2 keep working.
- **Hardware intelligence (Roadmap Phase 3)**: the app knows the device, whether a model fits and how fast it actually ran.
  - A local device profile reports OS, CPU architecture, cores, memory and storage on demand, and is never uploaded.
  - Compatibility ratings run from `Recommended` to `Not Recommended` (with `Should Run`, `May Be Slow` and `Memory Risk` between), derived from file size, metadata and the memory budget.
  - The memory estimate is broken into weights, KV cache, projector and runtime overhead, and the chat runtime shares its context-size constant with the estimator.
  - Benchmark records capture the runtime configuration, time to first token, prompt rate, memory and a device snapshot, and history is versioned storage.
- **Context & session management (Roadmap Phase 4)**: prompts are assembled against a token budget instead of fixed character limits.
  - `ContextPolicy` describes the window, the answer reservation, a safety margin and a per-message threshold; the system prompt is preserved and charged first.
  - Older turns are condensed locally into memory instead of being dropped, and reasoning-only output is never stored as memory.
  - A message longer than the threshold keeps its head and tail, and attached images are charged against the budget.
  - The chat shows a context usage readout above the composer, and assistant messages store the prompt tokens and window they ran with.
- **Inference profiles (Roadmap Phase 5)**: named runtime configurations any model can reuse, with `Balanced` and `Battery Saver` built in.
  - A profile overrides only what it sets — context, prompt batch, threads, GPU layers, KV placement, sampling and answer length — and resolves through one place.
  - Custom profiles are versioned JSON (`inference_profiles/profiles.json`) with clamped values, and the inference screen shows what the active profile resolves to.
- **Personas (Roadmap Phase 5)**: a reusable system prompt a conversation adopts, with `General`, `Coding`, `Research`, `Creative` and `Concise` built in.
  - Persona text is trimmed and length-limited, and the editor shows what the prompt costs in tokens.
  - Each conversation records the persona it chats with, and a persona can prefer a model and an inference profile.
  - Personas export to the clipboard as versioned JSON and import back as an editable copy that can never shadow a built-in.
- **Local documents and retrieval (Roadmap Phase 6A)**: local files are read, searched and cited fully offline, and their originals are never copied, moved or edited.
  - Extraction, chunking, ranking and storage stay separate, chunking is heading-aware, and oversized blocks split on sentence and line boundaries.
  - Retrieval is lexical BM25 with no extra model download, and every hit reports which query terms it matched.
  - Each document records its chunking settings, pipeline version, backend and content fingerprint, so a settings change re-indexes instead of mixing pipelines.
  - Indexing shows its stage, can be cancelled, and a cancelled or failed file stores nothing and names the reason.
  - Chat retrieval fits the best chunks into a budget, tells the model to cite them as `[1]`, `[2]`, and records which chunks were sent.
- **Knowledge collections (Roadmap Phase 6B)**: documents are grouped into named collections, so work, research and personal material stay apart.
  - A collection owns its chunking settings and index version and holds only derived text, never the files themselves.
  - Retrieval searches one collection at a time and computes its ranking statistics from that collection alone.
  - The index moved to schema v2 with a migration on read, and a partially written or hand-edited index is repaired rather than discarded.
  - Collections are created, renamed and removed on the Documents screen, and the active one is stored with the index and survives restarts.
- **Multimodal attachments (Roadmap Phase 7)**: a message can carry up to four images, each with its own thumbnail, remove button and a Clear all action.
  - Prompt assembly writes one `<image>` marker per attachment in order, and regenerating a turn resends all of its images.
  - Attachments are stored per conversation under the message id, and same-named files get a suffix instead of overwriting each other.
  - Images are downscaled to a 1280 px longest edge and re-encoded in a worker isolate, which also strips EXIF/GPS metadata.
  - An unreadable format (HEIC, for example) or a file over 32 MB is attached untouched instead of being dropped.
- **Voice models (Roadmap Phase 7)**: the app reads `clip.has_audio_encoder` from a projector and surfaces it as the model's `Audio` capability.
  - A Voice screen names the chosen speech model and states the local guarantee, and the chooser explains why an unsuitable model cannot be selected.
  - Projector metadata is read only when the chooser or the screen opens, and cached per file plus size and timestamp.
- **Voice transcription (Roadmap Phase 7)**: a picked wav, mp3 or flac is decoded by the bundled multimodal runtime and handed over as an editable draft, never as a message.
  - The speech model loads with its own declared context capped at 8192 tokens, and only one model is resident at a time.
  - A missing model, a projector without an audio encoder and an unreadable clip are each reported before the engine is touched.
- **Recording voice notes (Roadmap Phase 7)**: the Voice screen records from the microphone, stops itself at two minutes and hands the clip to the same transcription path.
  - Platform configuration lands with it: `RECORD_AUDIO` on Android, a usage description on iOS and macOS, and the macOS audio-input entitlement.
- **Text to speech (Roadmap Phase 7)**: replies are read with the device's own synthesizer behind one capability check, and Linux explains the platform limit instead of offering a dead control.
  - The chosen voice and speed are stored under `voice_settings`, where keys added later stay unset in older documents.
- **Reading replies aloud (Roadmap Phase 7)**: every reply has a **Read aloud** action that becomes **Stop reading**, and a switch reads new replies once as soon as they finish.
  - The switch is off by default, and only a reply with generation stats is read, so a placeholder is never spoken.
- **Model comparison (Roadmap Phase 8)**: a Compare tab sends one prompt to two to four installed models, sequentially, with the same window and a 256-token answer budget.
  - A run can be stopped, keeping the partial answer of the generating model and never loading the remaining ones.
- **Local tools (Roadmap Phase 10)**: a registry where every tool declares its name, typed parameters, risk level, platforms and timeout, and every outcome is a reported result rather than an exception.
  - Argument coercion accepts the shapes small models write, and a missing, misspelled or out-of-range argument is refused with the reason.
  - Two deterministic tools that need no permission ship with this unit, and a sensitive tool is refused unless a permission gate approves it.
- **Tool calls in chat (Roadmap Phase 10, unit 2)**: the model can use the local tools during a normal chat turn, and each call and result is shown under the answer.
  - A call is validated before it is shown, its result is fed back once so the visible reply is prose, and exactly one call runs per turn.
- **Read-only tools (Roadmap Phase 10, unit 3)**: `search_chat_history`, `search_local_documents` and `list_installed_models` run without a permission prompt.
  - Each is registered only when its data exists, and nothing leaves the device or changes.
- **Android actions behind an approval prompt (Roadmap Phase 10, unit 4)**: `set_alarm`, `create_event` and `send_sms` are `Sensitive` Android-only tools, requested through an **Allow …?** dialog that shows the exact validated call.
  - The legacy Android JSON tool contract and its separate reply path are gone, so the app has one tool path.
- **Reading a selected local document (Roadmap Phase 10, unit 5)**: `read_document` joins a document's chunks in order and truncates at 3000 characters with a note saying what was left out.
  - Names match exactly first and then by unique partial name, and only documents in the active collection are readable.
- **Comparison export (Roadmap Phase 8)**: a finished comparison exports as versioned JSON, CSV or Markdown from buttons above the answer cards.
  - The export records the settings the run actually used, and a stopped run warns and says it was stopped.
- **Blind comparison and a preferred answer (Roadmap Phase 8)**: answers can be labelled `Answer A`, `Answer B` while metrics stay visible, and one preferred answer is recorded with the run.
  - The JSON export carries `blind` and `preferredModelId`, and switching blind mode never loses a preference.
- **Saved comparison sets (Roadmap Phase 8)**: a comparison setup saves and reloads in one tap, storing model ids so uninstalled models are dropped with a notice.
  - Sets live in versioned JSON (`benchmark/comparison_sets.json`) with clamped values, and deleting one asks first and touches nothing else.
- **Prompt suites (Roadmap Phase 8)**: the Compare tab sends a whole set of prompts to the same models in one run, with its own versioned export.
  - Models still run sequentially within each prompt, and stopping keeps the answers produced and marks the prompts never sent as skipped.
- **Local agent loop (Roadmap Phase 11)**: an Agent screen works a goal through the local tools with an iteration cap of 12, a token check before every turn and a Stop that keeps partial text.
  - The same call asked for twice, a model that produces no text and a prompt that would not fit each end the run and say why.
  - Every step is recorded and survives as a copyable JSON or Markdown report, sensitive tools keep the **Allow …?** prompt, and a run never writes into a conversation.

### Changed

- **The runtime is upgraded to `llama_cpp_dart 0.9.0-dev.12` (Road Map 1 section 17, 2026-10-09)**: the same llama.cpp pin, with deterministic native teardown and a failed teardown reported instead of discarded.
  - macOS links `llama.framework` through Swift Package Manager instead of shipping dylibs, and answers vision/audio by looking for an mtmd entry point in the process.
  - Android keeps this repository's own three-ABI libraries and switches off the plugin's arm64-only native-assets hook.
- **The runtime track's pre-adoption evaluation is run and recorded (Road Map 1 section 17) (2026-10-08)**: the section 17 checklist answers nine of thirteen lines with evidence and records the four that need a device or a build.
  - `test/inference/inference_engine_contract_test.dart` fails when the pin moves, so the record cannot be skipped silently.
- **The chat bar carries a token dial that opens a budget panel, and New chat has a new icon (2026-10-08)**: the three composer lines became a circular meter with a `MenuAnchor` panel behind it.
  - A request that had to trim messages turns both the ring and the bar to the warning colour.
- **The chat header's trash button deletes the conversation (2026-10-08)**: it asks the same confirmation as the conversation list and removes the messages, their attachments and the row together.
- **Return sends the message on desktop (2026-10-08)**: a desktop-only `ComposerSendOnEnter` sends on Return and the keypad's Return, keeps Shift+Return as a line break, and leaves mobile untouched.
- **The tool contract is only sent to models that can call tools (2026-10-08)**: `supportsToolCalling` reads the model's own chat template, so a text-only model stops paying ~500 tokens of instructions it cannot follow.
- **Personas and inference profiles moved into Settings (2026-10-02)**: the drawer keeps only the screens for the current conversation, under a new Settings → Chat section.
- **Text to speech moved to `stts`, so macOS and iOS use Swift Package Manager (2026-10-02)**: nothing is vendored, the stored speaking rate is migrated, and voices that report `networkRequired` are filtered out.

### Fixed

- **The conversation list kept the message figures it loaded at startup (2026-10-08)**: saving now reloads the entry from the store, so the preview, count and time follow the messages just written.
- **Model-download notifications never appeared on macOS (2026-10-08)**: availability now follows what the platform answers to the permission request, so the request and every later notice happen.
- **The calculator rejected the Agent screen's own example question (2026-10-08)**: `18% of 2450` is now 441 and the word `percent` works, while `18 % 5` stays modulo.
- **The context indicator described a conversation that was no longer open (2026-10-08)**: idle, the chip is projected from the conversation on screen and names the fixed system-prompt cost.
- **An unreadable model file aborted the whole model catalog (2026-10-02)**: a protected or unopenable GGUF now reads as not downloaded, the same as a missing one.
- **Image turns could exceed the context window (Roadmap Phase 4)**: attachment overhead is charged in the single-turn budget as well as for older messages.

### Removed

- **`llmfit` is dropped from the app and the repository (2026-10-15)**: upstream's `--cli` is deprecated, auto-starts a dashboard server, and never exits on Android, and its crate has no Android backend.
  - Removed with it: the bundled binaries and assets, both build scripts, the Android hardware-detection patch and the Gradle tasks.
  - The Benchmark screen keeps its two on-device tabs, which measure real runs rather than a bundled CLI's predictions.

## [1.5.0] - 2026-03-24

### Added

- **Vision Model Support**: Support for multimodal models using `mmproj` projectors. Chat with images on supported hardware.
- **On-device Benchmarking**: Integrated the `llmfit` tool for measuring inference speeds (`tok/s`) directly in the app.
- **Model Search & Filtering**: New search bar in the model selection page to easily find models by name or metadata.
- **macOS Native Support**: Fully functional desktop build with unified navigation and performance optimizations.
- **About Page**: New dedicated About section in the navigation drawer featuring project info and sponsorship links.
- **Hugging Face Feature Detection**: Automatically detect and display model capabilities (Vision, Chat Template, etc.) from Hugging Face metadata.
- **Dynamic Model Discovery**: Automatically discovers and caches downloaded GGUF files for instant selection.
- **New Models**: Added support for the latest Qwen 2.5, DeepSeek R1, Gemma 2, and SmolLM2 variants.

### Fixed

- **Android Initialization Regression**: Resolved an issue where missing multimodal libraries prevented standard model loading.
- **Library Path Resolution**: Improved native library path resolution on Android for better compatibility with split `.so` files.
- **Message History Optimization**: Context window now correctly compresses long messages to maintain stable performance.

## [1.0.0] - 2026-03-07

### Added

- **iOS Native Support**: Full integration of llama.cpp using Metal GPU acceleration for physical devices and CPU-only support for simulators.
- **Max Output Tokens Slider**: New setting in LLM Inference to control response length (up to 2048 tokens).
- **New LLM Models**: Added support for DeepSeek-R1 (1.5B, 7B, 14B, 32B), Qwen2.5-Coder-7B-Instruct, and other modern variants.
- **Visual Refresh**: Updated app branding with a new logo and added a screenshots showcase to the project documentation.
- **Context Expansion**: Increased default context window (nCtx) to 2048 for better long-conversation memory.

### Fixed

- **Response Truncation**: Fixed a bug where chat responses were prematurely stopping at 256 tokens on mobile devices.
- **Default maxTokens**: Increased from 256 to 512 for a better out-of-the-box experience.
- **iOS Simulator Linker Errors**: Resolved issues related to Accelerate/BLAS framework mismatches in simulator builds.
- **Settings Persistence**: Hardened the internal settings logic to prevent Null type errors when loading user preferences.
- **Metal Performance**: Optimized GPU offloading specifically for iOS hardware.
