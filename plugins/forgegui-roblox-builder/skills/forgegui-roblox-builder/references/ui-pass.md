# UI pass

Follow this when you build or restyle HUDs, modals, shops, settings or notifications. The pieces it
uses live elsewhere:

- The screen layouts are the Screen templates in `gui-art.md`: modal, content inside framed art,
  icons, upgrade card and settings toggles.
- Art is placed with `luau/GuiArt.luau` (`gui-art.md`).
- Motion, including `Motion.modal`, comes from `luau/Motion.luau` (`ui-motion.md`).
- The checks are in `luau/UiCheck.luau`. `world-and-ui-checks.md` covers how to run them and how to
  read their output.
- Provenance and style-adaptivity evidence come from `UiCheck.provenance` and
  `tools/style_delta.py`; `gui-art.md` covers both.

## Before you build

Write down five things:

- the goal in one sentence (for example, "the shop answers: what do I get, what does it cost, can I
  afford it");
- the visual target (reference images) — and, if the user supplied one, how it became a reference:
  a registered owned asset, or the style-plate substitute in `gui-art.md`;
- the art registry, which `UiCheck.provenance` checks every screen against;
- what is in scope, meaning which screens;
- what is out of scope: gameplay code, the world, and anything else not listed.

Then classify every overlay before you build it:

- **Class A, transactional**: shop, upgrades, purchase confirmation, trade, settings.
- **Class B, lightweight**: tooltip, item popover, toast.

## Hard rules

1. **A Class A modal never closes from a click that misses a button.** Build it with `Motion.modal`.
   - The backdrop is a full-screen `TextButton` or `ImageButton` with `AutoButtonColor` off,
     `Modal` on, and no input handler.
   - The panel is `Active`.
   - The modal closes only from a visible close button, its own key, and gamepad B. The close
     button uses the same art and sits top right on every modal. Never close on Escape, because
     Roblox's menu owns it.
2. **One frame per visual unit.** Generated art that draws its own rim gets no `UIStroke`, no border
   and no visible background; placing it with `GuiArt` enforces this. Content inside framed panel
   art sits on borderless fills. A stroked box there is a frame inside a frame.
3. **Icons stand on their own.** Put no chip, ring, disc or plate around an icon. Depth comes from a
   soft drop shadow: a darker copy of the icon, a few pixels lower, placed as a sibling.
4. **Every `UIStroke` has a stated purpose**: text legibility, focus, or a state change. Remove the
   rest.
5. **Hierarchy.** On each card, the most important number and the primary action are the largest,
   highest-contrast things. A squint test must still find them.
6. **Design and capture every state:**
   - affordable;
   - unaffordable: the price in red, the shortfall in words, and a response when it is tapped;
   - maxed;
   - just purchased: sound, animation, and the balance updating once the server confirms;
   - refused by the server.
7. **One modal at a time.** Opening one closes the other.
8. **Size and place targets for touch.** Every interactive target is at least 44x44 px at the
   smallest supported viewport, stays out of the thumbstick and jump zones, and sits inside the safe
   insets.
9. **Report every gate as PASS or FAIL** with the tool output or evidence. Say plainly what you
   could not test. Gamepad B, for example, cannot be simulated in Studio.

## Steps

1. **Inventory (read only).** List the ScreenGuis, and every modal with its backdrop and close
   paths. Find every script that connects input on a backdrop, scrim or overlay with
   `UiCheck.lintSource`. Run `GuiArt.conflicts` on each element you are about to decorate.
2. **Baseline.** Capture each screen in each of its states. Run `UiCheck.audit` on each ScreenGui.
3. **One screen per step.** After each one: push, hash-check the script, play, capture, and run the
   gates.
4. **Finish.** Fill in the gate table below. Then have a reviewer, such as a fresh-context
   subagent, read the captures and the gate output rather than your summary.

## Gates

| Gate | Pass condition |
| --- | --- |
| U1 Classes | Every overlay is tagged Class A or Class B in the report |
| U2 Lint | `UiCheck.lintSource` over every client script finds no `modal_closes_on_stray_click` |
| U3 Structure | `UiCheck.audit` over each ScreenGui, with every modal open, finds no `art_background`, `art_stroke`, `bordered_icon`, `icon_on_plate` or `stroke_in_framed_art`. Each `text_overflow` warning is fixed or explained |
| U4 Stray clicks | For each Class A modal, click every point from `UiCheck.strayClickPoints`, inside the panel and around it, including over HUD buttons under the backdrop. The modal stays open and nothing under it fires. Then the close button closes it |
| U5 Class B | An outside tap closes it; an inside tap does not |
| U6 Keys | Each modal's key toggles it. Gamepad B closes it: read the handler, which must handle B even when the input is marked processed |
| U7 States | A capture exists for every state in rule 6 |
| U8 Targets | Interactive targets are at least 44x44 px at the smallest viewport, and none are in the thumbstick or jump zones |
| U9 Consistency | Every modal uses one close-button asset in one position, and only one modal is open at a time |
| U10 Evidence | Captures of the Studio window only, with the player list covered; the audit and lint output; the stray-click result; and the reviewer's sign-off |
| U11 Provenance | `UiCheck.provenance` over each ScreenGui, against the art registry, reports no `unregistered_image`. Every `primitive_surface` is either fixed or carries `AllowPrimitive` with a reason in the report. Record the generated-surface percentage per screen |
| U12 Style adaptivity | Two runs of the same prompt set under two style references, compared with `tools/style_delta.py`, report a mean delta-E at or above the threshold, with the contact sheet attached. If the reference had to be reconstructed as a style plate, the report says so |

## Running the checks

Paste `UiCheck` ahead of a runner with `references/tools/paste_module.py`, as described in
`world-and-ui-checks.md`. Run the structure check in play on the Client datamodel, with every modal
you are checking open. Run the lint in Edit. For stray clicks, get the points in play, click each
one with `user_mouse_input`, and after each click read the modal's `Visible`.

## Worked example

This is one game's shop, settings screen and action bar. They were rebuilt after a play-tester
reported both problems: modals that closed on a missed click, and icons in borders they did not
need.

Before the rebuild, the lint found the wiring the play-tester had hit:

```
[error] modal_closes_on_stray_click StarterPlayer.StarterPlayerScripts.Client.Shop:135: backdrop.Activated is connected; ...
[error] modal_closes_on_stray_click StarterPlayer.StarterPlayerScripts.Client.Settings:86: backdrop.Activated is connected; ...
```

The first audit reported 12 errors:

- the three stroked upgrade cards and a locked-section strip inside the shop's framed panel;
- the four stroked settings rows inside the settings panel;
- the four switch tracks.

The switch tracks were a false positive, because a control's own outline is not a second frame. The
rule was changed to count only containers. The icons-in-borders complaint turned out to be the
action bar, which laid each icon on a framed square plate. `icon_on_plate` was added to catch that.

After the rebuild:

- the lint found nothing;
- the audit found 0 errors across 175 elements with the shop open;
- 16 stray clicks on the shop and 18 on settings left both open. One of them was over the HUD's
  settings button, under the backdrop.
- the close button still closed both.
