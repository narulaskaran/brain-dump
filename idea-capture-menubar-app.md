---
tags: [tooling, seed]
---
# Idea capture menu bar app (macOS)

**Status:** 🌱 seed  
**Project:** Personal tooling  
**Created:** 2026-06-08  
**See also:** [[idea-capture-hosted]] (hosted version)

---

## Project status

- [x] Scaffold Swift project: `NSStatusItem` + `NSPopover` + Carbon hotkey
- [x] Build both LLM adapters (OpenAI-compatible + Anthropic)
- [x] Wire settings view → Keychain → URLSession calls
- [x] Build grooming pass, write to GROOMING.md
- [x] Polish: Obsidian URI on notification tap, badge for pending grooming
- [ ] Test filing pipeline against real messy inputs
- [ ] Add `LSUIElement = YES` to Info.plist for menu-bar-only mode (Xcode project step)

---

## Problem

Good ideas surface at random moments — in a meeting, mid-shower, reading a doc. The capture friction is too high: open Obsidian, navigate to the right file, format the idea, file it. By the time you're done you've lost the thread or given up. Most ideas die before they're captured.

---

## Core thesis

A native Swift menu bar app. One hotkey → text box → brain dump → AI cleans it up and files it. Zero formatting overhead, zero navigation. The idea goes from head to structured note in under 10 seconds.

---

## UX flow

```
[Any app, any moment]
    ↓ Cmd+Shift+I  (or click menu bar icon)

┌─────────────────────────────────────────────┐
│  💡 New Idea                          [ESC] │
│  ─────────────────────────────────────────  │
│  mpp browser ext could also work for        │
│  substack style micropayments not just      │
│  agents, devs need to implement gate tho    │
│  need to solve chicken egg first            │
│                                             │
│  [File Idea ↵]                    [Discard] │
└─────────────────────────────────────────────┘
    ↓ hit Enter

→ LLM processes in background (non-blocking)
→ notification: "Filed to: projects/mpp/mpp-browser-extension.md (appended)"
   or: "Filed as: projects/mpp/new-idea-slug.md"
→ grooming pass runs automatically
```

Text input is multiline. Enter adds a newline. Cmd+Enter submits. ESC discards.

App disappears immediately after submit — never interrupts flow.

---

## Tech stack

Native Swift:
- Menu bar: `NSStatusItem` + `NSPopover`
- Global hotkey: `Carbon` / `MASShortcut`
- LLM calls: `URLSession` (own mini harness, no subprocess)
- File I/O: standard `FileManager` on `~/ideas/` — no sandbox, ships as unsigned `.app`
- Settings: `SwiftUI` settings window

---

## Settings view

Fully local app — no hosted backend, no server.

| Setting | Options |
|---------|---------|
| **LLM mode** | BYOK · MPP |
| **Provider** (BYOK only) | Anthropic · OpenAI-compatible |
| **API base URL** (BYOK only) | editable (OpenRouter, Ollama, any compatible endpoint) |
| **API key** (BYOK only) | stored in Keychain |
| **Model** | free-text (e.g. `claude-sonnet-4-6`, `gpt-4o`) |
| **Vault path** | defaults to `~/ideas/`, browseable |
| **Hotkey** | rebindable |
| **Auto-groom on insert** | toggle (default on) |
| **Manage Obsidian graph config** | toggle (default on) |

In MPP mode the API key and base URL fields disappear. App detects which MPP CLI is on `$PATH` at launch (`mppx`, `tempo`, or `link-cli`) and uses it to pay the 402 challenge on each LLM call. LLM requests route through `openai.mpp.tempo.xyz` (OpenAI-compatible, pays via Tempo). Requires a funded Tempo wallet — no API key setup.

---

## LLM harness (mini, no subprocess)

`LLMProvider` protocol with tool-use support. One concrete class per provider. Settings view persists choice + key to Keychain; app instantiates the right class on launch.

```swift
protocol LLMProvider {
    func complete(messages: [Message], tools: [Tool]) async throws -> LLMResponse
}

enum LLMResponse {
    case text(String)
    case toolCalls([ToolCall])
}

class AnthropicProvider: LLMProvider { ... }   // Messages API + tool use
class OpenAIProvider: LLMProvider { ... }       // /v1/chat/completions + tool use, configurable base URL
```

`OpenAIProvider` takes a base URL — covers OpenAI, OpenRouter, Ollama, any OpenAI-compatible endpoint. README lists common providers and their base URLs. New provider = new subclass only if it needs a different wire format (only Anthropic so far).

