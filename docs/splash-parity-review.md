# Splash parity review

The interface has two splashes, one after the other: the launch screen of the mobile wrapper, and the
animated page the interface opens on.

## 1. The launch screen (`capacitor`)

- `capacitor/capacitor.config.js`: `SplashScreen: { launchShowDuration: 0 }`. On iOS the plugin's `showOnLaunch()` returns at
  once for a duration of 0: there is no overlay of the plugin and no fade, only the launch screen until the app draws.
- `capacitor/package.json`, `build:assets`: `capacitor-assets generate --iconBackgroundColor #e5204c
  --iconBackgroundColorDark #e5204c --splashBackgroundColor #e5204c --splashBackgroundColorDark #e5204c --android`, from
  `resources/logo.png` and `resources/logo_dark.png`, which are the same file: 512x512, a white mark on transparent, the
  mark 318 wide (x 97 to 414) and 272 high, centred.
- `@capacitor/assets` puts the logo on a canvas of the background colour, resized to `logoSplashScale` (0.2) of the canvas width, in the
  middle. The png is what is resized, with its margins, so the mark is `0.2 × 318 / 512 = 0.1242` of the width of the screen. The
  Android splashes it makes are one per orientation, each as wide as its screen.

`Base.lproj/LaunchScreen.storyboard`: `#e5204c` (`UIColor.HayaseTheme.theme`) and `HayaseLaunchLogo` (the mark, `#fff`), square, centred, `0.124219 ×` the width of the view.
It was a black screen with an 80pt mark. iOS caches launch screens, so it shows after the app has been deleted and installed again.

## 2. The page the app opens on (`src/routes/+page.svelte`)

`/` is not a blank page: it is the splash, and then it goes (`goto(data.goto, { replaceState: true })`) to Home, or to the setup
when `setup-finished` is behind `SETUP_VERSION`. A restart of the interface (`location.reload()` on the page it was on) does not pass through it.

On a black screen, a `size-10` (40pt) box in the middle, at the time of the page's mount `t`:

| | |
| --- | --- |
| box | `logo-scale .2s ease-out .2s both`: scale 5 to 1, from 0.2s to 0.4s; its `animationend` is the end of the splash |
| logo | white, through `chromaticAberration`: its red ×4 (pure red) moved 4 right, its green ×3 and blue ×10 (pure cyan) moved 6 left, screened (white where they meet); both offsets run to 0 from 0.15s over 0.1s (linear); the filter's region (the box ±10%) cuts what goes beyond |
| 6 spotlights | boxes `2.1 × size` by `size` of `linear-gradient(to right, #fff, transparent)`, through the same filter and `blur(3px)`; `left/top` the box's corner, `origin-left`; `rotate(angle) perspective(size × 2px) rotateY(dist × -50deg - 20deg)` with `dist = (192 - min(distance, 192)) / 192` (0.9219 for all); position, angle and size run from their `--from-*` values over 0.1s from 0.15s (ease-out); the opacity is `dist ×` a factor that goes from 1 to 0 over 0.55s (ease-out) |

`Routes/Splash`: `SplashPage.swift` (`SplashViewController`, the page, which `AppDelegate` shows first and replaces with Home or the setup with the crossfade of
a view transition), `SplashLogoView.swift` (the box, the logo and its aberration), `SplashSpotlight.swift` (the six streaks, their data copied from the page).
The mini player of the last session is restored when the app takes the splash's place, as it is mounted by the app's layout.

Not the same, by necessity (there is no CSS filter or blur on a layer):
- The streaks' blur is made once, at their final size, and scaled for the smaller size they start as (so the blur grows with it, and the 4pt/6pt offsets scale with it too for those first 0.1s).
- The filter's 10% region is not applied to the streaks (it is to the logo), so their cyan reaches further left than in the page.
- The two colours of the streaks are added (the screen of colours that do not share a channel), where the page puts them through its own alpha.
- The `await promise` before the `goto` (the stores read, the next page loaded) has nothing to wait for. Only the animation can hold the splash up, and it is let go of after 2 seconds if it has not ended (the app was held up by a call, or the screen locked).

Not checked: written without a compiler or a device. Look at the first 0.6s on a device, frame by frame if it can be had, against the web.
