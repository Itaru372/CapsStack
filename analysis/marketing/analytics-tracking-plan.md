# CapsStack Analytics and Measurement Plan

**Generated:** 2026-09-02  
**Current tool:** PostHog native Swift SDK  
**Privacy posture:** Explicit opt-in; no SDK initialization while off; manual aggregate events only; no session content, memo text, paths, session/model IDs, raw errors, screen capture, replay, or autocapture.

## Measurement objective

The immediate business question is not “How many events can CapsStack collect?” It is:

> Does CapsStack repeatedly reduce the friction between returning to agent work and taking the next confident human action?

Because the current app cannot directly observe “confidence” or the user's next editor action without invasive monitoring, measurement needs a combination of privacy-safe behavioral proxies and lightweight first-party feedback.

## Recommended metric hierarchy

### North-star candidate

**Weekly users with at least one completed and consumed return brief**

Definition: distinct opted-in installations that produce a successful brief and then view, copy, or export a completed brief within the same week.

Why: raw launches and brief generation are not enough; consumption is the closest existing signal that the brief entered the user's workflow.

### Activation

**First successful return brief within 24 hours of setup completion**

Supporting measures:

- Setup completion rate among telemetry-enabled users.
- Provider connection test success rate.
- First brief request → completion rate.
- Empty-brief rate on first attempt.
- Time bucket from setup completion to first successful brief.

### Core product health

- Return brief completion rate = completed / requested.
- Empty rate = empty / requested.
- Failure rate by stage and controlled failure code.
- Retry recovery rate = retry completed / retry started.
- Fallback utilization and success rate.
- Summary latency distribution by provider.
- Brief consumption rate = users consuming / users completing.

### Retention

- W1 and W4 retained activated users.
- Weekly briefs completed per activated user, bucketed.
- Consecutive active weeks with at least one completed-and-consumed brief.
- Share of users returning after a failed or empty brief.

### Qualitative outcome

**Brief helpfulness pulse:** optional one-click response after selected completed briefs.

- `helpful`
- `missing_important_context`
- `too_verbose`
- `incorrect_or_misleading`

Do not collect free-form feedback in product telemetry. If free-form feedback is later offered, use an explicit separate submission flow with clear content handling.

## Current instrumentation audit

| Existing event | Decision it supports | Assessment |
|----------------|----------------------|------------|
| `app launched` | Basic opted-in activity and retention | Useful, but first pre-consent launch is intentionally absent |
| `telemetry enabled` | Consent adoption | Correct and explicit |
| `return brief requested` | Demand, away-duration mix, source count, memo use | Strong; properties are coarse and privacy-safe |
| `return brief completed` | Reliability, provider/fallback mix, latency, session count | Strong core outcome event |
| `return brief empty` | Collector/setup mismatch and unsupported workflows | Useful; needs segmentation by first attempt vs repeat |
| `return brief failed` | Failure diagnosis | Strong controlled taxonomy; no raw error leakage |
| `summary retry started/completed/failed` | Retry recovery | Strong |
| `provider connection tested` | Setup troubleshooting | Useful |
| `return brief consumed` | View/copy/export behavior | Valuable, but repeat views may inflate event counts |

## Important gaps

1. **Setup completion is not measured.** We cannot separate users who consented but abandoned setup from users ready to create a brief.
2. **Activation is not identifiable.** `brief completed` does not say whether it is the installation's first success.
3. **Consumption can overcount.** Viewing may fire on repeated history selection, so use distinct users/funnels before raw event totals and consider once-per-entry-per-app-session deduplication without transmitting entry IDs.
4. **No quality signal exists.** A completed summary may be unhelpful or wrong.
5. **No distribution funnel exists.** The repository has no public landing-page/download analytics, so acquisition → install conversion cannot be evaluated.
6. **No version property is intentionally defined in the custom schema.** If the SDK's standard metadata is retained, verify app version/build are available before adding duplicates.
7. **Opt-in selection bias is material.** Results describe privacy-comfortable users, not all users. Never present opt-in telemetry as population-wide behavior without noting this.

## Proposed event additions

These are recommendations only; no telemetry code was changed.

