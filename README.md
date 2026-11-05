# AR Ruler

A macOS app for measuring real-world distances and angles on your screen. Click two points to lay a ruler exactly along what you're measuring, then read any position along it. There's no window in your way: without the modifier key held, the overlay ignores the mouse completely.

## Usage

Hold your modifier key (**Option** by default, set in Preferences) for everything below. Clicks without it go straight to the app underneath, and your current app keeps its focus either way.

| To | Do this |
| --- | --- |
| **Align** | Click two points. A ruler appears through both and runs to the screen edges, with zero at the first click and negative readings behind it. |
| **Read** | Just move the mouse, with or without the key. A marker shows the reading at the point on the ruler square to the pointer. |
| **Pin a reading** | Click within about 8 points of the line. The pin shows its position and, under Δ, the gap from the next pin down the ruler. |
| **Measure an angle** | Click away from the line. Up to 4 points in all, with lengths and angles. The next off-line click starts a new measurement. |
| **Re-aim** | Drag either end of the ruler. |
| **Slide** | Drag the middle of the ruler. |
| **Nudge** | Press the arrow keys to move the ruler 1 point. |
| **Snap** | Hold **Shift** while placing a point or dragging an end to snap to 0°, 45° or 90°. |
| **Clear** | Press **Esc**, or right-click with the key held. Also in the menu bar menu. |

While the key is held, the preview shows what a click would do: the marker turns amber when a click would pin, and a dashed line appears when it would add a point.

Pins stay with the spot they marked on screen, so their readings update if you then fine-tune the ruler.

### Good to know

- **Nudging takes over the key combination.** While a ruler is showing, modifier + arrow keys go to AR Ruler rather than the app you're in (so Option+arrow won't jump by word in a text editor). They return as soon as the ruler is cleared.
- **With Control as the modifier**, macOS may keep Control+Up and Control+Down for Mission Control and App Exposé, and Control+Left and Control+Right for switching Spaces, if those shortcuts are on. Option avoids this.
- **The line runs edge to edge, so "near the line" does too.** An angle point within about 8 points of the line, even far past the ends, drops a pin instead.
- **One screen at a time.** Clicks on another screen are ignored until the measurement is cleared or has its 4 points.

## Calibration

By default the scale comes from the physical size the display reports, or 72 points per inch if it reports none. Some displays report it wrongly. To correct it for a display:

1. Hold something of known length against the screen, such as a bank card (8.56 cm wide).
2. Modifier-click its two ends to lay the ruler across it.
3. Choose **Calibrate This Display…** from the menu bar menu and enter its true length.

This is saved per display and keeps working if you change the display's scaled resolution or rotate it. **Reset Calibration** returns to the reported size. The menu shows the current scale and where it came from.

## Permissions

Nearly everything works with no permissions. The exception is **Esc while another app is frontmost**, because macOS only shares other apps' key presses with apps that have Accessibility access. If it's missing, the menu shows **Allow Esc to Clear in Other Apps…**, or you can enable AR Ruler in **System Settings > Privacy & Security > Accessibility**. A rebuilt copy of the app may need to be allowed again.

## Building

`project.yml` is the source of truth for the Xcode project. After adding files, run `xcodegen generate`.

1. Open `AR-Ruler.xcodeproj` in Xcode.
2. Select the AR-Ruler scheme and build (Cmd+B).
3. Run (Cmd+R) or use **Product > Archive** for distribution.

### Tests

Run the tests with Cmd+U. Geometry, ticks, click handling and calibration are plain Swift in `AR-Ruler/Core`, so the tests run without launching the app.

To look at the rendering, save it to PNGs over light, dark and busy backgrounds:

```bash
TEST_RUNNER_ARRULER_SNAPSHOT_DIR=/path/to/existing/folder xcodebuild -project AR-Ruler.xcodeproj -scheme AR-Ruler test
```

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later (for building)