**MPP mode** routes through `openai.mpp.tempo.xyz` which is OpenAI-compatible only — Anthropic models unavailable in MPP mode. In MPP mode the UI hides provider/key/base-URL fields entirely and shows only the detected MPP CLI. CLI priority: `mppx` → `tempo` → `link-cli`. If none found, MPP mode is disabled with an explanatory label.

**First run:** on launch, if no API key is configured and MPP mode is not available, Settings opens automatically.

**Error handling:** on API error, timeout, or rate limit — fire a macOS notification with the error message, leave the popover open so the user can retry or discard. No silent failures.

**Retry:** no automatic retry. User retries manually.

Settings view writes provider choice + key to Keychain. App reads on launch.

---

## AI processing pipeline

### Phase 1 — Load + embed (local, no LLM)

```
1. Read all ~/ideas/projects/**/*.md
2. For each file: load cached embedding from .embeddings.json,
   or recompute if file mtime has changed
3. Compute embedding for raw input text
4. Cosine similarity: score input vector against every file vector
5. Take top-k (k=3) as candidate files for context
```

This phase is pure local computation — no network, no LLM, ~0ms.

### Phase 2 — Agentic tool-use loop

Hand the LLM the raw input, top-k candidates (title + full content), and a tool set. Run until it calls `done`:

```
while not done:
    response = llm(messages, tools)
    if response has tool_calls:
        results = execute(tool_calls)   // sandboxed to ~/ideas/
        messages += [response, results]
    else:
        done = True

max_iterations = 10  // hard cap
```

The loop lets the LLM handle non-trivial cases: reading more files, appending to multiple files, chaining a new file creation with an update to an existing one, etc. Simple inputs (clear new idea or obvious append) terminate in 1-2 iterations.

**Concurrency:** submissions are queued — if the user submits while a filing operation is in progress, the second submission waits. The popover closes immediately on submit either way; queue runs serially in the background.

**Tools available to the LLM:**

```swift
search_similar(query: String) → [FileResult]  // cosine sim on vault, returns top-k
read_file(path: String) → String
write_file(path: String, content: String)      // new files only; returns error "file exists, use append_to_file" if path taken
append_to_file(path: String, content: String)
update_index(row: String)                      // appends row to IDEAS.md; row must be: "| [[projects/<group>/<slug>]] | 🌱 | <one-line summary> |"
done(summary: String)                          // terminates loop; summary drives notification
```

All file tools are sandboxed — paths outside `~/ideas/` are rejected before execution. If `done()` is never called after `max_iterations`, the app fires an error notification and discards any partial writes.

`search_similar` is the key tool: instead of a fixed top-k upfront, the LLM can iteratively probe the vault if the initial candidates aren't sufficient.

### Phase 3 — Post-insert

```
1. For any file written/modified: recompute + cache embedding
2. Run grooming pass (if auto-groom enabled):
   - pairwise cosine similarity across all file vectors
   - pairs above threshold (>0.85) → flagged as near-duplicates
   - LLM generates suggestion text only for flagged pairs
   - write to ~/ideas/GROOMING.md, update .grooming-state.json
3. Fire macOS notification: summary from done() call, tap opens file in Obsidian
```

### LLMProvider protocol

Tool use requires a richer interface than a simple string completion:

```swift
protocol LLMProvider {
    func complete(messages: [Message], tools: [Tool]) async throws -> LLMResponse
}

enum LLMResponse {
    case text(String)
    case toolCalls([ToolCall])
}
```

Both `AnthropicProvider` and `OpenAIProvider` support tool use natively — different wire formats, same protocol.

### Local embeddings — how they work

Embeddings are dense vectors that encode semantic meaning. Two pieces of text with similar meaning produce vectors that point in similar directions — measurable with cosine similarity (dot product of unit vectors, range -1 to 1). This is pure math, runs in-process, no network call.

**Computing embeddings** — Apple's `NaturalLanguage` framework, ships with macOS, runs on Neural Engine, nothing to bundle:

```swift
import NaturalLanguage

let embedder = NLEmbedding.sentenceEmbedding(for: .english)!

func embed(_ text: String) -> [Double] {
    embedder.vector(for: text) ?? []
}
```

**Cosine similarity** — measures how close two vectors are:

