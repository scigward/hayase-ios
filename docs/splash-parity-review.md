# Splash parity review

The interface's splash is the animated page it opens on. The launch screen before it is plain black.

## 1. The launch screen: black, with no logo

The interface shows nothing before its splash page: the document is `bg-black`, and the page's first frame is already the
logo at five times its size (see 2). The mobile wrapper (`capacitor`) has a splash of its own, `#e5204c` with the white mark
(`capacitor.config.js` `SplashScreen: { launchShowDuration: 0 }`, and `build:assets` with `--splashBackgroundColor #e5204c`),
but the interface itself does not show a red logo first, so it was taken out.

`Base.lproj/LaunchScreen.storyboard` is a black screen. (It was a black screen with an 80pt mark, then, for a while, the red one.)
iOS keeps launch screens cached, so a change shows after the app has been deleted and installed again.

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
a view transition), `SplashPage.swift` (the box, the logo and its aberration), `SplashPage.swift` (the six streaks, their data copied from the page).
The mini player of the last session is restored when the app takes the splash's place, as it is mounted by the app's layout.

Not the same, by necessity (there is no CSS filter or blur on a layer):
- The streaks' blur is made once, at their final size, and scaled for the smaller size they start as (so the blur grows with it, and the 4pt/6pt offsets scale with it too for those first 0.1s).
- The filter's 10% region is not applied to the streaks (it is to the logo), so their cyan reaches further left than in the page.
- The two colours of the streaks are added (the screen of colours that do not share a channel), where the page puts them through its own alpha.
- The `await promise` before the `goto` (the stores read, the next page loaded) has nothing to wait for. Only the animation can hold the splash up, and it is let go of after 2 seconds if it has not ended (the app was held up by a call, or the screen locked).

Not checked: written without a compiler or a device. Look at the first 0.6s on a device, frame by frame if it can be had, against the web.
