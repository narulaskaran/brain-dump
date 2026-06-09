---
tags: [tooling, seed]
---
# Idea capture — hosted version

**Status:** 🌱 seed  
**Project:** Personal tooling  
**Created:** 2026-06-08  
**See also:** [[idea-capture-menubar-app]] (local version)

---

## Project status

- [ ] Decide vault storage approach (pass-through vs server-side)
- [ ] Spec out CLI client
- [ ] Spec out MCP server interface
- [ ] Build MPP-gated Next.js backend
- [ ] Test end-to-end: CLI → server → local file write

---

## What's different from the local app

The local app runs everything on-device — embeddings, LLM calls, file I/O. The hosted version splits the work:

- **Client** (CLI, MCP, curl): handles Phase 1 locally (load vault, compute embeddings, find top-k candidates), then sends raw input + candidate context to the server
- **Server**: runs the agentic tool-use loop, returns file operations for the client to execute

The server is stateless — it never touches the vault directly. File writes happen on the client. This keeps the server simple, keeps vault data local, and means embeddings always live on the machine that has the vault.

The server is itself an MPP-gated endpoint — callers pay per request via Tempo. No accounts, no API keys for the caller.

---

## Why a hosted version

- **Zero LLM key setup for the caller:** server has its own LLM keys; caller only needs a funded Tempo wallet
- **Any client:** CLI one-liner, MCP tool, curl, any HTTP client
- **Natural MPP demo:** every call is a real paid MPP request — the server is exactly what [[create-mpp-app-cli]] scaffolds

---

## Architecture

```
Client (CLI / MCP / curl)
  Phase 1 — local:
    1. Read vault, load/compute embeddings
    2. Embed raw input, cosine sim → top-k candidates
    3. Build request: { input, candidates: [{ path, content }] }

  Phase 2 — remote:
    → POST /file  { input, candidates }
    → 402 MPP challenge
    → client pays via Tempo (mppx / tempo / link-cli on PATH)
    → server runs agentic tool-use loop
    → returns { operations: [{ op, path, content }] }

  Phase 3 — local:
    4. Execute file operations returned by server
    5. Recompute + cache embeddings for modified files
    6. Run local grooming pass if enabled
```

Server is stateless — no vault access, no file I/O, just LLM orchestration.

---

## Vault format contract

All files written by the client must conform to the vault format contract defined in [[idea-capture-menubar-app]]. The server enforces this in its system prompt — the client validates outputs before writing (rejects files missing frontmatter, containing HTML, using absolute paths, etc.).

---

## Server — agentic loop

Same tool-use loop as the local app, but the tools are virtual — server can't actually write files. Instead, tool calls are accumulated and returned as a structured list of operations:

```
tools available to LLM on server:
  search_similar(query)       → searches candidates passed in the request
  read_file(path)             → reads from candidates passed in the request
  write_file(path, content)    → records a WRITE operation
  append_to_file(path, content) → records an APPEND operation
  update_index(row)           → records an INDEX_UPDATE operation
  done(summary)               → terminates loop

response: { operations: [...], summary: string }
```

Client receives the operations list and executes each one locally against `~/ideas/`.

---

## Client surfaces

**CLI:**
```bash
braindump file "raw idea text"
# Phase 1 runs locally, posts to server, executes returned operations
# Detects MPP CLI on PATH, pays 402 automatically
```

**MCP server** (local process, exposes tools to Claude Code / Cursor):
```
file_idea(text)     → runs full flow, returns filed path
search_ideas(query) → local embedding search, no server call needed
groom()             → local grooming pass, no server call needed
```

MCP tools that are purely local (search, groom) don't touch the server at all — only filing needs the LLM.

**HTTP (manual):**
```bash
curl -X POST https://braindump.example.com/file \
  -H "Authorization: <MPP credential>" \
  -d '{"input": "raw idea", "candidates": [...]}'
```

---

## MPP pricing

| Endpoint | Cost (approx) |
|----------|---------------|
| `POST /file` | ~$0.01 |
| `POST /groom` | ~$0.05 |

Amounts should reflect actual LLM token cost. Groom is more expensive — reads all candidates passed in context.

---

## Vault storage

Pass-through (stateless server, client executes operations locally). Rationale:
- Server never holds vault data
- Obsidian workflow unchanged — files land in `~/ideas/` as normal
- Embeddings stay local — no sync problem
- MCP agent knows vault path because it runs on the same machine

---

## Open questions

- [ ] Auth: MPP handles payment but not identity — fine for personal use, matters if multi-user ever happens
- [ ] Server LLM provider: which model/provider does the hosted server use? Needs to be decided for cost/pricing math
- [ ] `search_similar` on server: server only has the candidates passed in the request — if LLM wants to search beyond them, it can't. Mitigation: client passes top-10 instead of top-3 for hosted requests to give the server more to work with
