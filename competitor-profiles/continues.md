# continues — Quick Profile

**URL:** https://github.com/yigitkonur/cli-continues  
**Generated:** 2026-09-02  
**Depth:** Quick scan; SEO and review metrics unavailable

## At a Glance

| Metric | Value |
|--------|-------|
| Tagline | Resume any AI coding session in another tool |
| Target audience | Developers switching coding CLIs after limits or preference changes |
| Pricing starts at | Free, open source |
| Free tier/trial | Entire product is MIT licensed |
| Public adoption signal | About 1.4k GitHub stars at scan time |
| Domain rank / traffic | Not measured |

## Positioning

`continues` is a CLI-native portability layer. It discovers local session formats, builds a structured handoff, and resumes work in the same or a different coding agent. Its concrete trigger is rate limiting or tool switching.

## Product and pricing

- Run with `npx continues` or install globally.
- Current documentation lists 16 tools and 240 cross-tool paths.
- Supports session listing, inspection, same-tool resume, cross-tool handoff, and machine-readable output.
- MIT licensed; no paid plan found.

## Strengths

- Crisp, urgent trigger: a tool limit interrupts active work.
- Larger documented source/target matrix than CapsStack's current collector list.
- Minimal CLI-native adoption path and transparent open-source implementation.
- Actually continues work in a target agent, which CapsStack intentionally does not do.

## Weaknesses relative to CapsStack

- Optimizes agent-to-agent continuation, not human comprehension after absence.
- Launching or resuming target tools creates a different security and workflow boundary.
- Requires the user to invoke a CLI and choose a session/target rather than using an ambient macOS return trigger.
- No native history/notification experience comparable to a macOS utility.

## Competitive implication for CapsStack

This is the clearest risk of category confusion. CapsStack messaging must say that it **does not migrate or resume sessions**; it prepares the human to decide what happens next. “Return brief” and “review before continuing” should remain central.

## Raw Data Sources

- `competitor-profiles/raw/continues/2026-09-02/scrapes/npm-and-github.md`

