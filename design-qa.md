# CapsStack Brand Implementation QA

final result: passed

## Comparison target

- Source visual: `Design/Brand/capsstack-brand-board.png` (1487 × 1058 px).
- Primary implementation capture: `.build/qa/menu-bar.png` (632 × 600 px, representing the 316 × 300 pt menu-bar surface at 2× density).
- Combined comparison evidence: `.build/qa/brand-menu-comparison.png`.
- Supporting native-surface captures: `.build/qa/settings.png` and `.build/qa/history.png`.

The source is an identity board rather than a pixel-exact application screen. Layout fidelity is therefore evaluated against the board's menu-popover specimen and brand rules, while the existing native macOS information architecture remains intentionally unchanged.

## Findings and fixes

### Resolved P1 — icon detail drift

The first implementation export used two summary bars, while the approved application-icon and 16 px menu-bar specimens use three. Both production masters were corrected to three evenly spaced bars, the SwiftPM resources were replaced, the macOS AppIcon set and `AppIcon.icns` were regenerated, and the menu-bar surface was captured again.

Post-fix evidence: the app icon in `.build/qa/menu-bar.png` and the focused comparison in `.build/qa/brand-menu-comparison.png` show the three-bar form.

### Resolved P2 — runtime image rendering

The first offscreen render reserved the brand-icon frame but did not paint the resource-backed image. Resource loading now resolves the packaged SwiftPM bundle to `NSImage` before constructing the SwiftUI image. The branded app icon is visible and sharp in the final menu-bar capture.

### Resolved P1 — oversized menu-bar item

The custom mark filled an 18 pt menu-bar frame with substantially more visual mass than neighboring system items. The menu-bar label now uses a 26 pt display frame so the visible mark matches neighboring menu-bar icons, with its status dot recolored by phase. The larger app icon remains the application icon and popover identity.

## Required fidelity surfaces

- Fonts and typography: native macOS system typography is retained inside the product, matching the approved guidance. The headline, supporting copy, button labels, and secondary actions have clear weight and size hierarchy with no clipping or awkward wrapping.
- Spacing and layout rhythm: the 316 pt popover keeps a spacious 16 pt outer inset, a compact brand/status header, lightweight dividers, one clear primary action, and separated secondary actions. No card nesting or decorative container clutter was introduced.
- Colors and visual tokens: Ink Aubergine, Aged Brass, Petrol Slate, Rice Paper, and Bone are implemented as centralized adaptive tokens. System red remains reserved for failure. State color is always paired with text or an icon.
- Image quality and asset fidelity: the approved mark is shipped as a 1024 px RGBA app-icon master, a compact 64 px RGBA menu-bar asset, a complete macOS AppIcon asset set, and compiled `AppIcon.icns`.
- Copy and content: existing concise Japanese product copy remains intact. No invented tagline or feature claim was added.
- Icons: the custom CapsStack mark is used for the application and popover identity. The menu-bar status item uses the compact mark with a phase-aware status dot; standard actions continue to use macOS SF Symbols.
- States and interactions: the primary away/return action, history opening, settings link, quit action, native history selection, and settings controls remain functional code paths. The brand pass did not replace controls with static chrome.
- Accessibility: the menu-bar item exposes `CapsStack — <current state>` as its accessibility label. The visible state dot has a textual state title, and destructive/error meaning does not rely on brand color.

## Intentional differences and P3 follow-up

- The source board uses English specimen labels; the product correctly keeps its existing Japanese UI.
- Offscreen native captures show inactive-control styling and do not reproduce every window-chrome detail. This does not change the implemented brand tokens or application layout.
- The full wordmark remains a visual brand reference and is not placed inside the compact product UI, where the app icon and native title are more appropriate.

## Verification checklist

- [x] App icon matches the approved three-bar symbol; the menu bar uses the original compact mark with a phase-aware status dot.
- [x] Brand colors are centralized and adaptive for light/dark appearance.
- [x] Menu-bar, history, and settings surfaces compile with the new styling.
- [x] Resource-loading regression test passes.
- [x] Branded-surface rendering test passes.
- [x] SwiftPM test suite passes.
- [x] Staged `.app` bundle builds and launches successfully.
