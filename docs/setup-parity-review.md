# Setup parity review

The first-run setup of `interface/src/routes/setup`, ported to `Hayase/Source/Routes/Setup`. It shows until
`setup-finished` has reached `SETUP_VERSION` (3), as `routes/+page.ts` and `routes/app/+layout.ts` decide, and
Settings → Reset Everything clears that with the rest, so it comes back after a reset.

## Where each piece of the interface is

| Interface | Swift |
| --- | --- |
| `setup/+layout.svelte` | `SetupLayout.swift` (`SetupLayoutView`, `SetupGridBackground`, `SetupViewController`) |
| `setup/+page.svelte` | `SetupPage.swift` (`SetupWelcomePage`) |
| `setup/Progress.svelte` | `SetupProgress.swift` |
| `setup/Footer.svelte` | `SetupFooter.swift`, `SetupFooter.swift`, `SetupFooter.swift` |
| `setup/storage`, `network`, `extensions` | `SetupStoragePage.swift`, `SetupNetworkPage.swift`, `SetupExtensionsPage.swift` on `SetupStepView.swift` |
| `network/+page.svelte` `speedTest` | `SetupNetworkPage.swift` (@cloudflare/speedtest 1.13, ported from its source) |
| `$lib` `SETUP_VERSION`, `localStorage` keys | `SetupFlow.swift` |
| `ui/checkbox`, `ui/tooltip`, `icons/Logo.svelte` | `Components/UI/Checkbox`, `Components/UI/Tooltip`, `Components/UI/Img/Logo.swift` (the sidebar uses the same logo path) |
| `SettingCard.svelte` | `SettingsCardView` (now `bg-transparent`, label target and `self-baseline` aware) |
| `native.checkIncomingConnections` | bridge method `checkIncomingConnections` (bridge v11) |

## Details that are not what they look like

- `Label class='text-md …'`: tailwind-merge treats `text-md` as a font size, drops `text-sm`, and Tailwind has no
  `text-md`, so the terms label is the page's 16px on a `leading-none` (16px) line, medium weight.
- The `for='terms'` of that label names no element: a tap on its text does nothing. The two links are
  `py-2 px-1` inline boxes; the padding is spaced into the text and is part of the tap target.
- The progress track fills 15% / 50% / 85% (`translateX(-85/-50/-15%)`); the first badge is always `default`, the
  other two are `secondary` (muted icon) until reached, then `default` with a `text-background` icon.
- The check spinner is a ring with four equal borders (`border-border border-b-border`), so `animate-spin` turns
  it without anything showing; it is drawn as the static ring.
- The success and error marks are lucide icons with `strokeWidth='4px'` in a 16px badge with `p-[3px]` and a
  1px border, so in an 8px box: they are drawn at a third of their size (stroke 4/3) inside the circle. The
  first version drew them at 24px, spilling over the badge, which was wrong. The warning mark is its own 2x7 svg
  in black, which fits as it is.
- The port-forwarding help icon is `size-4` with `border-b`: 16px high including its 1px border, so the icon is
  15px.
- `SettingCard` titles are 21px high, not 20: `leading-[unset]` on the label leaves the line to `html`'s
  `line-height: 1.5` (corrected for every settings card).
- Transfer Speed Limit's box is `self-baseline`, so from `md` it sits at the top of its card's row, not the middle.
  Its box has a border of its own (130px across).
- Every `input` scales to 98% while it is pressed (`app.css`); the speed field is `no-scale` in a `scale-parent`,
  so it is its box that scales. The read-only download path is a field of its own that cuts the text off between its paddings, with no ellipsis (a text field with a clipping line break drew the rest of the path over its neighbours).
- The checkbox is placed by the page, so it has no constraints of its own (a constrained view with no position sat
  in the top corner of the page).
- The welcome column is `justify-center`: a window too short for it loses the top, which cannot be scrolled to.
  This is kept.
- The extensions page sets `lookupPreference` whenever it is made (`quality` after a forwarded port, else
  `seeders`), and its check never settles until an extension is installed.
- A finished speed test is not run again: `play()` after the end does nothing. It runs on from the page it started on.

## Differences that are on purpose

- iOS: no DNS over HTTPS cards (`SUPPORTS.isIOS`). The download location is chosen from Cache and Internal
  Storage, as in the app's client settings. The forwarded port is limited to 65535 (the page says 65536).
- The free space is the available capacity of the volume of the download folder, read in Swift.
- The port check goes to the torrent client through the bridge. It needs the `torrent-client` build to have
  `checkIncomingConnections`; if it does not, the row reads "Failed to check port forwarding availability. …".
- The speed test does not report its result to Cloudflare (`logAimApiUrl`), and does not calibrate a server time
  delta, which only HTTP/1.1 connections do.
- The tooltip of the waiting button opens for an iPad pointer; a touch has no hover.
- The bottom safe area is not applied, as in the interface (`#root` pads only the top).

## Not checked

Written without a compiler or a device: only `swiftc -parse` and `node --check` ran. Check on a device: every
breakpoint (phone, iPad portrait, landscape), the welcome page at a short height, the crossfade between pages, the
footer while checks settle, the speed test on a slow connection, the port check, and an extension being installed
on the last step.
