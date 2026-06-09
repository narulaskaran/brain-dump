# BrainDump

## What it is

BrainDump is a native macOS menu bar app that lets you capture ideas as fast as you can type them. Press a global hotkey, write your thought, and BrainDump uses an LLM to automatically classify and file the idea into the right place in your Obsidian vault — choosing the appropriate PARA folder, picking or creating a group subfolder, writing a structured Markdown note, and updating your ideas index. No context-switching, no manual filing.

## Requirements

- **macOS 26** (Tahoe) or later
- **Xcode Command Line Tools** (`xcode-select --install`)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/narulaskaran/brain-dump/main/install.sh | bash
```

After installation, open **Settings** (click the menu bar icon → Settings…, or press **Cmd+,**) to configure:

1. **LLM API key** — paste your Anthropic (or OpenAI-compatible) API key
2. **Vault path** — choose your Obsidian vault folder via the file picker

## First run

Settings opens automatically on the very first launch. Enter your API key and select your vault folder. BrainDump will start indexing the vault in the background — this can take a few seconds for large vaults.

## Usage

| Action | How |
|--------|-----|
| Capture an idea | **Cmd+Shift+I** (global hotkey) |
| Open menu | Click the menu bar icon |
| Run vault grooming | Menu → Groom Backlog |
| Open last filed note | Menu → Last Filed: \<filename\> |
| Settings | Menu → Settings… or **Cmd+,** |

### Icon states

| Icon | Meaning |
|------|---------|
| Brain | Idle — ready to capture |
| Spinner | Filing or grooming in progress |
| Lightbulb (💡) | Last filing completed successfully |
| Warning (⚠️) | An error occurred — click to dismiss |

### GROOMING.md

After a grooming pass, BrainDump writes `GROOMING.md` to your vault root with findings: near-duplicate notes, ideas ready to promote from seed → active, and missing-category observations. Act on the suggestions in Obsidian, then delete the file.

## Vault format

BrainDump writes into a PARA-style layout:

```
<vault>/
  10 Projects/<group>/<slug>.md   # actionable, has an end goal
  20 Areas/<group>/<slug>.md      # ongoing responsibility
  30 Resources/<group>/<slug>.md  # reference / external knowledge
  00 Inbox/<slug>.md              # unclear classification
  IDEAS.md                        # auto-maintained index table
  GROOMING.md                     # grooming report (ephemeral)
  .grooming-state.json            # hidden from Obsidian
  .obsidian/graph.json            # colour-coded by group (auto-synced)
```

Each new note includes YAML frontmatter with tags, a status badge, and structured sections (Problem, Core thesis, Open questions).

## Gatekeeper

Because the app is not notarized, macOS will block it on first launch:

**Right-click `BrainDump.app` in `/Applications` → Open → Open**

You only need to do this once.

## LLM providers

Choose a provider in Settings. Each has a preset base URL and a model picker with common models (or type a custom model ID).

| Provider | Base URL | Notes |
|----------|----------|-------|
| **Anthropic** (default) | `api.anthropic.com` | Best filing quality; uses Claude API |
| **OpenAI** | `api.openai.com` | GPT-4o and friends |
| **OpenRouter** | `openrouter.ai/api` | 200+ models with one key |
| **Ollama** | `localhost:11434` | Fully local inference, no API key needed |
| **Custom** | any | Any OpenAI-compatible endpoint |

All non-Anthropic providers use the OpenAI `/v1/chat/completions` wire format.

## License

MIT
