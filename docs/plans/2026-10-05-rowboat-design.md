# Rowboat design

Date: 2026-10-05. Status: accepted for v0.1.

## Purpose

Rowboat is an open-source macOS utility that puts keyboard labels on every
clickable element, scrolls any scroll area from the keyboard, and finds
elements by typing their text. It replaces Homerow, whose core idea is right
but whose implementation is glitchy: stale or missing labels in Chromium and
Electron apps, scroll mode landing on the wrong area, slow activation on
large windows, and no way to inspect or fix any of it.

## Non-goals for v0.1

No hyper key, no input-source switching, no analytics, no licensing, no
auto-update, no Xcode project. Each can be added later without changing the
architecture below.

## Measured facts that shape the design

Probed on this Mac (macOS 26, Swift 6.4, Homerow 1.2.2 running):

| Strategy | Finder window | Chrome window | Chrome web area |
|---|---|---|---|
| `AXUIElementsForSearchPredicate` | returns 0 | unsupported (-25213) | 5 results, 0 ms, misses most buttons |
| Recursive traversal, one attribute per call | 156 nodes, 82 ms | 398 nodes, 83 ms | 302 nodes, 49 ms |
| Recursive traversal, `AXUIElementCopyMultipleAttributeValues` | - | - | 302 nodes, 26 ms |

Later the same day, measured on a long Wikipedia article in Chrome: the walk
visited 6814 nodes and hit the 900 ms budget with 140 targets, 4350 of those
nodes reporting empty frames (offscreen content Chromium does not lay out);
`AXUIElementsForSearchPredicate` on the same web area with `AXVisibleOnly`
returned 118 interactive elements in 9 ms. Notes with 13,000 notes: the walk
hit 900 ms over 6997 rows until `AXVisibleRows` was preferred, then 198 ms.

Conclusions:

1. Traversal with one batched attribute fetch per node is the collection
   strategy for native views. For `AXWebArea` nodes the search predicate is
   primary (Chromium and WebKit both implement it) and the walk is the
   fallback when the attribute is unsupported or returns nothing. Tables
   and outlines are walked through `AXVisibleRows` when they offer it, and
   containers with empty `AXChildren` through `AXContents` (Finder's column
   view).
2. Chromium exposes its web tree only when something asks for it. Rowboat sets
   `AXEnhancedUserInterface` on the application element of Chromium and
   Electron apps when the user enables that setting, and reads the tree only
   after it responds.
3. Every AX call is an IPC round trip to the target app, so collection runs on
   a dedicated serial queue with a per-call messaging timeout, and the overlay
   never blocks the main thread on it.

## Architecture

Two SwiftPM targets plus tests:

- `RowboatCore` (no AppKit). Label alphabet and prefix-free label generation,
  typed-prefix matching, fuzzy text matching for search mode, and layout
  helpers that deduplicate overlapping element frames. Fully unit tested.
- `Rowboat` (AppKit, ApplicationServices, Carbon). Everything that talks to
  the system.

Components inside `Rowboat`:

```
HotKeys (Carbon RegisterEventHotKey)  ──activate──▶  ModeController
                                                      │  owns exactly one active Mode
                                   ┌──────────────────┼───────────────────┐
                                HintsMode          ScrollMode         SearchMode
                                   │                  │                  │
          ElementCollector (AX, background queue) ◀───┘   ScrollAreaCollector
                                   │
                              Overlay (one NSPanel per screen, label layers)
                                   │
                         KeyCapture (CGEventTap, enabled only while a mode is active)
                                   │
                              Actions (AXPress or synthetic CGEvent click / scroll)
```

### Activation and key capture

Hotkeys are registered with Carbon so Rowboat adds no latency to normal
typing. When a mode activates, a session-level `CGEventTap` is installed and
swallows all key events until the mode ends. Escape always ends the mode. If
the tap is disabled by the system (timeout), it is re-enabled once, and if
that fails the mode ends and the overlay hides, so the keyboard is never left
captured. This is the first glitch class to design out.

### Element collection

