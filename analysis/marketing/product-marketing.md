# Product Marketing Context

**Document version:** v1
**Last updated:** 2026-09-02
**Status:** Codebase-derived working context. Items marked as hypotheses or unknown require customer/business validation. The canonical `.agents/product-marketing.md` path was not writable in this workspace.

## Product Overview

**One-liner:** CapsStack is a macOS utility that turns the time you step away from AI coding agents into a concise return brief, so you can resume work without rereading long logs.

**What it does:** The user switches Caps Lock on before stepping away and off when returning. CapsStack gathers local sessions from supported terminal coding agents, then uses a separately selected CLI to summarize progress, decisions, blockers, and next steps. It keeps history locally, supports pre-away notes, and deletes raw artifacts after successful summarization.

**Product category:** AI coding workflow utility / developer productivity / coding-agent session summarizer.

**Product type:** Native macOS desktop utility with a companion local CLI and Codex plugin.

**Business model:** Unknown. The repository documents local `.pkg` distribution but no price, license, paid plan, account, or subscription.

## Target Audience

**Target companies:** Hypothesis — individual developers and small technical teams using one or more terminal coding agents on Mac. Company size, buyer, and procurement profile are unvalidated.

**Decision-makers:** Primarily the end user. For team adoption, likely a senior engineer, engineering manager, developer-experience lead, or founder; this is unvalidated.

**Primary use case:** Regaining working context after leaving one or more coding agents running for several minutes or longer.

**Jobs to be done:**

- When I return to delegated coding work, tell me what changed, what was decided, what is blocked, and what I should do next.
- Let me step away without keeping the agent's full conversation state in working memory.
- Consolidate return context across different CLI agents without forcing me into one vendor's workflow.

**Use cases:**

- Coffee, meeting, lunch, or end-of-day return after an agent task.
- Parallel terminal-agent sessions across several repositories.
- Capturing a short note for GUI-based agents that CapsStack cannot inspect directly.
- Copying or exporting a return brief for a handoff or work log.

## Personas

These are hypotheses, not research-backed personas.

| Persona | Cares about | Challenge | Value we promise |
|---------|-------------|-----------|------------------|
| Multi-agent Mac developer | Fast re-entry, reliability, local control | Context is fragmented across terminals and tools | One return brief organized by project and session |
| AI-native indie developer/founder | Momentum and low coordination overhead | Delegated work continues while attention moves elsewhere | Step away and resume from an actionable summary |
| Developer-experience lead | Repeatable workflows, privacy, interoperability | Team members use different coding agents | A vendor-neutral local re-entry pattern; team value is unvalidated |

## Problems & Pain Points

**Core problem:** AI agents can keep working while the human leaves, but the human pays a context-reconstruction cost when returning.

**Why alternatives fall short:**

- Reading the full transcript is slow and forces the user to separate signal from tool chatter.
- Inspecting only `git diff` shows code changes but misses decisions, failures, and intended next steps.
- Each coding agent keeps its own history and summary conventions.
- Manual notes require the user to predict what will matter before leaving.

**What it costs them:** Time to reread, delayed validation, repeated questions, missed blockers, and lost momentum. No quantified customer evidence exists yet.

**Emotional tension:** “I delegated the work to save attention, but now I have to reconstruct the whole story.” This is positioning language, not a verbatim customer quote.

## Competitive Landscape

**Direct:** No validated direct competitor identified yet for Caps-Lock-bounded, cross-agent return briefs.

**Secondary:** Agent-native session summaries, conversation history/search, IDE agent dashboards, and local context-memory tools solve parts of the same re-entry job.

**Indirect:** Reading transcripts, checking `git diff`/status, terminal scrollback, writing manual notes, asking the agent to recap, or doing nothing.

## Differentiation

**Key differentiators:**

- A physical, low-friction Caps Lock gesture defines the away interval.
- Collection and summarization providers are configured independently.
- Ten terminal-agent session sources are supported in the current README.
- Summarization runs away from the original working directory with restricted or disabled tools.
- Raw logs are deleted after success; failed runs retain only what is needed for retry.
- Pre-away notes preserve context for unsupported GUI-agent work.

**How we do it differently:** CapsStack treats human re-entry as its own workflow, bounded by absence rather than by an entire chat or repository history.

