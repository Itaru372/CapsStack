# CapsStack Marketing Analysis — Integrated Readout

**Generated:** 2026-09-02  
**Sequence:** product-marketing → customer-research → competitor-profiling → analytics → ASO

## Bottom line

CapsStack has a differentiated and understandable wedge:

> **AI coding agents keep working while you step away. CapsStack shortens the time it takes the human to return, understand what happened, and review what matters next.**

Public developer discussions support the underlying problem: waiting breaks flow, parallel agents desynchronize the human's mental model, and developers already maintain scratchpads, context files, summaries, and diffs to recover. Competitors address adjacent jobs—persistent memory, cross-agent resume, or full agent orchestration—but none of the three profiled products owns the deliberately bounded **return moment**.

The major risk is not feature parity. It is whether this pain is frequent enough, whether Caps Lock is an acceptable trigger, and whether users trust and repeatedly consume the brief. Those questions should be answered before expanding into team orchestration or committing to Mac App Store architecture.

## What each analysis changed

| Stage | Main conclusion | Decision it informs |
|-------|-----------------|---------------------|
| Product marketing | Category is “AI coding workflow / return brief,” not generic AI acceleration | Keep the promise centered on human re-entry |
| Customer research | Human mental-model drift and review backlog are real public pain themes | Make review triage and confidence explicit |
| Competitor profiling | Pieces owns broad memory; `continues` owns session portability; Vibe Kanban owned orchestration | Defend a narrow, low-friction return workflow |
| Analytics | Current telemetry measures reliability but not setup completion, activation, or quality | Add only the minimum decision-bearing events and feedback |
| ASO | No listing exists; App Sandbox may conflict with core external-CLI behavior | Run feasibility spike before store production work |

## Highest-priority actions

### 1. Validate the job with five focused interviews

Recruit developers who run multiple coding agents and still review production changes. Ask about the last actual return-from-away event, time to regain confidence, current workaround, trust boundaries, and why they might uninstall. Do not lead with CapsStack or ask whether the idea sounds useful.

### 2. Define the product outcome as review readiness

Evaluate each brief against four questions:

- What changed?
- What decisions were made?
- What is blocked, failed, or unverified?
- What should the human inspect or do next?

This keeps CapsStack distinct from transcript compression and agent memory.

### 3. Measure activation and repeat consumption

Use “first successful brief completed and consumed” as activation. Use weekly completed-and-consumed briefs as the north-star candidate. Add setup completion, first success, structured helpfulness, and notification-open signals only after privacy review.

### 4. Keep direct distribution as the default launch path

Build a notarized-download landing page and measure aggregate download → first activation. A Mac App Store release should remain conditional on proving sandboxed session-folder access, Accessibility behavior, helper behavior, and especially external summarizer execution.

### 5. Test the positioning before price

Primary message:

> Step away. Come back caught up.

Supporting message:

> One return brief for progress, decisions, blockers, and what to review next—across the coding agents already on your Mac.

Trust qualifier:

> CapsStack does not resume your original session. It collects the away interval locally and uses your selected CLI to generate the brief; that provider may process the supplied content.

## 30-day validation plan

| Week | Work | Exit evidence |
|------|------|---------------|
| 1 | Five problem interviews and baseline time-to-re-entry observations | At least 3 unprompted examples of costly re-entry in one segment |
| 2 | Instrument setup completion, first success, and structured quality feedback in a reviewed design | Event schema approved with no content/path leakage |
| 3 | Private beta with deterministic onboarding and one-week diary | At least 3 users voluntarily reuse the Caps Lock workflow |
| 4 | Analyze completion, consumption, helpfulness, and repeat use | Decide: improve reliability, improve brief quality, change trigger, or expand acquisition |

## Stop/go criteria

### Continue investing if

- At least 3 of 5 interviews describe the problem unprompted and recently.
- Users can explain what the brief changed about their next action.
- Brief completion is at least 85% in the beta.
- Most activated users consume a brief again the following week.
- The Caps Lock trigger is chosen voluntarily rather than tolerated for the test.

### Reconsider positioning or product shape if

- Users mainly want live notifications or remote control rather than return summaries.
- The transcript or built-in agent recap is consistently “good enough.”
- Users distrust any provider processing enough to avoid real projects.
- They consume briefs but still need the same amount of transcript/diff reconstruction.
- Direct-download installation friction overwhelms the perceived value.

## Deliverables

- [Product marketing context](product-marketing.md)
- [Customer research synthesis](customer-research.md)
- [Analytics and measurement plan](analytics-tracking-plan.md)
- [ASO readiness report](aso-readiness.md)
- [Competitive landscape summary](../../competitor-profiles/_summary.md)
- [Pieces profile](../../competitor-profiles/pieces.md)
- [`continues` profile](../../competitor-profiles/continues.md)
- [Vibe Kanban profile](../../competitor-profiles/vibe-kanban.md)

## Known unknowns

- Business model, price, launch market, and primary business goal.
- First-party customer language and measured time saved.
- Download/install/active-user baseline.
- App Store Connect availability and developer identity.
- Mac App Store sandbox feasibility.
- Whether English, Japanese, or bilingual launch should be primary.

Until these are resolved, treat personas, willingness to pay, and store conversion projections as hypotheses rather than facts.
