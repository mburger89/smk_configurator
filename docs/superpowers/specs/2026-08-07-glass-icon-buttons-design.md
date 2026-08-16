# Circular Glass Icon Buttons

Date: 2026-08-07
Status: Approved, pending implementation plan

## Problem

The titlebar toolbar buttons (`New`/`Open`/`Save`/`Save As`/`Import`/`Export`, `ToolbarIconButton` in `Sources/SMKConfigurator/Views/UIStyle.swift`) and the icon rail buttons (`KEY`/`DSN`/`THM`/`DEV`, `RailButton`, same file) currently render as flat rounded-rect tiles with a solid neutral fill (or, for the rail's active tab, a fully solid accent fill). The goal is to make both icon-only button groups circular with a "liquid glass"-like translucent material, matching Apple's current design language as closely as SwiftCrossUI allows.

## Constraint

SwiftCrossUI (this app's UI framework) has no public backdrop-blur/Material/vibrancy API — its one `NSVisualEffectView` usage (`AppKitBackend.swift`) is internal and only wired to a sidebar split view, not exposed as a general-purpose `View`. There's also no `.clipShape()` modifier, so a gradient `View` can't be masked to a circle. Available primitives: `Circle`/`Capsule`/`RoundedRectangle` shapes with `.fill(Color)` and `.stroke(Color, style:)`, `.opacity()`, and `.overlay()`. "Glass" here therefore means a faux-glass composition built from stacked, semi-transparent solid shapes — real blur/refraction isn't reachable, and this spec doesn't attempt it.

## Design

**New shared component: `GlassIconTile`** (`UIStyle.swift`), replacing the internal `TapTarget` composition inside both `ToolbarIconButton` and `RailButton`. Both keep their existing public API (icon/tooltip/action parameters unchanged) — only their internals swap to build on `GlassIconTile`. `TapTarget` itself is untouched and keeps serving its other callers (palette chips, inspector tab row, `InspectorButton`, `ToolbarPill`'s text pills).

`GlassIconTile` is a `ZStack`, bottom to top:
1. `Circle().fill(tint)` — the base translucent fill. `tint` is supplied by the caller: a neutral translucent chrome tone for inactive buttons, an accent-tinted translucent color for the rail's active tab.
2. A small circle (~40% of the tile's diameter), offset toward the top-leading edge, filled with white at low opacity — a specular highlight/sheen.
3. `Circle().stroke(chrome.glassRim, style: StrokeStyle(lineWidth: 1))` — a thin light rim tracing the edge, reading as "glass catching light."
4. The caller's icon content, centered on top.

`onTapGesture` fires the caller's `action`, mirroring `TapTarget`'s existing pattern.

**New `Chrome` tokens** (`UIStyle.swift`), so every glass tile pulls from one palette:
- `glassFill: Color` — neutral translucent base for inactive tiles (derived from the existing `pillBackground` tone at reduced opacity).
- `glassRim: Color` — white-based, low opacity, same value in both light and dark scheme (a light rim reads the same regardless of what's behind it).
- `glassSheen: Color` — white at low opacity, for the highlight blob.

**`ToolbarIconButton`** changes from a padded, non-square `TapTarget` (16px icon + asymmetric 5/8px padding, so width ≠ height — can't be a circle) to a fixed square frame wrapping `GlassIconTile(tint: chrome.glassFill)`, sized to sit comfortably in the existing 44px titlebar.

**`RailButton`** keeps its existing 40×40 frame, but its background switches from `isActive ? chrome.railActiveBackground : chrome.railInactiveBackground` (solid fill) to `GlassIconTile(tint: isActive ? <accent-tinted translucent color> : chrome.glassFill)`. The existing icon-tinting rule (white/"dark" icon variant when active, for legibility against the still-visible accent tint) is unchanged.

Exact opacity constants (fill/rim/sheen alpha, active-state accent alpha) are tuning values, not fixed by this spec — reasonable starting points get picked during implementation and verified visually (`swift run` + a screenshot), the same way this app's other visual work has been checked.

## Non-goals

- `TapTarget`, `ToolbarPill`'s text-pill usage (DSN's `+ Row`/width presets), `InspectorButton`, and the palette-drawer chip buttons are unchanged — only the two icon-only tap targets identified above are in scope.
- No attempt at real backdrop blur or dynamic vibrancy — explicitly unreachable per the Constraint section.

## Testing

- `swift build --target SMKConfigurator` compiles clean.
- `swift test` — this is a purely visual change with no new logic to unit test; the existing suite (including `IconLoaderTests`) should pass unchanged.
- Manual visual QA: `swift run SMKConfigurator`, screenshot, confirm both button groups render as circles with visible translucency/rim/sheen in both Light and Dark (View ▸ Appearance), and that the rail's active tab still clearly reads as selected against its neighbors.
