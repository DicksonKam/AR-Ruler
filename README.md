# AR Ruler

A macOS app for measuring real-world distances and angles on your screen. Click two points to lay a ruler exactly along what you're measuring, then read any position along it. There's no window in your way: without the modifier key held, the overlay ignores the mouse completely.

## Usage

Hold your modifier key (**Option** by default, set in Preferences) for everything below. Clicks without it go straight to the app underneath, and your current app keeps its focus either way.

| To | Do this |
| --- | --- |
| **Align** | Click two points. A ruler appears along them, with zero at the first click, ending on a whole cm or inch at least one unit past the second. |
| **Read** | Just move the mouse over the ruler, with or without the key. A marker shows the reading there. Away from the ruler there's no reading. |
| **Pin a reading** | Click on the ruler or within about 8 points of it. The pin shows its position and, under Δ, the gap from the next pin down the ruler. |
| **Measure an angle** | Click away from the ruler. It's replaced by plain lines with their lengths and the angle in a small arc. A fourth point adds another line and angle, and the click after that starts a new measurement. |
| **Re-aim** | Drag either of the two points you clicked. The direction shows while you do. |
| **Slide** | Drag the ruler's body. |
| **Lengthen** | Drag the tab on the far end. The ruler changes length in whole units, down to the second point, without changing its zero or angle. |
| **Nudge** | Press the arrow keys to move the ruler 1 point. |
| **Snap** | Hold **Shift** while placing a point or dragging one of the two points to snap to 0°, 45° or 90°. |
| **Clear** | Press **Esc**, or right-click with the key held. Also in the menu bar menu. |

While the key is held, the preview shows what a click would do: the marker turns amber when a click would pin, and a dashed line appears when it would add a point.

Pins stay with the spot they marked on screen, so their readings update if you then fine-tune the ruler. A pin left past the ruler's ends is hidden, and comes back if the ruler reaches it again. Switching to an angle measurement removes the ruler and its pins for good.

### Good to know

- **Nudging takes over the key combination.** While a ruler is showing, modifier + arrow keys go to AR Ruler rather than the app you're in (so Option+arrow won't jump by word in a text editor). They return when the ruler is cleared or replaced by an angle measurement.
- **With Control as the modifier**, macOS may keep Control+Up and Control+Down for Mission Control and App Exposé, and Control+Left and Control+Right for switching Spaces, if those shortcuts are on. Option avoids this.
- **"On the ruler" means the body you can see**, plus about 8 points around it. A click past the end is an angle point, even in line with the ruler. Lengthen the ruler first to pin further along.
- **Angle measurements can't be fine-tuned.** Clear and click again to redo one.
- **One screen at a time.** Clicks on another screen are ignored until the measurement is cleared or has its 4 points.

## Menu bar app

AR Ruler lives only in the menu bar, with no Dock icon or Cmd-Tab entry. Its ruler icon's menu has Clear Measurement, calibration, Launch at Login, Preferences and Quit.

- **Launch at Login** is off until you turn it on. The checkmark shows what macOS has on record, including changes made in **System Settings > General > Login Items**. If macOS wants your approval there, the menu item says so and opens the page.
- **If the icon is hidden**, as macOS can do in a crowded menu bar, open AR Ruler again from Applications or Spotlight. That opens Preferences, and Cmd-Q quits from there.

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
