# CapsStack Customer Research — Public Signal Synthesis

**Generated:** 2026-09-02  
**Mode:** Existing public signal (Reddit and Hacker News)  
**Scope:** Developers using coding agents asynchronously or in parallel  
**Caveat:** No CapsStack customer interviews, surveys, support tickets, reviews, or product-usage exports were available. Findings describe the problem space, not proven demand for CapsStack.

## Executive finding

There is credible public evidence for a **human re-entry and synchronization problem** around coding agents. Developers describe waiting-induced distraction, mental-model desynchronization, difficulty tracking multiple sessions, and review work that grows faster than their ability to absorb it. The most common workaround is a manually maintained summary, scratchpad, plan, diff, or context file.

The evidence does **not** yet prove that users want Caps Lock as the trigger, will install a macOS utility, will trust local session collection, or will pay. Those are the highest-priority validation questions.

## Source set

| ID | Source | Recency | Signal used |
|----|--------|---------|-------------|
| S1 | [Reddit: What do you do while your coding agents work?](https://www.reddit.com/r/ClaudeCode/comments/1rfpzpk/what_do_you_do_while_your_coding_agents_work/) | 2026 | Lost context after waiting; scratchpads and “state of the world” notes as workarounds |
| S2 | [Reddit: After a year in Claude Code, the thing slowing me down turned out to be me](https://www.reddit.com/r/ClaudeAI/comments/1ti8cwr/after_a_year_in_claude_code_the_thing_slowing_me/) | 2026 | Parallel sessions increase mistakes and re-orientation work |
| S3 | [Reddit: What do you do while waiting on an AI code generation?](https://www.reddit.com/r/cursor/comments/1jd8e9y/what_do_you_do_while_waiting_on_an_ai_code/) | 2025–2026 comments | Waiting leads to distraction; extra context switching can add mental burden |
| S4 | [Reddit: Tried Claude Code. Hate it.](https://www.reddit.com/r/cursor/comments/1sj85kg/tried_claude_code_hate_it/) | 2026 | Poor task visibility and forced multitasking described as “mental thrashing” |
| S5 | [Hacker News: Context is the bottleneck for coding agents now](https://news.ycombinator.com/item?id=45387374) | Active in 2026 crawl | Structured summaries are already used to resume work across contexts |
| S6 | [Hacker News: Beyond agentic coding](https://news.ycombinator.com/item?id=46930565) | 2026 | Human mental models desynchronize; even three sessions can cause re-orientation errors |
| S7 | [Reddit: How I stopped losing context every time Claude resets](https://www.reddit.com/r/ClaudeCode/comments/1n2bukk) | 2025 | Technical decisions and fixes are the context users want preserved |
| S8 | [Reddit: Cross-agent knowledge and configuration sync](https://www.reddit.com/r/ClaudeCode/comments/1v3sxzq/i_built_an_mcp_server_that_syncs_knowledge_skills/) | 2026 | Developers switch among several agents and face fragmented session/config state |

S1–S4 and S6 are practitioner discussions. S7–S8 include creators describing their own solutions, so their problem statements may be influenced by product promotion.

## Top themes

### 1. The human mental model falls behind the agent

**Confidence:** High for the broad problem; medium for its frequency in CapsStack's exact target segment.  
**Frequency:** 5 of 8 source discussions.  
**Intensity:** High.

Developers repeatedly describe losing track of the plan, modified files, decisions, or even the correct session. The problem is not only the model's context window; it is the human's need to reconstruct intent after autonomous work.

Representative language:

- “I’ve lost context” — S1
- “mental model getting desynchronized” — S6
- “it’s just mental thrashing” — S4

**Implication:** Lead with human re-entry, not “AI memory.” The most defensible promise is: **understand what happened while you were away and know what to inspect next**.

### 2. Parallelism converts model latency into review and coordination load

**Confidence:** High.  
**Frequency:** 5 of 8 sources.  
**Intensity:** High.

Multiple agents appear attractive, but users report terminal hopping, merge risk, mistakes, and a growing queue of output to review. The limiting resource becomes attention and verification rather than generation speed.

Representative language:

- “The review work never finishes.” — S1
- “I can’t keep up” — S2
- “wasted time re-orienting myself” — S6

**Implication:** CapsStack should not imply that a summary replaces review. The brief should act as a **review triage layer**: what changed, what is risky, what failed, and where the user should verify first.

### 3. Waiting breaks flow even before the user fully leaves

**Confidence:** Medium.  
**Frequency:** 3 of 8 sources.  
**Intensity:** Medium to high.

Waiting periods of seconds or minutes prompt social scrolling, impatient multitasking, or “babysitting” the agent. Some users prefer physical chores because another knowledge task creates too much cognitive switching.

Representative language:

- “productive coding session slowly turns into a scrolling session” — S1
- “extra context switching actually led to more mental burden” — S3

**Implication:** The Caps Lock gesture matches a real behavioral transition: stop watching, leave the desk, and return deliberately. Test this narrative directly; the trigger itself remains unvalidated.

### 4. Users already build manual re-entry artifacts

**Confidence:** High.  
**Frequency:** 5 of 8 sources.  
**Intensity:** Medium.

Common workarounds include a scratchpad, `context.md`, “state of the world” note, explicit agent summary, plan/file list, SQLite knowledge store, or git diff. These artifacts preserve different parts of the story and require upkeep.

Representative language:

- “state of the world note” — S1
- “compact but technically precise” summary — S5
- “technical decisions” and “fixes and insights” — S7

**Implication:** Compare CapsStack with the actual default behavior—manual notes plus diffs—not only with software competitors. “No new ritual beyond flipping a key” is a promising claim to validate.

### 5. Cross-agent fragmentation exists, but it is adjacent to—not identical with—re-entry

**Confidence:** Medium.  
**Frequency:** 3 of 8 sources.  
**Intensity:** Medium.

Some developers switch between Claude Code, Codex, OpenCode, Cursor, and other tools. They want context, configuration, or memory to survive tool boundaries. Most products discussed solve **agent-to-agent continuity**; CapsStack currently solves **agent-to-human return context**.

**Implication:** Keep “works across agents” as proof of neutrality, but do not let “universal agent memory” blur the core category. CapsStack should own the moment of return.

## Jobs to be done

### Functional

- Reconstruct what happened during an unattended interval without reading every turn.
- Prioritize code review and validation based on decisions, failures, and risk.
- Distinguish projects and sessions when several agents ran concurrently.
- Preserve the intended next action across a break.

### Emotional

- Feel in control of delegated work rather than surprised by it.
- Step away without anxiety that attention loss will erase the productivity gain.
- Return without the “where was I?” tax.

### Social

- Remain the accountable engineer who understands and reviews the work.
- Explain an agent's changes and rationale to teammates without appearing to rubber-stamp output.

## Switching forces

| Force | Evidence-backed hypothesis |
|-------|----------------------------|
| Push | Transcript fatigue, terminal hopping, mental-model drift, and manual note upkeep |
| Pull | A concise, automatically scoped return brief with review priorities |
| Habit | Stay in one session, watch the agent, ask for a recap, inspect diffs, maintain `context.md` |
| Anxiety | Missing or misleading summaries, privacy, setup complexity, summary-provider cost, and losing direct visibility into the work |

## Provisional segment, not yet a persona

The source set supports a provisional segment: **experienced Mac developers who use two or more coding-agent sessions and still personally review production-bound changes**. It does not support detailed demographics, company-size claims, or multiple distinct personas. More first-party data is required before persona creation.

## Positioning and product implications

1. **Position as return-to-work infrastructure.** Avoid competing head-on with persistent-memory products unless CapsStack adds agent-to-agent continuation.
2. **Make review triage explicit.** The brief should distinguish verified completion, unverified claims, blockers, files/areas touched, and recommended checks.
3. **Demonstrate interval scoping.** Show why “what happened while I was away” is better than a generic whole-session summary.
4. **Prove trust.** Explain exactly what is collected, what reaches the selected model provider, and what is deleted.
5. **Treat multi-agent support as a wedge for power users.** The stronger the concurrency, the higher the re-entry cost—but also the higher the complexity and trust bar.

## Research gaps and next study

The next round should prioritize disconfirmation, not validation.

### Five interview targets

- 2 developers who regularly run 2+ agents in parallel.
- 2 developers who tried parallel agents and deliberately returned to one-at-a-time work.
- 1 developer who relies on manual summaries or a project context file.

### Questions to answer

1. Tell me about the last time you came back to an agent after leaving it alone. What did you do first?
2. How long did it take before you felt confident enough to review or continue?
3. What information was missing from the transcript, diff, or agent recap?
4. What is the most serious mistake caused by losing track of agent work?
5. What do you currently write down before leaving, if anything?
6. Would a keyboard-state trigger feel natural, risky, or annoying? Why?
7. What session data would you refuse to let a summarization provider process?
8. What would make you uninstall after one week?

### Minimum validation thresholds

- At least 5 independent interviews in one consistent segment.
- At least 3 unprompted accounts of re-entry delay or mental-model drift.
- A measured baseline for time-to-first-confident-action after return.
- At least 3 users choosing the Caps Lock trigger voluntarily in a one-week test.
- Evidence of weekly repeat use; installation interest alone is insufficient.