`ElementCollector.collect(in: window)` walks from the focused window of the
frontmost application. For each node it fetches role, subrole, children,
position, size, title, description, value, enabled, and action names in one
`AXUIElementCopyMultipleAttributeValues` call. A node is a hint target when
it has `AXPress` or its role is in the clickable set, its frame is non-empty,
and its frame intersects the window's visible frame. Subtrees whose
non-empty frame lies fully outside the visible frame are pruned. Node and
depth limits bound the walk; a time budget aborts it and shows what was
collected. Results are returned on the main thread as `[HintTarget]` with
screen coordinates already converted to AppKit's bottom-left origin.

Chromium and Electron apps are detected by bundle identifier prefix and by
the presence of an `AXWebArea`. When the setting is on, Rowboat sets
`AXEnhancedUserInterface` on the app element before the walk.

### Labels

Labels come from a configurable alphabet (default `asdfghjklqwertyuiopzxcvbnm`
reordered so the home row comes first). Labels are prefix-free: with 14
characters and 20 targets, 13 targets get one character and 7 get two.
Targets are sorted top-to-bottom, left-to-right before labels are assigned
so the same screen gets the same labels every time. Typing filters labels by
prefix; a full match acts. Shift on the last character right-clicks, Command
on the last character command-clicks, and typing a label twice within
300 ms double-clicks. Overlapping labels are offset by the layout helper
instead of being hidden.

### Clicking

If the target supports `AXPress` and no modifier is held, Rowboat performs
`AXPress`. Otherwise it posts a synthetic mouse down and up at the target
centre with the requested modifier flags, then restores the cursor position.
Synthetic clicks are the fallback because they work everywhere; `AXPress` is
preferred because it works on elements that are visually covered.

### Scroll mode

`ScrollAreaCollector` finds every `AXScrollArea` (and web areas that scroll)
in the focused window, sorted by area descending, and labels them with
digits. The largest area is selected by default; pressing a digit switches.
`h j k l` post scroll-wheel events at the selected area's centre; Shift
multiplies the step; `d u` scroll half a page; `g g` and `G` jump to the
ends; arrow keys mirror `hjkl` when the setting is on. The cursor is warped
to the area centre only when the event-location routing fails for that app.
An optional inactivity timer ends the mode.

### Search mode

The hints collection is reused. A small text field panel at the bottom of the
screen receives typed text; `RowboatCore.FuzzyMatcher` scores targets by
title, description, value, and role; the overlay shows labels only for
matches above a threshold. Return clicks the best match; typing a visible
label clicks that target.

### Settings

`Settings` is a small class over `UserDefaults` with typed properties and a
Combine publisher. A SwiftUI settings window edits shortcuts (custom key
recorder), label alphabet, excluded bundle identifiers, Chromium
accessibility toggle, arrow-keys-scroll, scroll speed, menu bar icon, and
launch at login (`SMAppService`).

### Error handling

Every AX call returns an `AXError`; the wrapper converts it to `nil` and
counts failures. A mode that finds no window or no targets shows a brief
"no targets" badge for 600 ms and ends. Nothing is ever retried in a loop.
Logging goes through `os.Logger` with a `rowboat` subsystem so
`log stream --predicate 'subsystem == "rowboat"'` is the debugging story.

### Testing

- `swift test` covers RowboatCore: label generation (prefix-free, count,
  stability), prefix matching, fuzzy scoring, overlap layout.
- `Rowboat --dump [bundle-id]` prints the collected targets for the frontmost
  or named app as text, so the collector can be verified from a trusted
  terminal without a GUI.
- `Rowboat --activate hints|scroll|search` sends a distributed notification
  to the running instance so modes can be triggered during development
  without pressing the hotkey; `--type` and `--hold` post key events with
  real key codes. Screenshots with `screencapture` verify the overlay.
  This is how the 2026-10-05 verification matrix (Finder, Chrome, Safari,
  Notes, System Settings) was run.

## Packaging

`scripts/build-app.sh` runs `swift build -c release`, assembles
`dist/Rowboat.app` with an `Info.plist` (`LSUIElement` true, bundle id
`com.nathanforster.rowboat`), and ad-hoc signs it. Without a Developer ID the
Accessibility grant must be repeated after each rebuild; a stable
self-signed certificate is the documented workaround.

## Open questions for Nathan

- Final name and GitHub organisation before publishing.
- Which Homerow glitches hurt most, to order the verification list.
- Whether the Caps Lock hyper key is wanted in v0.2.
