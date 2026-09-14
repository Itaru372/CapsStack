# CapsStack Brand and Product UI Guide

Status: current implementation

Last reviewed: 2026-09-13

![CapsStack brand board](capsstack-brand-board.png)

The brand board is the approved identity reference for the mark, wordmark, and
overall character. Its warm color studies and example panels are not a literal
specification of the current app UI. The product UI is defined by the adaptive
tokens in `Sources/CapsStack/Support/BrandStyle.swift` and documented below.

## Source of truth

When this guide and the shipped product disagree, use these sources in order:

1. `Sources/CapsStack/Support/BrandStyle.swift` for product UI and state colors.
2. The master assets in this directory for the app and menu-bar marks.
3. This guide for intent and application rules.
4. `capsstack-brand-board.png` for identity character and mark geometry.

## Brand idea

CapsStack is a quiet, dependable macOS utility that holds the thread of
AI-assisted work while its user steps away. It should feel like a focused work
instrument: native, calm, precise, and trustworthy rather than decorative or
futuristic.

The core promise is: **Step away. Come back caught up.**

The current product expression combines:

- a near-black, high-contrast app icon;
- cool neutral surfaces that sit naturally beside macOS system UI;
- a restrained deep-teal signal color for selection and the next action;
- generous spacing, compact type, thin borders, and limited visual effects.

## Mark

The approved mark is the rounded geometric C-shaped enclosure with:

- one fixed circular status indicator in the upper-right area;
- three short horizontal summary lines beneath it;
- a large open counter that remains legible at menu-bar size.

The mark geometry is locked. Do not redraw, rotate, skew, outline, add effects,
move the status dot, or change the relationship between the enclosure and the
three lines.

### App icon

The production icon uses a near-black charcoal tile, an off-white mark, and a
large saturated green status dot with a charcoal keyline. The subtle material
depth in the master is intentional, but the finish should remain restrained.
Do not recolor or rebuild the app icon from runtime UI tokens.

### Menu-bar icon

Use the separate compact menu-bar asset. At runtime, the enclosure and summary
lines are tinted black or white to follow the active appearance. The circular
cutout is drawn separately as the current phase indicator.

The menu-bar image is not a template image because its glyph and indicator need
independent colors. Its accessibility label must state the current phase.

## Product UI color

The application uses adaptive semantic tokens. Hex values describe the current
sRGB implementation; do not replace semantic macOS colors with fixed hex values
where the implementation deliberately uses a system color.

### Primary UI tokens

| Token | Light | Dark | Current use |
| --- | --- | --- | --- |
| Canvas | `#F8FAFA` | `#14191C` | Main window background |
| Panel | `#EFF3F3` | `#1A2124` | Sidebars, quiet grouped areas, status capsules |
| Card | `#FFFFFF` | `#222B2E` | Raised content and settings rows |
| Border | Primary at 10% opacity | Primary at 10% opacity | Dividers and card outlines |
| Signal | `#087069` | `#80D9C9` | Tint, selection, links, icons, next actions |

Signal is the normal interactive accent. Selected backgrounds generally use it
at 8–12% opacity. Large saturated teal fields are not part of the current UI.

### Supporting identity tokens

These tokens remain available for identity and state-specific use, but they are
not the default app background or control tint.

| Token | Light | Dark | Current use |
| --- | --- | --- | --- |
| Ink Aubergine | `#352A38` | `#EAE1EC` | Identity foreground when a branded composition needs it |
| Aged Brass | `#B89B48` | `#D2B75B` | Reserved identity accent |
| Petrol Slate | `#4F7174` | `#78A2A5` | Summarizing phase |
| Rice Paper | `#EFE7D8` | `#252128` | Reserved warm identity surface |
| Bone | `#F7F3EA` | `#2D2830` | Reserved warm raised surface |

The earlier `Brief Signal #C6F24E` swatch shown in identity explorations is not
a runtime product UI token. The app icon's green is embedded in the reviewed
raster master; product controls use Signal or a semantic macOS state color.

### Phase and semantic colors

| Phase or meaning | Color |
| --- | --- |
| Idle | macOS secondary/system gray |
| Away | macOS system green |
| Summarizing | Petrol Slate |
| Failed | macOS system red |
| Disabled | macOS system gray |
| Warning or attention | macOS semantic orange |
| Destructive action | macOS semantic red and destructive button role |

State color must never be the only signal. Pair it with a label, icon, status
text, or control state.

## Typography

Use native macOS system typography throughout the product. The current hierarchy
is compact and sturdy:

