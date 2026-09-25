# UI motion

The difference between a Roblox menu and a shipped one is rarely the layout. It is that everything
arrives, responds and leaves, and that nothing ever snaps. Motion costs no frames and is the most
reliable read of "finished", which is why it closes the detail flow rather than being an optional
extra.

Reviewed code: `luau/Motion.luau`. Ship it as a ModuleScript under `ReplicatedStorage` and require it
from LocalScripts; it touches only the objects a caller hands it, plus one `BlurEffect` it owns.

Camera moves are not UI motion: cinematic shots (eased Catmull-Rom paths that hand the camera back) are in
`ambient-motion.md` (`luau/CameraPath.luau`). They follow the same budget rule.

## Three rules the module keeps for you

1. **One tween per object per channel.** Starting a new tween on a channel cancels the previous one,
   so a fast clicker gets responsiveness instead of jitter. The channels are `scale`, `position`,
   `backdrop`, `blur` and `value`.
2. **Motion has a budget.** Durations are clamped to `Motion.MAX_SECONDS` (1.2 s). A panel that
   takes a second to open reads as lag, not as polish. The presets are 0.12 s for state changes,
   0.16 s for exits and 0.28 s for arrivals.
3. **Nothing animates a layout property.** Scale is animated on a `UIScale`, never on `Size`, so
   layout never reflows mid-animation and a list does not shove its neighbours around.

## API

| Call | Use it for |
| --- | --- |
| `Motion.reveal(object, { seconds, from, rise })` | a panel, card or toast arriving: scales up from 0.92 and lifts into place |
| `Motion.dismiss(object, { seconds, rise })` | the same element leaving; hides it only when the tween truly finished |
| `Motion.stagger(container, { delay, seconds })` | reveals children in order, 0.045 s apart, because a stagger you notice is too slow |
| `Motion.pressable(button, { hover, press })` | hover and press feedback by scale, for art buttons with no background to tint |
| `Motion.pulse(object, strength)` | one attention beat when something changed under the player |
| `Motion.countTo(label, from, to, { seconds, format })` | a total that ticks up instead of being assigned |
| `Motion.modal(panel, { backdrop, blur, seconds })` | returns `{ open, close }` for a dimmed, blurred modal |
| `Motion.stop(object)` | cancel everything running on an object before destroying it |

`Motion.EASING` holds the four curves (`arrive`, `exit`, `state`, `emphasis`) as
`{ style, direction, seconds }`. Override `seconds` per call rather than editing the table: Back for
arrival (a slight overshoot reads as physical), Quart for exits, Quad for changes that should not
draw attention.

## Modals never close on a stray click

Wiring a backdrop to close the modal means any click that misses a button closes the screen the
player was reading — and a panel's empty space lets clicks fall through to the backdrop behind it.
`Motion.modal` therefore makes the backdrop dim and *sink* input, never close. Close from a close
button, a key, gamepad B, or the action that opened the modal. Do not connect an input signal on the
backdrop.

The backdrop should be a `TextButton` or `ImageButton`: that is what reliably stops clicks reaching
the HUD and the world beneath, and `Modal = true` frees a locked mouse (shift lock, first person).
`Motion.modal` sets those properties for you when it is given a button.

The blur is this module's own `BlurEffect`, named `ForgeGUI_ModalBlur` under `Lighting`, created on
open and destroyed on close. It never adopts a blur the place already had, so a place that blurs for
its own reasons keeps doing so.

## Things that look like motion bugs and are not

- **Interrupted tweens.** `Tween.Completed` fires for `Cancel` as well as for a finished tween, so a
  close handler that hides the panel on completion also hides it when the player reopens the menu
  mid-close. Check `PlaybackState.Completed`, and aim an interrupted reveal at the element's resting
  position rather than at wherever it happened to be. `Motion` does both; hand-written tweens
  usually do not.
- **The HUD jumping to design size mid-tween.** Keep responsive scale and motion on *different*
  `UIScale`s: a screen-anchored outer frame carries the viewport scale, an inner frame carries
  reveal and pulse. Animating the only `UIScale` resets the responsive scale to 1.
- **A panel sitting 58 px lower than the mock-up.** With `IgnoreGuiInset = false`, `(0, 0)` is below
  the top bar on current clients. Anchor clusters to corners with offsets instead of placing by
  screen fraction.
- **A notification nobody sees.** Notifications belong above modals: a purchase confirmation that
  renders under the shop's backdrop is invisible exactly when the player is looking for it. Give
  them a higher `DisplayOrder` on their own `ScreenGui`, or queue them until the modal closes.

## Verify

Play the game; do not just look at the tree. Open and close each panel, click a button twice
quickly, and reopen a menu mid-close. Then: `screen_capture` during the animation and at rest,
`get_console_output` clean, and one pass clicking everything that is *not* a button, to confirm
nothing closes that should not.
