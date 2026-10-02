# MacBar

A custom MacBook Touch Bar with app shortcuts, backgrounds, media controls, and typing suggestions. Built with Swift, AppKit, and SwiftUI. No third-party packages.

Requires macOS 13 or later and Xcode or the Swift command-line tools. The settings preview works without Touch Bar hardware.

## Build

```sh
bash scripts/build.sh
open build/MacBar.app
```

Open `Package.swift` in Xcode to edit the project. Quit MacBar before rebuilding. The app is signed locally for your Mac’s architecture; it is not notarized.

`bash scripts/install.sh` rebuilds the app, replaces `~/Desktop/MacBar.app`, and launches it. Launch at login is enabled on first run and can be toggled in the MacBar menu.

## Features

- App shortcuts with Dock import, reordering, and unread badges.
- Full-width image backgrounds with Fit, Fill, and Stretch sizing.
- Brightness, volume, Wi-Fi, battery, and clock controls.
- Spotify playback, album art, volume, and seeking.
- YouTube and Netflix controls when their browser tab is active.
- Typing suggestions and word replacement using macOS spell checking.
- An X profile panel with follower, following, and post counts.
- Flappy Bar, a game played directly on the Touch Bar.
- A Showcase window for demos and screen recordings.

Closing settings leaves MacBar running. **Hide Bar** restores the normal controls until **Show Touch Bar** is selected. **Quit MacBar** stops it.

## Configuration

Use **Configure MacBar…** to add apps and choose a background. Changes save to:

```text
~/Library/Application Support/MacBar/apps.json
```

**Show Config File** reveals the file. After editing it manually, select **Reload Configuration**. See `apps.example.json` for a starting point.

```json
{
  "apps": [
    { "name": "Safari", "bundleIdentifier": "com.apple.Safari" },
    { "name": "Terminal", "bundleIdentifier": "com.apple.Terminal" }
  ],
  "background": {
    "mode": "fill",
    "isEnabled": true
  }
}
```

App entries accept an optional absolute `path`. The background accepts an optional absolute `imagePath`; omit it to use the bundled banner. Custom images are referenced in place. Invalid configuration files are preserved.

The bundled profile and banner are personalized for `@liammdevs`. Change `ProfileLink` in `Sources/MacBar/LauncherBarView.swift` and the files in `Sources/MacBar/Assets` to use your own. The welcome text is in `Sources/MacBar/IntroOverlay.swift`.

The default bar width is 1004 points. To override it:

```sh
defaults write dev.macbar.launcher barWidth 1004
```

To run with a separate config and only the on-screen preview, quit MacBar first, then run:

```sh
open build/MacBar.app --args --config "$PWD/apps.example.json" --preview-only
```

## Permissions and compatibility

Accessibility permission is used for Dock badges, browser detection, and typing suggestions. Spotify and browser scripting require Automation permission. For exact browser seeking and playback information, enable **Allow JavaScript from Apple Events** in the browser’s developer menu. Without it, media controls fall back to keyboard shortcuts. Rebuilding an ad-hoc-signed app may require granting permissions again.

X profile stats are fetched from `api.fxtwitter.com` using the configured public handle. Media artwork is downloaded from the URLs supplied by Spotify or the browser. Typing suggestions use macOS services and an in-memory fallback buffer for apps that do not expose text through Accessibility.

Global Touch Bar presentation and display brightness use private macOS APIs. They may stop working after a macOS update, and this approach is unsuitable for the Mac App Store. If the bar does not appear, select **App Controls** in macOS Touch Bar settings and quit other Touch Bar replacement apps.

API references: [NSTouchBar](https://developer.apple.com/documentation/appkit/nstouchbar), [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace), [EnergyBar’s system-modal declarations](https://github.com/billziss-gh/EnergyBar/blob/master/src/System/NSTouchBar%2BSystemModal.m), and [MTMR’s Control Strip integration](https://github.com/Toxblh/MTMR/blob/master/MTMR/TouchBarController.swift).

## Tests

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" swift test --disable-sandbox
```

Tests cover configuration, layout, presentation lifecycle, media scripts, typing replacements, and game state. Physical Touch Bar behavior still needs testing on a supported MacBook.