**Why that's better:** The brief is scoped to what happened while the user was away, is easier to scan, and does not require changing coding-agent vendors.

**Why customers choose us:** Hypothesis — the combination of a tactile trigger, cross-agent support, and privacy-conscious local orchestration.

## Objections

| Objection | Response |
|-----------|----------|
| “I can just ask the agent to summarize.” | That works for one active session; CapsStack scopes the period automatically and can combine multiple supported agents and projects. |
| “Reading local agent logs sounds invasive.” | CapsStack documents local collection boundaries, excludes known artifacts, sends no session content to its own server, and deletes raw inputs after success. The selected summarizer may still send input to its provider. |
| “Caps Lock is already useful to me.” | The trigger is intentionally fast but may be a poor fit for users who rely on Caps Lock for typing or remap it; alternative triggers are not documented. |

**Anti-persona:** Windows/Linux-only users; developers who do not delegate unattended work; users whose work occurs only in unsupported GUI agents; environments that prohibit sending session material to the selected summarization provider.

## Switching Dynamics

**Push:** Rereading transcripts, checking several terminals, and losing momentum after breaks.

**Pull:** A brief highlighting progress, decisions, blockers, and next steps immediately upon return.

**Habit:** Terminal scrollback, `git diff`, agent recap prompts, and keeping the work mentally active while away.

**Anxiety:** Privacy, collection reliability, summary accuracy, model cost, CLI installation/authentication, and interference with Caps Lock behavior.

## Customer Language

No first-party customer verbatims are available in the repository. The lines below are product copy, not customer evidence.

**How they describe the problem:**

- “離席後、長い会話ログやGit diffを読む前に現在地を把握したい” — README product copy
- “人間がAIの作業状態へ戻るまでの時間を短くする” — README product copy

**How they describe us:**

- “Step away. Come back caught up.” — current tagline
- “復帰ブリーフ” — current name for the output

**Words to use:** return brief, caught up, resume, progress, decisions, blockers, next steps, local, step away, agent sessions.

**Words to avoid:** autonomous employee, surveillance, guaranteed accuracy, private by default without qualification, AI dashboard.

**Glossary:**

| Term | Meaning |
|------|---------|
| Away interval | Time between Caps Lock ON and OFF |
| Return brief / 復帰ブリーフ | Structured summary of progress, decisions, blockers, and next actions |
| Collector | A supported CLI session source |
| Summarizer | The independently selected CLI/model that generates the brief |
| Pre-away note / 退席前メモ | User-written context included in the next brief |

## Brand Voice

**Tone:** Calm, precise, reassuring, lightly warm.

**Style:** Direct and native-Mac in feel; concise explanations with explicit privacy and safety boundaries.

**Personality:** Dependable, quiet, crafted, pragmatic, privacy-conscious.

## Proof Points

**Metrics:** No customer outcome, adoption, conversion, retention, or revenue metrics are documented. Opt-in telemetry can measure aggregate brief success/failure, duration buckets, retries, provider tests, and brief consumption actions.

**Customers:** None documented.

**Testimonials:** None documented.

**Value themes:**

| Theme | Proof |
|-------|-------|
| Cross-agent coverage | README documents ten collection sources and multiple summarizers |
| Safer orchestration | Provider-specific tool restrictions and isolated temporary working directories are implemented and tested |
| Local-data restraint | No first-party upload of session content; reviewed opt-in telemetry vocabulary; raw inputs deleted after successful summarization |
| Native workflow | macOS app, menu-bar state, history, notifications, `.pkg`, and companion CLI |

## Goals

**Business goal:** Unknown. Working hypothesis: validate that “time to regain context” is a painful, frequent job and earn repeat weekly use among Mac developers running coding agents unattended.

**Conversion action:** Unknown. Near-term candidate: install the `.pkg`, complete setup, and generate the first successful return brief.

**Current metrics:** Unknown. No App Store Connect, distribution, website, download, revenue, or opt-in telemetry results were provided.

## Changelog

*Newest first. One line per revision: what changed and why.*

- v1 (2026-09-02) — Initial codebase-derived context for the customer, competitor, analytics, and ASO analysis sequence.
