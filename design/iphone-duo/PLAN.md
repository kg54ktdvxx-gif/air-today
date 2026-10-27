# Air Today on iPhone Duo — plan

Research date: 27 October 2026. Status: **plan, awaiting approval**. Nothing implemented yet.
Toolchain: Xcode 27.1 (27A9275), iOS 27.1 SDK. Deployment target iOS 18, so every Duo API below is gated with `#available(iOS 27.1, *)`.

## 1. Research log

Claims are tagged REQ (Apple requirement), REC (Apple recommendation), FACT (documented API or behaviour, or verified locally), DECISION (this project), UNVERIFIED.

| Claim | Tag | Source |
|---|---|---|
| Outer display 466 × 678 pt (1398 × 2034 px @3x), portrait. Inner display 669 × 951 pt (2007 × 2853 px @3x), natively landscape (`nativeOrientation 270`), so 951 × 669 pt held wide | FACT (local) | Simulator profile `iPhone Duo.simdevicetype/…/capabilities.plist`; `simctl io enumerate` |
| Apple's marketing specs give the inner display as 1878 × 2670 px. The screenshot spec and the simulator say 2007 × 2853 | UNVERIFIED (conflict) | apple.com/iphone-duo/specs vs screenshot specifications |
| Outer display: compact width, regular height in portrait. Inner display: regular in both | FACT | Tech talk 111461 |
| The inner display ignores supported interface orientations. The outer display honours them | FACT (talk wording conflicts; Apple forum resolves it) | 111461; forums thread 847644 |
| Built with the iOS 27.1 SDK, an app "extend[s] to use the full display, with toolbars and tab bars appearing vertically below the status bar"; "make sure your app's content adapts to the bars becoming vertical" before shipping | REQ | developer.apple.com/iphone-duo/prepare |
| Toolbars, tab bars and navigation controls move to the side, except on the inner display in portrait. Only bars from navigation containers move; a custom bar doesn't | FACT | HIG "Designing for iPhone Duo"; Preparing your app for iPhone Duo (technology overview) |
| `EnvironmentValues.toolbarVerticalEdge: HorizontalEdge?`, which Apple says to "use … to position custom bars or other UI relative to the system's bar placement" | FACT (iOS 27.1) | docs swiftui/environmentvalues/toolbarverticaledge (checked directly) |
| Reserved regions: outer camera (always present), inner camera (only while active), the fold (a `division` when partially open) | FACT | HIG |
| `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` → `[ReservedRegion]`. `.includeInactive` returns regions not currently active, which "still [have] a frame, so you can leave room for it. This keeps your layout from jumping" | FACT (iOS 27.1) | docs swiftui/geometryproxy/reservedregions (checked directly); swiftui/reservedregion |
| "Most apps don't need to check for reserved regions"; scroll containers don't split around a division; continuous scrolling content doesn't displace | REC | swiftui/reservedregion; talk 111463 |
| "Move only what's necessary … favor small adjustments over rearrangement"; "Avoid extreme layout changes as people fold the device" | REC | HIG |
| "Avoid placing an arrangement view inside a navigation split view, list, scroll view" | REC | Technology overview |
| "You don't want just a stretched out iPhone app"; "Avoid fixed widths, breakpoints, or any metrics tied to a specific screen" | REC | Talk 111466 |
| A hinge API exists (`onHingeChange(isEnabled:_:)`, iOS 27.1). It's meant "for driving interactions or effects. For layout, use the arrangement and region APIs" | FACT / REC | Talk 111464 |
| No Duo-specific Info.plist key. iOS 27 ignores `UIRequiresFullScreen` and resizes the scene anyway (TN3192) | FACT | Talk 111461; Xcode App Resizability skill |
| Duo App Store screenshots: 1398 × 2034 (outer) and 2853 × 2007 (inner). They earn an "optimized for iPhone Duo" badge, and become required from April 2027 | REQ (date's scope conflicts between two Apple pages) | Screenshot specifications; Apple news kkphp5qo |
| In the Duo simulator, most app extensions (our widgets) can't run, and VoiceOver and Accessibility Inspector can't read screen content in Device Hub | FACT | Xcode 27.1 / 27.2 release notes |
| Folding is driven from Device Hub's Closed, Partially Open and Open buttons. There's no `simctl` or XCUITest control for it (checked locally) | FACT | Device Hub docs; local search of simctl and XCTest |
| HIG Motion has no folding or resizing guidance | FACT | HIG Motion (last change Sep 2025) |

## 2. Discovery brief

- **Product:** answers "is it a good time to be outside here?" in plain words over a sky that shows the air. Then it covers which activities are fine, when the air will be cleanest, and what's coming.
- **Users:** people who decide daily whether to go out, such as runners, cyclists, parents and people with asthma. They have up to six saved places.
- **Primary content:** the verdict, number and band (the hero).
- **Secondary content:** Activities (with the best time), Forecast (hourly chart, then later days), Details (weather, nearby stations, map).
- **Navigation:** swipe between places; a dots menu to jump or add a city; a gear that pushes Settings.
- **Presentations:** sheets for search, the scale explainer and advice; the map as a full-screen cover.
- **Brand:** full-bleed atmosphere photo per air band, white type with sky-tinted shadows, glass cards, SF Pro.
- **Constraints:**
  - SwiftUI with a scene-based lifecycle, which iOS 27's scene requirement already satisfies.
  - Deployment target iOS 18.
  - Portrait only, with `UIRequiresFullScreen` = true.
  - 1.4.0, built with the 27.1 SDK, is in App Review. It will run full-display on Duo with today's layout.
- **Assumption:** no user research exists. The expected benefit of the inner display (answer and detail side by side) is a design hypothesis.

## 3. Baseline: today's build on iPhone Duo

Outer display, captured 27 Oct, in `baseline/`:

1. The status bar is a vertical column down the right edge (camera, time, battery). Air Today's pages ignore it:
   - cards run under the column, and the chart's "Sensitive" and "Moderate" labels sit inside it
   - the hero centres across the full width, not the usable width
2. The top bar's blur respects the safe area and stops at 375 pt, but the scrolling content beneath doesn't. So scrolled card text passes under the time and battery with nothing behind them.

Cause, found by applying Apple's App Resizability skill (Xcode 27.1, `IDEIntelligenceChat.framework/…/app-resizability*`) by hand:

- **Prerequisites:**
  - Launch screen: passes (`UILaunchScreen`).
  - iPad orientations: fail. Portrait only, so upside-down, landscape left and landscape right are missing.
  - Full-screen opt-out: fails. `UIRequiresFullScreen` is set, iOS 27 ignores it, and the skill says to keep it until resizing is verified at runtime.
- **Detection:**
  - `LocationPager.swift:160`: a bare `.ignoresSafeArea()` on the paging scroll view, which is content, not a backdrop (Rule 13).
  - `VerdictHero.swift:64` / `DesignSystem.swift:38`: `heroTopInset = 112`, a literal standing in for status bar plus top bar (Rule 13: delete stand-in literals).
  - The other `ignoresSafeArea()` calls are on backgrounds and scrims, which is correct.
  - No `UIScreen.main`, orientation, idiom or app-delegate use.

Inner display: **not captured yet**. Folding needs Device Hub's buttons, and this session can't click them because it has no Accessibility permission.

## 4. Adaptive layout decision matrix

| Screen | Outer display (compact) | Inner, open wide (951 × 669) | Inner, partially open as a book (vertical fold) | Inner, open tall / laptop (horizontal fold) | Split View 50/50 or narrow window |
|---|---|---|---|---|---|
| **Place page** (hero + cards) | Single pane as today: full-height hero, scroll to cards. Fix safe areas | **Two panes**: hero on the leading side, cards scrolling on the trailing side, split at the fold's (inactive) frame | Same two panes, already split at the fold, so **nothing moves** when it folds | Single column. The hero fills the space above the fold, and cards start below it (laptop: sky up, detail on the table) | Single pane (compact) |
| **City menu + settings** | Top bar today, overlapping nothing once safe areas are fixed | Option C: a rail on the system's vertical-bar edge, below the status bar | Same | Top (no vertical bars on the inner display in portrait) | As compact |
| **Settings** (List, pushed) | System navigation bar, which goes vertical by itself | Readable-width list. No split: it's a short list, and a second level adds nothing | Same | Same | Same |
| **Map** (full-screen cover) | Full bleed; Done button inside the safe area | Same | The map is continuous content, so no displacement | Same | Same |
| **Sheets** (search, scale, advice) | System sheets adjust themselves | Same | Same | Same | Same |
| **Onboarding** | As today | Content column of readable width | Column moves to the leading half when the fold is active | Content above the fold | As today |

**Why two panes are worth it on the inner display:** on the phone, the answer and the "when / what about running" detail are a scroll apart. On the inner display, both fit at once: the verdict on the left, Activities and the Forecast on the right. This is simultaneous context, not a stretched phone screen. Each pane is about the size of the outer display, so cards keep their designed proportions. And because the split sits on the fold, the device can bend without anything crossing the crease.

**Rejected:**
- `NavigationSplitView` with a place list in a sidebar. It breaks the full-bleed sky that is the product's identity and duplicates the city menu, and with six places at most, a sidebar is navigation the task doesn't need.
- `ArrangementView`. Apple says not to put it inside a scroll view, and each place page lives inside the horizontal pager.
- A tabletop-only layout. Apple says not to tie functionality to a pose.

### Layout rules (place page)

1. **Two panes** when the horizontal size class is regular **and** the page is at least as wide as two minimum card columns plus the gap. That minimum comes from the cards' own design, not from a device size. Otherwise, one column.
2. In two panes, if `reservedRegions(kind: .division, options: .includeInactive)` returns a vertical division, the pane gap sits on its frame. Otherwise it's an even split.
3. In one column, if a horizontal division (active or inactive) exists, the hero ends above it and the cards begin below it. Otherwise the hero is full height, as today.
4. Before iOS 27.1, rules 2 and 3 fall back to an even split and a full-height hero.
5. **State kept across every change:** the selected place (`scrollPosition(id:)`), open sheets, the Settings navigation path and refresh state. The cards' scroll position resets to the top when the layout mode changes: one scroll view becomes another. In two panes, the first two cards are visible at once anyway.

## 5. Transitions and motion

Today's motion stays: the hero rises in, cards reveal on scroll, the forecast draws in, and place swipes crossfade the backdrop. All of it already respects Reduce Motion and the app's Reduce Visual Effects setting.

| ID | Purpose | Trigger | From → to | Continuous | Changes | Technique | Timing (hypothesis) | Interruption | Reduced motion | Validate by |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | Layout continuity | Unfold or fold between outer and inner, rotate, resize, Split View | one pane ↔ two panes | Place, backdrop, top bar | Hero and cards re-flow | None of our own: the system animates the scene resize. Our layout follows the new size immediately | — | The latest size always wins; no stored state | Same | Device Hub: Closed → Open → Closed while scrolled and while a sheet is open |
| T2 | Fold without jump | Open → partially open | two panes, inactive fold → active fold | Everything | Nothing | None (by design) | — | — | — | Device Hub: Partially Open; compare screenshots |
| T3 | Laptop displacement | Tall inner, flat → laptop | full hero → hero above the fold | Everything (inactive frame already used) | Nothing | None (by design) | — | — | — | Device Hub, tall plus partially open |
| T4 | Reading arrives | Data loads | skeleton → reading | Layout | Lines rise in | Existing `riseIn` (decelerating 0.9 s, staggered) | Unchanged | Settles once | Off | Existing UI test |
| T5 | Next place | Swipe or menu pick | page n → page n+1 (both panes move as one page) | Top bar, rail | Page, backdrop crossfade | Existing paging and crossfade | Unchanged | Paging snaps | Crossfade only | Swipe in two-pane mode |
| T6 | Rail relocation | `toolbarVerticalEdge` changes | top bar ↔ vertical rail | Controls and their order | Axis and position | Same choice SwiftUI makes for system bars: a short standard animation | `DS.Motion.standard` (hypothesis) | Re-evaluates per environment change | Instant | Rotate the inner display; Split View |

No hinge-angle effects. Apple reserves the hinge API for interactions and effects, and nothing in the task needs one.

## 6. Implementation plan

**Phase 1: safe-area correctness (every device; a candidate for a quick 1.4.1).** Files: `LocationPager.swift`, `LocationPage.swift`, `VerdictHero.swift`, `DesignSystem.swift`, then a check of `OnboardingView.swift` and `MapScreen.swift`.

- The pager respects the safe area, and only the backdrop and scrims stay full bleed.
- The top bar becomes a `safeAreaInset(edge: .top)`, so pages inherit its height.
- Delete `heroTopInset`.
- The top-bar blur reaches under the status column.
- Done when: Duo outer has nothing under the column; iPhone 18 Pro and iPad 13" look unchanged (before/after sheets); the UI tests and accessibility audit pass.

**Phase 2: inner display.**

- An adaptive place layout implementing the rules above.
- `reservedRegions` and `toolbarVerticalEdge` behind `#available(iOS 27.1, *)`.
- The rail (option C, if chosen).
- Onboarding displacement.
- New UI tests that read the layout mode.

**Phase 3: validate and ship.**

- Configuration matrix (section 7).
- Duo App Store screenshots (outer and inner).
- What's New.
- Then decide `UIRequiresFullScreen` and the iPad orientations. Per the skill, that's the developer's call, made only after resizing is verified.

## 7. Validation matrix

| Configuration | How | Who |
|---|---|---|
| Outer display, all screens, Dynamic Type up to AX3, Reduce Motion | Duo simulator, UI tests | Me |
| Inner open wide / tall, partially open (book, laptop) | Device Hub Open / Partially Open, plus rotation | **Needs your clicks in Device Hub** (or Accessibility permission for Claude, which only you can grant) |
| Split View 50/50, resized windows | Device Hub | Needs your clicks |
| iPhone 18 Pro, iPad 13" regressions | Existing simulators, UI tests, before/after sheets | Me |
| VoiceOver | iPhone/iPad only. Device Hub can't convey Duo screen content (Xcode 27.2 notes) | Me, on iPhone/iPad |
| Widgets on Duo | Not runnable in the Duo simulator (Xcode 27.1 notes) | Untestable here; flagged |

Quality gate: an internal score of 85 or more (out of 100) after rendering, with no critical failures (lost place, controls under bars, content across the fold).

## 8. Decisions needed

1. **Top bar on Duo.**
   - (A) Keep it at the top and only fix safe areas.
   - (C, recommended) Keep the same controls, but when `toolbarVerticalEdge` is set, show them as a rail on that edge below the status bar, as Apple's docs suggest for custom bars. Unchanged everywhere else.
   - (B, not recommended) Move them into the system toolbar. That changes the look on every iPhone, and the coloured dots can't render vertically as a system item.
2. Approval of phases 1–3 as written.
