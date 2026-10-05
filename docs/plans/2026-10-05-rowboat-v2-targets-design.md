# Rowboat v2: every clickable thing, every visible window, faster

Date: 2026-10-05. Status: proposal, after Nathan's first day of use.

## The complaint

Homerow puts a label on nearly everything; Rowboat 0.1.1 labels fewer things
in the same window. Nathan also cascades two to six app windows and wants to
click into any of them, which Homerow cannot do.

## How Homerow does it (from its binary and behaviour)

Accessibility only, no screenshots. It walks the focused window of the
frontmost app plus the menu bar and open menus, through `AXChildren` and
`AXChildrenInNavigationOrder`; for web areas it uses
`AXUIElementsForSearchPredicate` with Button, CheckBox, Control, Graphic,
KeyboardFocusable, RadioGroup, TextField, Link and Landmark keys; it switches
on `AXEnhancedUserInterface` and `AXManualAccessibility` in Chromium and
Electron apps. Its density comes from two choices: it labels leaves and
their containers alike (a row, the text in the row, and the icon all get
labels), and it never drops overlapping labels; it clusters them and lets
Space rotate through the cluster. It does nothing for other windows or apps.

## Why Rowboat shows fewer labels today

Four deliberate filters, each of which removes things Homerow keeps:

1. Near-duplicate frames are dropped (intersection over union above 0.8).
2. Text, images, groups and cells inside an element that is already a target
   are skipped, so a row gets one label instead of three.
3. Native elements need a clickable role, an `AXPress`, or (since 0.1.1) to
   be text or an image outside a target.
4. Web pages come only from the predicate keys plus named pressable groups;
   unnamed clickable groups and plain text are left out.

Filter 2 is the one Nathan notices. The rest are smaller.

## Measurements behind the proposal (this Mac, 2026-10-05)

| What | Result |
|---|---|
| Walk six top windows of six apps, one after another | 2542 ms |
| Same six in parallel (one thread per app) | 765 ms, about 3.3x; per-walk time rose from ~420 to ~680 ms, so the client side serialises partly |
| Enumerate on-screen windows with z-order and bounds (`CGWindowListCopyWindowInfo`) | tens of ms |
| Vision OCR, fast level, half-resolution screen | 45 ms for 50 text boxes (plus 25 ms downscale) |
| Vision OCR, fast level, full resolution | 207 ms |
| Vision rectangle detection, half resolution | 42 ms |
| One-shot ScreenCaptureKit screenshot | 1.8 to 3.7 s, unusable at hotkey time |
| ScreenCaptureKit stream | not yet measured cleanly; expected one frame interval (~16 ms) once running |

## Proposed architecture: layered targets, progressive labels

```
hotkey ─▶ Scene (window list, z-order, visible-region mask per window)
             │
             ├─▶ Layer 1  AX walk of every visible window, one task per app, clipped
             │             to the window's unoccluded region. Frontmost window paints
             │             first; others append as they arrive. Density = Homerow's.
             │
             ├─▶ Layer 2  Cache. Per-window snapshot keyed by window id, title and
             │             size, kept warm by AX observers (layout changed, value
             │             changed, element destroyed, window moved). Re-activation
             │             renders from cache in ~10 ms, then revalidates.
             │
             ├─▶ Layer 3  Vision for AX-blind regions only: the parts of the screen
             │             no AX target covers (canvases, Qt and Java apps, video,
             │             screen shares, Electron before its tree is ready). Latest
             │             frame from a running ScreenCaptureKit stream, fast OCR at
             │             half resolution for text targets, contour detection for
             │             icon-sized blobs. Labels append ~60 to 100 ms after Layer 1.
             │
             └─▶ Layer 4  Grid. A two-level grid over the screen or a window for
                           anything the layers above missed. Zero latency.
```

Labels are assigned in arrival order and never reassigned while a mode is
open, so a label the user has started typing cannot move. Overlapping labels
are clustered and offset, with Space rotating the cluster, instead of being
dropped.

Clicking into a background window: an AX target can be pressed without
raising its app (a real background click, which Homerow cannot do); a
synthetic click raises the window first. Setting: "Clicking another window
brings it to the front", default on.

## Latency budget

| Moment | Target |
|---|---|
| Hotkey to first labels, frontmost window, from cache | 20 ms |
| Hotkey to first labels, frontmost window, cold | 150 ms |
| Other visible windows | stream in, each as it finishes, 100 to 700 ms |
| Vision labels for AX-blind regions | 100 ms after Layer 1 |
| Overlay redraw with 500 labels | under 2 ms |

## Risks and costs

- Screen Recording is a second permission with its own prompt. The vision
  layer is opt-in and the stream runs only while Rowboat has been used in the
  last minute, so battery cost is bounded; frames arrive only when the screen
  changes.
- AX parallelism yielded 3.3x on six apps, not 6x. Enough for the cascade
  case, and the cache removes most of the walk from the hot path anyway.
- Density has a cost: 500 labels on a busy screen need good typography and
  the overlap clustering to stay readable. Mixed-length labels keep the
  common ones short.
- The vision layer clicks by coordinates only; it cannot press a button that
  is visually covered. That is what the AX layers are for.

## Order of work

1. Density parity: label leaves and containers, cluster overlaps, Space
   rotates. One session. Verify against Homerow on the same windows.
2. Every visible window, parallel per app, occlusion-clipped, progressive
   rendering, background press. One to two sessions.
3. Warm cache with AX observers. One to two sessions. This is where
   "labels appear before you finish pressing the key" comes from.
4. Grid mode. Half a session.
5. Vision layer: OCR text targets first, icon blobs second, a small on-device
   UI-element detector (CoreML) only if blobs prove too noisy. Two to three
   sessions, opt-in.