| Event name | Description | Properties | Trigger | Decision |
|------------|-------------|------------|---------|----------|
| `setup_completed` | Initial setup becomes usable | `collector_count_bucket`, `summarizer`, `telemetry_enabled=true` | Final setup action, only if already opted in | Find setup drop-off and provider mix |
| `first_return_brief_completed` | First successful brief on this installation | `provider`, `fallback_used`, `away_duration_bucket`, `summary_duration_bucket` | First persisted completed history entry after opt-in | Measure activation |
| `brief_feedback_submitted` | One-click structured quality feedback | `rating_reason`, `status=completed` | User explicitly taps a feedback option | Decide whether summary quality or workflow fit is limiting use |
| `notification_opened` | User opens the relevant brief from a completion notification | `status` | Notification response action | Measure whether notification closes the return loop |

Avoid `onboarding_step_completed` unless each step clearly drives a distinct decision. The current four-step setup is small; `setup_completed` plus provider-test success is likely enough.

## Property rules

- Keep object/action event names lowercase with underscores for new events, even though existing human-readable names should not be renamed casually because that would split historical data.
- Use enums, booleans, and coarse buckets only.
- Never send repository names, file names, paths, prompts, summary text, memo text, model IDs, session IDs, terminal output, exact timestamps beyond SDK defaults, or raw error messages.
- Keep `source_count` coarse if re-identification risk increases at scale; consider using the existing count buckets consistently.
- Document every property value and treat renames as schema migrations.

## Funnels and saved insights

### Funnel A — activation

1. `telemetry enabled`
2. `setup_completed`
3. `return brief requested`
4. `first_return_brief_completed`
5. `return brief consumed` with `status=completed`

Break down by summarizer, source-count bucket, memo presence, fallback use, and app version where safely available.

### Funnel B — reliability

1. `return brief requested`
2. One of `return brief completed`, `return brief empty`, or `return brief failed`
3. If failed: `summary retry started`
4. `summary retry completed` or `summary retry failed`

### Funnel C — repeat value

1. First week with completed + consumed brief
2. Week 1 return
3. Week 4 return

Measure retention using distinct anonymous installations, not event totals.

## Decision thresholds for an early beta

These are initial operating thresholds, not industry benchmarks.

| Signal | Green | Investigate | Likely action |
|--------|-------|-------------|---------------|
| Brief completion rate | ≥85% | <85% | Prioritize collector/provider reliability before acquisition |
| First-attempt empty rate | ≤10% | >10% | Improve detection, setup copy, and unsupported-source guidance |
| Retry recovery | ≥60% | <60% | Rework retry diagnostics or fallback behavior |
| Completed-brief consumption | ≥70% of activated opted-in users | <70% | Improve notification, brief salience, or history UX |
| W4 retained activated users | ≥30% | <30% | Validate frequency of the job and trigger fit before monetization |
| Helpful feedback | ≥70% helpful | <70% | Improve brief structure/accuracy before expanding feature scope |

With fewer than roughly 30 activated opted-in installations, treat percentages as directional and inspect individual research feedback rather than optimizing small-number fluctuations.

## Distribution measurement plan

If a website or release-download page is introduced, track the minimum viable funnel:

| Event | Properties | Notes |
|-------|------------|-------|
| `landing_page_viewed` | `source`, `medium`, `campaign`, `content` | Aggregate web analytics with consent requirements respected |
| `download_clicked` | `asset_type`, `release_channel`, UTM fields | Primary web conversion |
| `install_guide_viewed` | `platform=macos` | Diagnoses installation friction |
| `release_notes_viewed` | `version` | Optional trust/upgrade signal |

The app cannot reliably join web visitors to installations without creating more persistent attribution data. For an early privacy-first beta, compare aggregate weekly downloads with anonymous first activations rather than building cross-device identity.

## Validation checklist

- Confirm no event fires before opt-in and the SDK remains uninitialized while off.
- Confirm every new event's properties are tested against an allowlist.
- Confirm no duplicate completion or feedback events.
- Confirm opt-out stops future capture and preserves no new person profile.
- Validate funnels with a dedicated test PostHog project and synthetic data only.
- Review dashboards for denominators and opt-in bias before sharing conclusions.
- Revisit the event vocabulary quarterly; remove events that do not drive decisions.
