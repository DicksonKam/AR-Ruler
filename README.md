# AR Ruler

A macOS app that lets you measure real-world distances and angles directly on your screen. Hold a modifier key (Option by default) and click to capture points—no app window blocking your work.

## Features

- **2-point mode**: Click two points to measure the distance between them
- **3-point mode**: Click three points to get two distances and the angle at the vertex
- **4th point**: Clicking a fourth point starts a new measurement with that point as the first
- **Multi-screen**: Works across all displays; overlay covers every screen
- **No cross-screen measurement**: Points must be on the same screen; cross-screen clicks are ignored
- **Transparent overlay**: Clicks pass through to apps below until you hold the modifier key
- **Automatic scaling**: Uses display EDID physical size (CGDisplayScreenSize) for accurate measurements—no calibration needed; falls back to 72 pts/inch when EDID unavailable
- **Menu Bar + Dock**: Quick access from the menu bar; runs with minimal footprint

## Usage

1. Launch AR Ruler. A ruler icon appears in the menu bar.
2. Hold **Option** (or your configured modifier) and click to add measurement points.
3. With 2 points: distance is shown. With 3 points: two distances and the angle at the middle vertex.
4. Press **Esc** to clear the current measurement. **Right-click** to reset.

## Permissions

- **Accessibility**: Required for detecting the modifier key and capturing clicks when held. Enable in **System Settings > Privacy & Security > Accessibility**.

## Building

1. Open `AR-Ruler.xcodeproj` in Xcode.
2. Select the AR-Ruler scheme and build (Cmd+B).
3. Run (Cmd+R) or use **Product > Archive** for distribution.

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later (for building)