- `28–32 pt`, bold: primary onboarding and workspace titles;
- `title2` / `title3`, bold or semibold: section and card titles;
- `headline`: row and item titles;
- `body` / `callout`: primary reading and explanatory copy;
- `footnote` / `caption`: metadata, status detail, and supporting labels;
- monospaced digits: dates, durations, counts, versions, and other scan-heavy data.

Do not introduce a custom runtime font, futuristic display type, or use
monospaced text as general body copy. The wordmark on the brand board is a visual
reference, not a named production font or a runtime text treatment.

## Layout and component language

The current app follows native macOS information architecture:

- use a quiet left sidebar and a spacious content workspace for History,
  Settings, and Setup;
- use 28 pt content padding for normal workspaces and 36 pt for onboarding;
- keep primary content at a readable maximum width rather than stretching it
  across the full window;
- use cards only to group meaningful units, not as decoration;
- use thin 10%-opacity borders instead of heavy shadows;
- use corner radii from 8–12 pt for fields, rows, and cards, with smaller radii
  for compact sidebar selections;
- use capsules only for compact statuses and badges;
- use SF Symbols for product actions and concepts, and supplied agent artwork
  for third-party agent identity;
- keep animation short and functional; the setup flow currently uses a 0.2 s
  ease-in-out transition.

The design should stay readable at the minimum supported window sizes. Preserve
native focus, scrolling, keyboard, and window behavior instead of replacing them
with custom interaction patterns.

## Voice and copy

Lead with the user's return-to-work outcome. Copy should be calm, direct, and
specific about what CapsStack found, what it could not find, and what action is
safe to take next.

- Prefer “return brief,” “away,” “summarizing,” and “resume” language.
- Explain pending, empty, permission, and failure states without blame.
- Keep privacy language concrete: history and away notes stay on this Mac, while
  the selected summarizer CLI may process supplied input according to its service.
- Avoid generic AI hype, anthropomorphic claims, and urgency where none exists.

## Accessibility

- Preserve native controls and semantic roles whenever possible.
- Give icon-only controls an accessibility label.
- Include the current state in the menu-bar item's accessible description.
- Never rely on color alone for state, warning, selection, or completion.
- Keep primary text on Canvas, Panel, and Card surfaces at system semantic
  foreground colors so appearance and increased-contrast settings can adapt.
- Verify keyboard traversal, focus visibility, VoiceOver labels, reduced motion,
  and light/dark appearance after meaningful UI changes.

## Do and do not

Do:

- keep the app mostly native, neutral, and information-first;
- reserve Signal for selection, navigation emphasis, and the next useful action;
- preserve semantic system colors for status, warnings, and destructive actions;
- use spacing, alignment, hierarchy, and thin separators to create structure;
- support both light and dark appearances with the adaptive tokens.

Do not:

- apply the warm brand-board canvas literally to current product screens;
- use Aged Brass as the default button or selection color;
- use the app icon's bright green as the general control tint;
- add blue-purple gradients, neon cyan, glassy decoration, or large saturated fields;
- add heavy shadows, ornamental cards, or custom controls without a functional need;
- redraw the mark or merge the app icon and menu-bar assets.

## Asset inventory

| Asset | Role |
| --- | --- |
| `capsstack-brand-board.png` | Identity character and mark reference |
| `capsstack-app-icon-master.png` | Reviewed 1024×1024 app-icon master |
| `capsstack-menu-bar-master.png` | High-resolution compact mark master |
| `Sources/CapsStack/Resources/CapsStackAppIcon.png` | Runtime app image |
| `Sources/CapsStack/Resources/CapsStackMenuBar.png` | Runtime menu-bar mask/source |
| `Packaging/Assets.xcassets/AppIcon.appiconset/` | Packaged macOS icon exports |

The app-icon master, runtime 1024 px image, and packaged 1024 px export should
remain byte-identical. Generate smaller package exports from the reviewed master.
Keep the menu-bar source separate so its status indicator can change color at
runtime without altering the app icon.

## Implementation and verification

- Product UI tokens and branded image rendering:
  `Sources/CapsStack/Support/BrandStyle.swift`
- Light/dark visual rendering coverage:
  `Tests/CapsStackTests/BrandRenderingTests.swift`
- Resource packaging checks:
  `Tests/CapsStackTests/ModelTests.swift`
- UI QA checklist and captured-output procedure: `design-qa.md`

For UI changes, render the branded surfaces in both appearances, run the full
test suite and strict build, and inspect the generated images rather than relying
on compilation alone.
