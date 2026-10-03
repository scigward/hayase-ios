# Splash parity review

What the interface's mobile app shows while it starts, from the repositories of github.com/hayase-app:

- `capacitor/capacitor.config.js`: `SplashScreen: { launchShowDuration: 0 }`. On iOS the plugin's `showOnLaunch()` returns at
  once for a duration of 0, so there is no plugin overlay and no fade: what is shown is the launch screen alone, until
  the app draws.
- `capacitor/package.json`, `build:assets`: `capacitor-assets generate --iconBackgroundColor #e5204c
  --iconBackgroundColorDark #e5204c --splashBackgroundColor #e5204c --splashBackgroundColorDark #e5204c --android`,
  from `resources/logo.png` and `resources/logo_dark.png`. The same colour for light and dark.
- `@capacitor/assets` makes such a splash by putting the logo on a canvas of the background colour, resized to
  `logoSplashScale` (default 0.2) of the canvas width, in the centre. The generated Android splashes are one per
  orientation and density, each as wide as its screen, so the logo is 20% of the width of the screen in either orientation.

So the splash is a screen of `#e5204c` (the theme colour, `UIColor.HayaseTheme.theme`) with the white Hayase mark in the middle,
a fifth of the width of the screen across. `Base.lproj/LaunchScreen.storyboard` is that: the red background, and
`HayaseLaunchLogo` (the mark, `#fff`) centred with a width of `0.2 ×` the view's, square. It was a black screen with an 80pt mark.

Not checked: `resources/logo.png` itself was not looked at (the mark is taken to be the white one of the app icon), and iOS
keeps launch screens cached, so it shows after the app has been deleted and installed again.