```swift
func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    let dot  = zip(a, b).map(*).reduce(0, +)
    let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
    let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
    guard magA > 0, magB > 0 else { return 0 }
    return dot / (magA * magB)
}
```

Score of 1.0 = identical meaning. Score ~0.85+ = strong overlap. Score <0.5 = unrelated.

**What gets embedded** — title + full file content concatenated. More signal than title alone; the LLM makes the final call so quality doesn't need to be perfect.

**Caching** — vectors are stored in `~/ideas/.embeddings.json` keyed by file path + mtime. On load, only recompute vectors for files that have changed since last run:

```swift
struct EmbeddingCache: Codable {
    var entries: [String: Entry]  // key = file path

    struct Entry: Codable {
        var mtime: Date
        var vector: [Double]
    }
}
```

**CLASSIFY flow in full:**

```
1. embed(rawInput) → inputVector
2. for each file: load cachedVector (or recompute)
3. score = cosineSimilarity(inputVector, cachedVector) for every file
4. sort descending, take top-3
5. send top-3 files (title + full content) to LLM:
   "Is this a new idea, or does it extend one of these?"
6. LLM returns action + target path
```

The LLM never sees the vectors — only the top-k candidates filtered by them. Vault can have 1000 files; LLM context stays small.

**GROOM near-duplicate detection:**

```
1. load all cached vectors
2. pairwise cosineSimilarity for every (file_a, file_b) combination
3. pairs with score > 0.85 → flagged as near-duplicates
4. pass flagged pairs to LLM to generate merge suggestion text
```

Pairwise is O(n²) but fine for hundreds of files — each comparison is just a dot product.

**Fallback:** if `NLEmbedding.sentenceEmbedding(for: .english)` returns nil (older macOS), skip Phase 1 entirely and pass all files (capped at 20) directly to the LLM as starting context.

**Long files:** `NLEmbedding` silently truncates long input. Embed `title + first 500 chars` rather than full content to keep vectors consistent across files of different lengths.

**Limits:** `NLEmbedding` is not SOTA — it's a small on-device model. Good enough for near-duplicate detection and top-k retrieval. The LLM makes the actual decision, so embedding quality only affects recall (whether the right candidate makes the top-k), not precision.

---

## Grooming / clustering

Triggers:
- **Auto**: after every successful insert, no cooldown
- **Manual**: "Groom Backlog" button in menu bar dropdown

**Context window:** if vault exceeds 50 files, groom in chunks of 50, sorted by recency. Write findings from each chunk to GROOMING.md before processing the next.

What it does:
1. Reads all project files, summarizes each in one line
2. LLM identifies: semantic clusters, near-duplicate ideas, ideas that should merge, ideas ready to graduate from 🌱 seed
3. Writes suggestions to `~/ideas/GROOMING.md` — does NOT auto-modify files (human stays in control)
4. Badge on menu bar icon when unreviewed grooming suggestions exist

Over time `GROOMING.md` becomes a living backlog refinement log. User acts on suggestions in Obsidian, clears the file when done.

**Format:** Pure markdown — no YAML frontmatter. Swift has no built-in YAML parser and mixing machine-managed fields with human-edited content is fragile.

**Badge state:** Separate `~/ideas/.grooming-state.json` — `{ reviewed: bool, generated_at: string, count: int }`. Swift `Codable`, zero dependencies. Badge clears when user deletes/archives `GROOMING.md`; app detects absence and resets state.

---

## Vault format contract

Every file the app writes must be navigable by a human in Obsidian, VS Code, or a plain markdown reader without any knowledge of the app. The app is just a faster way to create files a human could have written themselves.

### File structure

```
~/ideas/
  IDEAS.md                        ← human-maintained index, app only appends rows
  GROOMING.md                     ← app-written suggestions, human acts on them
  projects/
    <group>/                      ← one subfolder per category (mpp, tooling, etc.)
      <slug>.md                   ← one file per idea
  .embeddings.json                ← dotfile, hidden from Obsidian by default
  .grooming-state.json            ← dotfile, hidden from Obsidian by default
```

Dotfiles (`.embeddings.json`, `.grooming-state.json`) are machine state only — never shown in Obsidian's file explorer, never appear in graph view.

### Every generated file must

- Start with valid YAML frontmatter (`tags`, no other required fields)
- Use `[[wikilinks]]` for cross-references to other vault files — not relative paths, not URLs
- Use standard ATX headings (`##`, `###`) — no setext style
- Use lowercase-hyphenated filenames, no spaces or special characters
- Contain no absolute paths in body text
- Contain no HTML
- Contain no app-internal metadata (no IDs, timestamps, or machine-generated keys in the body)

