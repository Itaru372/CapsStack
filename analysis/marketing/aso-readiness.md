# ASO Readiness: CapsStack

**Store:** Apple Mac App Store candidate  
**Audit date:** 2026-09-02  
**Brand tier:** Challenger — no public CapsStack listing, rating base, or store traction was found  
**Overall score:** N/A — scoring a nonexistent listing as 0 would be misleading

## Executive conclusion

**ASO is not CapsStack's immediate acquisition lever.** The repository currently builds a directly distributed `.pkg`, its entitlements file is empty, and its core behavior reads hidden CLI session directories and launches separately installed CLI executables. Apple requires Mac App Store apps to use App Sandbox. Apple also documents that sandboxed apps normally access external files through explicit user selection/security-scoped bookmarks and cannot run programs outside the app bundle, container, or app-group containers merely through user-selected-file entitlements.

That makes Mac App Store submission a product-architecture decision, not a metadata task. Before producing final screenshots or keywords, run a sandbox feasibility spike. Until then, prioritize a notarized direct-download page and web discoverability.

Sources:

- [Apple: App Sandbox is required for Mac App Store distribution](https://developer.apple.com/documentation/security/app-sandbox)
- [Apple: accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Apple: Mac distribution channel comparison](https://developer.apple.com/macos/distribution/)
- [Apple App Review Guidelines, including Mac App Store requirements](https://developer.apple.com/app-store/review/guidelines/)

## Readiness scorecard

| Dimension | Score | Status | Key issue |
|-----------|-------|--------|-----------|
| Title & subtitle | N/A | Draftable | No App Store Connect metadata exists |
| Description | N/A | Draftable | No listing; pricing and conversion action are unknown |
| Visual assets | N/A | Partial | Strong icon exists; no store screenshot set or preview video found |
| Ratings & reviews | N/A | Missing | No public listing or ratings |
| Metadata & freshness | N/A | Blocked | Store category, localization, privacy nutrition label, and version record do not exist |
| Conversion signals | N/A | Blocked | Price, developer-store identity, social proof, and install conversion data are unknown |

## Distribution feasibility gate

### Current implementation evidence

- `Packaging/CapsStack.entitlements` is an empty dictionary; App Sandbox is not enabled.
- Collectors resolve hidden home-directory locations such as `.codex`, `.claude`, `.continue`, `.qwen`, and `.local/share` automatically.
- Summarization resolves and runs external CLIs installed in user-controlled locations.
- The direct `.pkg` includes a companion helper CLI.

### Likely Mac App Store conflicts

This is an inference from Apple's documented sandbox rules and the local implementation:

1. Automatic access to every supported hidden session directory would likely need explicit folder selection plus persistent security-scoped bookmarks.
2. Launching arbitrary separately installed summarizer executables appears incompatible with the normal App Sandbox execution boundary.
3. The helper and persistence locations would need to inherit or comply with the containing app's sandbox.
4. Existing local history would move into the app container or need a migration strategy.
5. App Review would need clear explanations of Accessibility permission, session-folder access, supported third-party tools, and the data sent to a selected model provider.

### Go/no-go spike

Time-box a sandbox prototype before ASO production work:

- Enable `com.apple.security.app-sandbox` in an experimental target/branch.
- Add read-only user-selected folder access and app-scoped security bookmarks.
- Prove at least Codex and Claude session collection after relaunch.
- Prove whether an external installed summarizer CLI can be invoked; expect this to be the hardest blocker.
- Validate Caps Lock monitoring and Accessibility behavior under sandbox.
- Confirm the bundled `capsstack` helper and shared history contract.

If external summarizers cannot operate compliantly, keep direct distribution or define a materially different App Store edition. Do not silently replace the product's current privacy/safety boundary with an embedded cloud API just to qualify for the store.

## Public listing check and category signal

A search for `site:apps.apple.com "CapsStack"` did not return a CapsStack listing. It did surface several adjacent products, showing that **Developer Tools** is the likely shelf:

| Listing | Title | Subtitle | Relevance |
|---------|-------|----------|-----------|
| [AI Agent Monitor: CLI Status](https://apps.apple.com/us/app/ai-agent-monitor-cli-status/id6778941425?mt=12) | 28/30 chars | “Menu bar alerts for coding” (26/30) | Directly targets Mac menu-bar monitoring of CLI agents and “stop babysitting the terminal” |
| [AI Agent Usage](https://apps.apple.com/us/app/ai-agent-usage/id6770159263?mt=12) | Brand-led | “Cost, insights, & goals for AI” | Demonstrates local-session analysis and privacy positioning in Developer Tools |
| [CodeVibe](https://apps.apple.com/us/app/codevibe/id6756500217) | Brand-led | “Remote AI Coding Agent Control” | Targets away-from-desk supervision from iPhone |

These listings make `coding agent`, `CLI`, `menu bar`, `session`, `summary`, `monitor`, and `developer` semantically relevant candidates. Exact search volume and ranking difficulty require paid ASO data or App Store Connect/Search Ads evidence.

## Draft Apple metadata

These are challenger-style drafts, not final choices. They avoid repeating title/subtitle terms in the hidden keyword field.

### English (US)

**Recommended title:** `CapsStack: Coding Agent Brief` — 29/30 characters  
**Recommended subtitle:** `Return caught up, review next` — 29/30 characters  
**Recommended keyword field:** `developer,assistant,session,summary,history,workflow,productivity,mac,cli,review` — 80/100 bytes

Why:

- `coding agent` states the category in the strongest indexed field.
- `brief` differentiates from monitors and full orchestration tools.
- The subtitle communicates the human outcome and review posture without repeating title words.
- The keyword field captures adjacent discovery terms while avoiding competitor trademarks and title/subtitle duplication.

**Promotional text draft:** 167/170 characters

> Step away from your Mac while coding agents work. Return to one concise brief with progress, decisions, blockers, and next steps—without resuming the original session.

**Description opening draft:**

> Stop rereading long agent transcripts when you return to your Mac. (66 characters)  
> CapsStack turns the time you step away into a concise return brief: progress, decisions, blockers, and next steps. (114 characters)  
> Flip Caps Lock on when you leave and off when you return. (57 characters)

The Apple long description is not indexed, so use it for conversion: show the problem, the three-step flow, supported-source boundaries, safety model, privacy qualification, macOS/CLI requirements, and a direct install CTA.

### Japanese

**Recommended title:** `CapsStack：AI作業復帰ブリーフ` — 20/30 characters  
**Recommended subtitle:** `離席中の進捗・判断・次の一手を要約` — 17/30 characters  
**Recommended keyword field:** `開発,エージェント,セッション,要約,履歴,進捗,ターミナル,生産性` — 88/100 bytes

The Japanese keyword field must be budgeted by UTF-8 bytes, not characters. Validate every localized keyword set before submission.

## Visual asset assessment

### Icon

The production master is a strong starting point:

- Distinctive C-shaped mark, no text, and readable large forms.
- Green status dot communicates active state and creates a memorable focal point.
- Dark matte tile differentiates from the warm in-app palette.

Before submission, verify recognizability at 16, 32, 64, and 128 px and test against dark/light App Store surfaces. The subtle material texture and shadows should not erase the three summary lines at small sizes.

### Six-screenshot storyboard

Apple allows up to ten Mac screenshots; use six, with the first three telling the complete value story.

1. **“Step away. Come back caught up.”** — show the completed return brief, not setup.
2. **“One flip marks the work you missed.”** — show Caps Lock ON → away → OFF as a simple sequence.
3. **“Progress. Decisions. Blockers. Next.”** — zoom into the four actionable sections.
4. **“Your coding agents, one return view.”** — show multiple supported sources without overcrowding the frame.
5. **“Built around local, explicit boundaries.”** — visualize collection, selected summarizer, deletion-after-success, and opt-in telemetry accurately.
6. **“Keep a useful history—or export Markdown.”** — show history selection and export/copy.

Use five-to-seven words per overlay, one benefit per screenshot, and actual in-app UI. Do not imply that all processing is on-device: the selected summarizer may send input to its provider.

## Keyword opportunities

| Keyword | Why it matters | Placement | Priority |
|---------|----------------|-----------|----------|
| coding agent | Defines the emerging category and appears in adjacent listings | Title | High |
| brief | Differentiates from monitoring, remote control, and persistent memory | Title | High |
| session summary | Matches the functional job without promising session migration | Keyword field / description | High |
| CLI | Qualifies the supported workflow and appears in competitor metadata | Keyword field | High |
| review | Aligns with the human bottleneck found in research | Subtitle / keyword field | High |
| menu bar | Relevant interaction model, but not the core outcome | Description / screenshot | Medium |
| developer productivity | Broader shelf with more competition | Keyword field / description | Medium |
| agent monitor | High adjacent relevance but may set an expectation of live monitoring | Description only, test carefully | Low |

Do not use `Codex`, `Claude`, `Cursor`, or other third-party product names as hidden keywords. If compatibility names appear in the description or screenshots, keep them accurate and review trademark guidelines.

## Top three quick wins

### 1. Lock the channel decision memo

**Impact:** High | **Effort:** <1 hour  
Document “direct distribution now; sandbox spike before Mac App Store” so ASO asset work does not begin under a false assumption.

### 2. Reserve the metadata drafts

**Impact:** Medium | **Effort:** <30 minutes  
Keep the English and Japanese title/subtitle/keyword drafts above in a release checklist; verify name availability inside App Store Connect before treating it as reserved.

### 3. Turn existing QA captures into a screenshot shot list

**Impact:** Medium | **Effort:** <1 hour  
Map the six frames above to existing demo states and record what new capture fixtures are missing. Do not export final art until the store decision is green.

## Priority action plan

### This week

1. Decide whether the goal is Mac App Store reach, direct-download growth, or both.
2. Run the sandbox feasibility spike around external CLI execution and persistent read access.
3. Confirm business model and price; listing conversion copy cannot be final without them.

### This month

4. If Mac App Store is feasible, create App Store Connect metadata and privacy disclosures.
5. Produce six localized Mac screenshots from real UI states.
6. Prepare reviewer notes and a deterministic demo path that does not depend on private session logs.

### Next quarter

7. Launch to a small beta, gather at least 30 activated opted-in users, and validate repeat value.
8. After listing launch, track impressions, product-page views, downloads, first successful brief, and retention as separate funnel stages.
9. Test screenshot order before investing in preview video.

## Limitations

- No public CapsStack listing, App Store Connect data, keyword field, ratings, screenshots, product-page conversion, or Search Ads data were available.
- Exact keyword volume, difficulty, and ranking positions were not measured.
- Competitor screenshots were not fully audited in-browser; only listing metadata and accessible page content were used.
- App Sandbox feasibility is a reasoned technical risk, not a completed App Review determination.
- Name availability must be confirmed in App Store Connect, not inferred from public search alone.
