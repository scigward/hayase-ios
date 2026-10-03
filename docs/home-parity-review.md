# Home parity review

Scope: `interface/src/routes/app/home/+page.svelte` and what it is made of, against the Swift Home page.
No Apple toolchain was available, so the changes were checked by reading both sources, not by running
the app: `swiftc -parse` is the only compile check there has been.

## Structure

The Swift Home was a single file (`BrowseAnimeViewController.swift`, 2,900 lines). It is now the same
set of pieces as the interface, one file per piece.

| interface | Swift |
| --- | --- |
| `routes/app/home/+page.svelte` | `Routes/App/Home/HomePage.swift` (`HomeViewController`), `HomePage+DataSource.swift`, `HomePage+Banner.swift` |
| the section queries in its `<script context='module'>` | `Routes/App/Home/Sections.swift` |
| the header of each section | `Routes/App/Home/SectionHeader.swift` |
| `ui/banner/banner.svelte` | `Components/UI/Banner/Banner.swift` |
| `ui/banner/banner-image.svelte` | `Components/UI/Banner/BannerImage.swift` |
| `ui/banner/full-banner.svelte` | `FullBanner.swift`, `FullBanner+Layout.swift`, `FullBanner+Artwork.swift`, `FullBannerTitle.swift`, `FullBannerBadges.swift`, `FullBannerFollowing.swift`, `FullBannerProgress.swift` |
| `ui/banner/skeleton-banner.svelte` | `Components/UI/Banner/SkeletonBanner.swift` |
| `ui/cards/query.svelte` | `Components/UI/Cards/QueryCard.swift` |
| `ui/cards/small.svelte`, `episode.svelte` | `Components/UI/Cards/AnimeCollectionViewCell.swift` |
| `ui/cards/skeleton.svelte` | `Components/UI/Skeleton/Skeleton.swift` (`SkeletonCardCell`) |
| `ui/cards/preview.svelte` | `Components/UI/Cards/PreviewCard.swift` |

The class is `HomeViewController` now (it was `BrowseAnimeViewController`; `Main.storyboard` follows).

## Differences found and fixed

Page
- A section's title now leads to the search too, not only "View More"; both turn `text-foreground`
  while hovered or pressed and shrink to 98% while pressed.
- Section headers are 38pt (`pt-5` and an 18pt line), not 42pt, and their texts are bottom aligned
  (`items-end`) rather than baseline aligned. Their colour is the theme's `muted-foreground`, not a
  literal.
- Rows had 20pt of extra space under them: the interface's `-mb-5 pb-5` takes nothing from the page.
- Loading shows 20 skeletons (it showed 10); before the query has started they do not pulse; they
  run `load-in` as they mount; a skeleton row is 322pt, a message row 320pt, a card row 323pt.
- "Ooops!" is `text-4xl font-bold`, its lines `text-lg text-muted-foreground`, in a `h-80` box as wide
  as the row; a failure also says "Looks like something went wrong!" above the error.
- The first card of a row has its preview start-aligned below `md` (`first={i === 0}`).
- Removed what the interface does not have: the spinner and "No anime found" label (the sections are
  never empty), swiping the banner, selecting the banner anywhere to open the media.

Banner
- A failed banner query shows the same "Ooops!" block, at the top of the banner (`h-72`).
- Only the title (or the logo) is a link to the media, in a box `min(900, 85%)` wide; it turns
  `muted-foreground` and underlined under a pointer.
- `text-balance` on the title and the description.
- The description keeps "No description available." for a missing description only, and collapses
  white space, so a paragraph break does not break the line.
- Format and status are always there ("N/A" when AniList has none); the season button no longer sends
  an empty season; the default-variant buttons have their `shadow`, the genres (ghost) do not.
- "Also Watched This Series": 16pt over 20pt text lines with nothing between, avatars and text from
  the top, the avatars fade in when the followers change.
- The play button has its `shadow`, a 12.8pt icon and 8pt (not two spaces) between icon and label;
  `text-contrast` is black from a luminance of 128, as the CSS clamps it.
- The progress badges are clickable over their whole `pt-2 pb-4` wrapper including `mr-2`.
- The picture fades in 500ms with Tailwind's easing (`duration-500`), on Home, in the sidebar and on the
  anime page (it was 300ms).

Cards
- Title: `text-foreground` (not white), 12.8pt on a 19.2pt line; the status dot is inline, on the baseline,
  and the second line starts under it.
- Year and format: `text-muted-foreground`, 16pt icons that stick out 2pt past the padding (they were
  12pt, flush).
- The cover fades in as `Load` does, blurred when it arrives right away.
- Hovering with a pointer waits 30ms and restarts when the pointer moves.

Preview card
- The title has its `pt-2` and 28pt line, details and description their 16.5pt and 16.8pt lines, the
  buttons are 25.6pt: everything under the banner sat a few points off.
- Buttons are real `Button`s: the default variant with `shadow`, the ghost variant, press and hover
  states and the animated icons.
- The bullets between the details have `.3rem` of room each side and are centred in the line; the
  details are clipped, not ellipsised.
- The preview disappears at once when it is not hovered (no fade out), is not moved into the screen,
  and is centred on the card's 323pt rather than starting at its top.

## Left as it is

- The cover that hides the banner picture when the page is scrolled past (`HomePage+Banner.swift`) is a
  documented stand-in for the 5% opacity of `hideBanner`: it hides the picture entirely instead.
- `dragScroll` (mouse drag scrolling) and keyboard/gamepad focus have no touch counterpart.