### Template for new idea files

```markdown
---
tags: [<group>, seed]
---
# <Title>

**Status:** 🌱 seed
**Project:** <group display name>
**Created:** <YYYY-MM-DD>

---

## Problem

<2-3 sentences>

---

## Core thesis

<1-2 sentences>

---

## Open questions

- [ ] <question>
```

LLM must follow this template exactly for new files. Sections can be omitted if genuinely not applicable, but order must be preserved. Additional sections (Tech stack, Pipeline, etc.) go after Core thesis.

### Obsidian-specific

- `[[wikilinks]]` without path work as long as filenames are unique in the vault (they should be)
- `obsidian://open?vault=ideas&file=<url-encoded-path>` URI in notifications opens the file directly
- Status emoji (`🌱 🔄 ⏸ ✅ 🪦`) in frontmatter `status` field can be queried by the Tasks plugin

### Obsidian graph config (opt-out, default on)

When "Manage Obsidian graph config" is enabled, the app owns `.obsidian/graph.json` and keeps colorGroups in sync with the `projects/` folder structure. Every subfolder gets a distinct color — new group = new colorGroup entry added automatically.

**Behaviour:**
- On first run: generate `graph.json` with a colorGroup per existing subfolder
- When a new group folder is created: append a new colorGroup entry
- When a group folder is deleted: remove its colorGroup entry
- Never touches other graph.json keys (forces, display settings, etc.) — only `colorGroups`

**Color assignment:** predefined palette of 10 visually distinct colors, assigned in order as groups are created. Stored in `.grooming-state.json` so assignments are stable across runs (group 1 always stays its original color even if groups are added/removed).

```swift
let palette: [Int] = [
    0x00A63A, // green
    0x4A8FD4, // blue
    0xE8A838, // amber
    0xE05C5C, // red
    0x9B59B6, // purple
    0x1ABC9C, // teal
    0xE67E22, // orange
    0x2ECC71, // mint
    0xE91E8C, // pink
    0x607D8B, // slate
]
```

colorGroup query uses `path:projects/<group>` — no tags needed, folder membership is the signal.

**Why opt-out not opt-in:** Obsidian graph view works out of the box for anyone who clones the vault or opens it fresh. Zero manual config required.

---

## System prompts

The agentic loop uses tool calls — the LLM does not respond with JSON. System prompts describe the task and rules; the LLM drives the loop by calling tools.

**Filing system prompt:**
```
You are filing a raw idea into an Obsidian vault at ~/ideas/.

You have been given the top-3 most semantically similar existing files as starting context.
Use the tools to read more files, search for others, or write/append as needed.

EXISTING GROUPS: {{comma-separated list of subfolders under projects/}}

Rules:
- Preserve the user's intent exactly. Don't add ideas they didn't have. If vague, keep it vague.
- New files must follow the vault format contract exactly: valid YAML frontmatter, [[wikilinks]] for cross-refs, standard ATX headings, no HTML, no absolute paths, no app-internal metadata.
- New files: frontmatter tags: [<group>, seed]. Slug: lowercase-hyphenated, no stop words.
- Use an existing group folder if one fits. Only create a new group if the idea clearly doesn't belong to any existing one.
- If the input clearly extends an existing idea, append — don't create a duplicate.
- If the input spans multiple existing ideas, append to each.
- Call update_index() when creating a new file. Row format: "| [[projects/<group>/<slug>]] | 🌱 | <one-line summary> |"
- Call done() when all writes are complete, with a one-line summary for the notification.
```

**Grooming system prompt:**
```
You are reviewing an Obsidian ideas vault for backlog health.

You have been given all files with their titles, paths, and tags.
High-similarity pairs (cosine similarity > 0.85) have been pre-flagged.

Identify and write to GROOMING.md:
1. Near-duplicates that should merge (include both paths + rationale)
2. Ideas ready to move from 🌱 seed → 🔄 active
3. Missing categories (several ideas share a theme but have no shared group folder)

Rules:
- Be terse. One bullet per finding.
- Flag only high-confidence observations.
- Do NOT modify any idea files — suggestions only.
- Call done() when GROOMING.md is written.
```

---

## Future extensions

- **Voice input:** `SFSpeechRecognizer` as alternative to typing — word vomit literally
