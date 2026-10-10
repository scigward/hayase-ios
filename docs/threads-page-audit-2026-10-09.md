# Threads page audit: Swift app against the interface

Date: 2026-10-09. Swift app: `bd1cb5e` on `master`. Interface: `interface/src`, the source of truth.

This is a list and a record. Nothing was changed while it was written.

## What is covered

"The threads page" is four things that the interface keeps together:

1. **The Threads tab** of the anime page: `lib/components/ui/forums/Threads.svelte`, with `Pagination.svelte`, `Tooltip` and `Avatar`.
2. **The thread route**: `routes/app/anime/[id]/thread/[threadId]/{+layout.ts,+layout.svelte,+page.svelte}`, which the anime page shows in place of its tabs.
3. **Its comments**: `Comments.svelte`, `Comment.svelte`, and the reply writer `Write.svelte` with `ui/markdown`.
4. What they stand on: `Shadow.svelte` (the body renderer), `Profile.svelte`, the AniList queries and cache rules (`queries.ts`, `client.ts`, `urql-client.ts`).

Swift counterparts: `Components/UI/Forums/{Threads,Comments,Comment,Write}.swift`, `Components/Pagination.swift`, `Components/Shadow.swift`, `Modules/AniList/AniListForumClient.swift`, the thread parts of `Modules/Navigation/Router.swift` and `Routes/App/Anime/[id]/{Layout,Page}.swift`.

## How it was checked

- Both sides were read in full.
- The interface was run (`vite dev`) in the Browser pane and measured: `getBoundingClientRect` and `getComputedStyle` on the live page, with real AniList data (anime 16498, threads 52428 and 51899). Widths: **1194x834** (an iPad in landscape, `md` and up) and **390x844** (below `md`). Hover was tried with the pointer.
- Swift values are read from the code. Nothing was compiled or run on a device, so every Swift value below is "what the code says".
- Not measured: the reply writer (it needs an AniList sign-in; read from source), the profile popover, the `...` item of the page buttons (it needs seven or more pages), VoiceOver.

## How to read an entry

Same scale as `docs/full-app-audit.md`. **Severity**: *High* = a feature is missing or the page looks wrong everywhere; *Medium* = a visible difference or an added or missing behaviour; *Low* = small or rare. **Confidence**: *Measured* = measured in the running interface and read in Swift; *Confirmed* = read in both sources; *Likely* = follows from the code but depends on timing or a device; *Needs device* = cannot be settled without running the app. A difference that a code comment explains as intended is in [Documented deviations](#documented-deviations-that-stay), not listed as a defect.

## Summary

| Section | Entries | High | Medium | Low |
| --- | ---: | ---: | ---: | ---: |
| 1. Threads tab (the list) | 11 | 0 | 3 | 8 |
| 2. Thread page | 13 | 1 | 5 | 7 |
| 3. Reply writer | 3 | 1 | 1 | 1 |
| 4. Rich text | 5 | 0 | 3 | 2 |
| 5. Data and navigation | 4 | 0 | 1 | 3 |
| 6. Structure | 1 | 0 | 0 | 1 |
| **Total** | **37** | **2** | **13** | **22** |

The ones with the biggest effect:

- `TH-20` the thread page has the wrong vertical rhythm everywhere: comments touch each other (0 where the interface has 24, or 16 below `md`).
- `TH-40` the reply writer is a plain text box; the interface has a markdown editor with a toolbar.
- `TH-01`, `TH-02`, `TH-22`, `TH-50` colours and sizes of the text on the cards and in the posts are not the interface's (stats are 9.6 pt grey instead of 12.8 px near-white, dates are grey instead of near-white, bodies are lighter than the interface's).
- `TH-60` opening a thread waits for the network; the interface opens it at once from what the list already has.
- `TH-25` every change in the comments rebuilds the whole page, post and its web view included.

## 1. Threads tab (the list)

### TH-01 Stats row: font and colour. Medium, Measured

- Interface: row 1 of the card is `text-[12.8px]`, and the stats block inherits it and the card's `text-secondary-foreground`. Measured: 12.8px, line-height 12.8px, colour 0.98, `mt-0.5 ml-2`; icons 12px with `mr-1`, and `ml-2` before the second and third icon.
- Swift: `ThreadCardView.configure` calls `statsView.configure(...)` without a size (`Threads.swift:221`), so the labels are 9.6 (`Threads.swift:96`). The icons and the numbers are grey 0.6 (`:77`, `:86`). The thread page passes 12.8 (`Comments.swift:619`) and gets the same grey.

### TH-02 The "since" line: colour. Medium, Measured

- Interface: it inherits the card's `text-secondary-foreground`: measured 0.98 (near-white), 9.6px.
- Swift: `UIColor(white: 0.5)` (`Threads.swift:135`), which is muted-foreground. A different grey from the stats too.

### TH-03 Title colour. Low, Measured

Interface 0.98 (`secondary-foreground`). Swift `.white`, 1.0 (`Threads.swift:125`).

### TH-04 Footer geometry and card height. Low, Measured

- Interface: padding 12 / 16. Row 1 is the title (12.8px bold, line-height 19.2) plus `mb-2` 8 = 27.2. Row 2 is `pt-2` 8 plus the 16px avatar (`items-end`) = 24. The card is the sum: **75.2**. A thread without user or badges has a 14.4 text line instead of the avatar: 73.6. The avatar has `mr-2`: 8.
- Swift: height fixed at 75 (`Threads.swift:187`); the footer sits 14 from the bottom (`:197`, `:202`) where the interface has 12; avatar to text is 6 (`:182`) where it is 8; the footer's top bound is the title plus 6 (`:201`), where the interface has 8.
- Effect: the footer line is about 2 pt higher than the interface's and 2 pt closer to the avatar.

### TH-05 Space below the last row. Low, Measured

- Interface: the grid has `pt-3` and `gap-y-7` (28) and nothing below the last row; the footer's own `py-3` gives **12** between the last card and the page buttons (measured: the footer box starts where the last card ends).
- Swift: every row cell has 14 above and 14 below (`Threads.swift:328`, `:337`), only the first row's top is 12 (`:348`). The last row adds 14 to the footer's 12: **26**. The skeleton has the same 14 (`:646`).
- The gap above the first row is right: tab bar `mt-2` 8 plus `pt-3` 12 = 20 (measured); Swift has 8 (`Layout.swift` tab bar container) plus 12.

### TH-06 Category badges. Low, Measured / Likely

- Colour: the interface's `text-contrast` gives a pure black or pure white (`rgb(X,X,X)` with `X = ((299R + 587G + 114B) / 1000 - 128) * -1000`, clamped). Measured: `rgb(0,0,0)` on `rgb(241,161,67)`. Swift's `luminanceContrastColor` (`SearchModal.swift:657`) returns grey 0.07 for light backgrounds instead of black.
- No cover colour: the interface background is `#27272a` and the text is **black** (`colors()` defaults to white, so contrast is black). Swift falls back to grey 0.15 with white text on the list (`Threads.swift:562`) and to `secondary` on the page (`Comments.swift:40`).
- Height (Likely): `py-0.5` around a 14.4 line = 18.4. A `UILabel` line of 9.6 pt is shorter.
- Wrapping: the container is `flex-wrap gap-2` and the card grows to `max-h-28` (112). Swift's badges are one row that does not wrap, and the date label is squeezed instead (`Threads.swift:203`).

### TH-07 Avatar placeholder. Low, Confirmed

- Interface: `Avatar.Fallback` is `bg-muted`, the card's own colour (0.04), so only the clipped name shows while the image loads or fails; it exists for every thread that has a user.
- Swift: a grey 0.16 circle (`Threads.swift:141`), and no circle at all when the user has no avatar URL (`:264`).

### TH-08 Lock icon. Low, Confirmed

The interface's lock is `ml-2 mr-1`: 4 more points to its right. Swift stops at the icon (`Threads.swift:61`). The interface's text and icons are top-aligned in the block; Swift centres them.

### TH-09 Title tooltip is missing. Medium, Measured

- Interface: the title is a `Tooltip.Trigger` (`tabindex=-1`). Hovering it with the pointer opens a bubble above it with the whole title: `bg-primary text-primary-foreground rounded-md px-3 py-1.5 text-xs`, 28 high (observed).
- Swift: none, although `Components/UI/Tooltip/TooltipContent.swift` exists. A long title is only cut with "…".

### TH-10 Hover shadow. Low, Measured

- Interface `select:shadow-lg`, measured: `0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)`, with `transition-[transform,box-shadow] duration-200 ease-out`. Scale 1.05 and `bg-accent` (0.08) are right.
- Swift: one shadow, radius 18, opacity 0.45, offset 8 (`SelectableCardView.swift:61-63`): much larger and darker. It is shared with the episode cards, so the same fix covers both.

### TH-11 Accessibility of the cards. Low, Needs device

The interface card is an `<a>`: VoiceOver reads its text as a link. The Swift cards have no accessibility label, trait or element flag (no `accessib` in `Forums/*.swift`, `SelectableCardView.swift` or `Pagination.swift`).

## 2. Thread page

### TH-20 Vertical rhythm. High, Measured

The thread page is not wrapped in anything: header, post, "N Replies", every comment and the page buttons are direct children of the anime layout's `gap-4 md:gap-6` column. Measured:

| Between | Interface at 1194 (md) | Interface at 390 | Swift |
| --- | ---: | ---: | ---: |
| genres row and the thread header | 24 | 16 | 24 / 16 (`Threads.swift:516`) |
| header and post | 24 | 16 | 16 |
| post and "N Replies" (`mb-10` + gap) | 64 | 56 | 40 (`Comments.swift:179`) |
| "N Replies" and the first comment | 24 | 16 | 16 |
| comment and comment | **24** | **16** | **0** (`Comments.swift:211`) |
| last comment and the page buttons (then their own `py-3` 12) | 24 | 16 | **0** (`:211`) |
| page bottom (`pb-10`) | 40 | 40 | 32 (`Threads.swift:519`) |

The 0 between comments is the visible one: the cards touch. The skeleton cards have the same 0 (`Comments.swift:223`), where the interface's 4 skeletons are 24 / 16 apart too.

### TH-21 Post header spacing. Medium, Measured

- Interface: the user row (32 avatar, `mb-2` 8) makes the header **40**; the stats block is `mt-0.5` (2). The body then has `my-3` (12).
- Swift: `ThreadPostView` has no space under the header row (`Comments.swift:524-598`, `rootStack.spacing = 0`, no custom spacing) and no 2 above the stats, so the body starts 8 pt too high. `ThreadCommentView` does it right (`Comment.swift:123`).

### TH-22 Date and stats colours on the post and comments. Medium, Measured

- The post's and the comments' date text inherits `text-secondary-foreground`: measured 0.98. Swift uses muted-foreground 0.5 (`Comments.swift:581`, `Comment.swift:148`).
- The post's stats use `ThreadStatsView`, so they are grey 0.6 (see `TH-01`); the interface's are 0.98. The comments' like count is right (0.98).

### TH-23 Title sizes follow the screen, not the window. Medium, Confirmed

The interface switches `text-[20px]` / `md:text-2xl` live at 768 px of the window. Swift reads `UIScreen.main.bounds.width` (`Comments.swift:466`), once, when the page is built: in Split View, Slide Over or Stage Manager it is wrong, and it does not change when the window is resized or rotated. The page buttons beside it use the window (`Pagination.swift:83`).

### TH-24 Fallback texts. Low, Confirmed

- A thread without a user: the interface shows nothing; Swift writes "Unknown" (`Comments.swift:613`).
- A thread without a title: the list says `Thread <id>` (right) but the page says `No thread title...`. Swift's model turns a null title into `Thread <id>` for both (`AniListTypes.swift:368`), so the page never says it. The page's `?? ` only catches a null, so an empty string is shown empty in the interface; Swift shows "No thread title...".

### TH-25 Every comments change rebuilds the whole page. Medium, Confirmed

Changing the comments page, the loading skeleton, a failed page and a refresh all call `renderBase` (`Comments.swift:155`, `:218`, `:243`), which removes every view and builds the post card again, including its web view. The interface replaces only the comments. Effect: the post flashes and reloads, its height changes for a moment (the scroll jumps), and the web view is parsed again each time.

### TH-26 After send or delete. Low, Confirmed

- Interface: the mutation invalidates the thread comments in the cache and the comments query runs again. The thread (reply count, likes) is not refetched.
- Swift: `fetchThread()` (`Comments.swift:440`, `:451`) refetches the thread and the comments, with a centred spinner, and rebuilds everything. The reply count changes where the interface's does not (until the next visit).
- `saveComment` also passes the thread id as `rootCommentID` (`:437`), which only works because the Swift cache is keyed by thread; the interface passes the root comment's id.

### TH-27 Page-buttons count while a comments page loads. Low, Confirmed

The interface reads `$comments.data?.Page?.pageInfo?.total ?? 0`, so while a page loads the footer says "Showing 16 to 0 of 0 comments" with the previous button on and no numbers. The Threads tab copies this quirk (`threadCount` is 0 until the page is there); the comments do not: they keep the previous total (`Comments.swift:226`).

### TH-28 Mobile quirks. Low, Measured

At 390 the interface's page arrows are **28.8** wide, not 36: the `w-full` text takes the room and the buttons shrink. Swift's are fixed 36 (`Pagination.swift:160`, `Button.swift:35`). The back button of the thread header also shrinks (30.3 measured) with a long title; Swift's is fixed 36.

### TH-29 The `...` item. Low, Needs device

The interface's `...` is a 36x36 `span`, 16px text (`text-center`, no vertical centring: the dots sit where a 24px line puts them). Swift's is a 14pt label centred in 36x36 (`Pagination.swift:166-178`): smaller and probably lower.

### TH-30 Text metrics. Low, Likely

CSS sizes every line from its `line-height` (1.5, or `leading-none`); UIKit uses the font's metrics. Where a label decides a height the result differs: the comment header (interface 28 = 20 avatar + 8; Swift 8 + the 16pt label's line, about 22), the "N Replies" row (32; the 24pt label's line is about 33), the stats and date lines. Setting fixed line heights on these labels, as the combobox now does, would match them.

### TH-31 Alert on a failed like, send or delete. Medium, Confirmed

Swift shows a modal "Ooops!" `UIAlertController` (`Comments.swift:459`). The interface has nothing: `client.toggleLike`, `comment` and `deleteComment` are fire-and-forget, there is no error handler on the AniList client, and urql only undoes the optimistic like. This is a behaviour the interface lacks.

### TH-32 The comments skeleton does not pulse. Low, Confirmed

The thread list's skeleton pulses (`HayaseSkeleton.makeBlock`); the comments' (`Pagination.swift:271-281`) are plain views. Interface: all of them `animate-pulse`. Geometry (112 high, 150/112/80/96 wide bars, 12 between, `py-[18px] px-4`) matches.

## 3. Reply writer

### TH-40 The editor. High, Confirmed

- Interface: `Write.svelte` uses `ui/markdown` = OverType 2.4: a **toolbar** (bold, italic, inline code | link | h1 h2 h3 | bullet, numbered, task list | quote | view mode), shortcuts (Ctrl+B, Ctrl+I), markdown syntax coloured while typing with the theme in `markdown.svelte` (headings `#e06c75` / `#e5c07b` / `#98c379`, strong, em `#c678dd`, link `#61afef`, code, quote, markers), list continuation and a link tooltip, on `#282c34`.
- Swift: a plain `UITextView` with the same two colours and the placeholder (`Write.swift:15`, `:42-50`). No toolbar, no styling, no shortcuts.

### TH-41 Dialog chrome. Medium, Confirmed

- Interface: the `Dialog` (overlay, `flyAndScale` 200ms) anchored to the bottom: `h-[90%] sm:h-1/2`, `border-t`, no radius, `gap-4` between the editor and the buttons, `px-4`, `!pb-4`, and the Cross2 close button at `right-4 top-4`.
- Swift: a system page sheet (`Write.swift:22`): no close button, system motion, the buttons start 8 below the editor (`:63`, the interface has 16).

### TH-42 Size class and `sm`. Low, Likely

The interface's sheet is 90% of the window below 640px and 50% above it. Swift picks by `horizontalSizeClass == .regular` (`Write.swift:93`), which differs in Split View and on some iPhones in landscape.

## 4. Rich text

### TH-50 Body colour. Medium, Measured

Interface: thread and comment bodies are `text-muted-foreground`, measured **0.5**. Swift's document sets `hsl(0 0% 63.9%)` (`Shadow.swift:113`), the old dark-theme value. Bodies are visibly lighter than the interface's.

### TH-51 Link and other default colours. Medium, Likely

The interface's root has `color-scheme: dark`, so links in the body are `rgb(158,158,255)` and underlined (measured by adding a link to a body's shadow root of the test page). The Swift document declares no colour scheme (`Shadow.swift:117-129`), so a web view uses the light defaults (`#0000EE` links) on a dark card. Fix direction: `color-scheme: dark` on the document.

### TH-52 Wrapping. Low, Confirmed

Swift's CSS adds `overflow-wrap: break-word` and `overflow-x: hidden` (`Shadow.swift:122-124`). The interface's host is `overflow-clip`, so a long unbroken word is cut; Swift wraps it. There is no comment that says this is intended.

### TH-53 One web view per body. Medium, Needs device

Each post and each comment, replies included, is its own `WKWebView` with its own configuration and non-persistent data store. Page 1 of thread 52428 has 22 bodies, thread 51899 has 40 (counted in the interface). Each view loads the base64 of the 277 KB font in its HTML (about 370 KB) and 72 KB of scripts. Memory and CPU grow with every comment, and a long page risks the system ending the app.

### TH-54 `webm()` without the leading `h`. Low, Confirmed

The interface turns `webm(i.imgur.com/x.webm)` into a `<video>` with a broken `src`; Swift drops it (`AniListRichText.js`, `if (!/^https?:\/\//i.test(url)) return ''`). No comment says why.

## 5. Data and navigation

### TH-60 Opening a thread waits for the network. Medium, Confirmed

- Interface: `+layout.ts` awaits `asyncStore(Thread, ..., 'cache-and-network')`, which resolves as soon as the store has data. The list already put the thread in the cache (same `ThreadFrag`), so the page opens at once and updates when the network answers.
- Swift: `navigateToAnimeThread` asks the network first and navigates when it answers (`Router.swift:222-253`), with the sidebar's navigation progress running meanwhile. The wait is a full round trip that the interface does not have when the thread comes from the list.

### TH-61 Thread data is not shared or live. Low, Confirmed

The interface's cache is normalised: a like on the thread page changes the count on the list card too, and the page keeps updating from the network. Swift's list holds its own copies (`threadPages`), so the list shows the old count after a like, and the page gets one answer.

### TH-62 A path the interface does not have. Low, Confirmed

`openThread`'s branch without an anime id pushes a thread controller (`Threads.swift:601-608`), and `ThreadDetailViewController` has a non-embedded mode with its own scroll view and spinner (`Comments.swift:93-114`, `:118`). The interface only has the route inside the anime page.

### TH-63 Scroll position. Low, Needs device

In the interface the scroll container is the anime layout's, which persists across `thread/[id]`: opening a thread keeps `scrollTop` (measured 900 stays 900 after going back), and back lands on the Episodes tab. Swift sets the Episodes tab (`Threads.swift:466`) and reloads the table; whether the offset survives needs a device.

## 6. Structure

### TH-70 Files and repeated code. Low, Confirmed

The rule is the interface's folders and file names.

- `Forums/Comments.swift` holds the thread route page (`ThreadDetailViewController`, `ThreadPostView`, which are `+page.svelte` and `+layout.ts`) and the list logic of `Comments.svelte`.
- `Forums/Threads.swift` (681 lines) holds `Threads.svelte` and also an `AnimeDetailViewController` extension (the embedded route, the page fetching) that belongs with the anime route.
- `Pagination.swift` holds `ThreadPaginationView` and the comments' skeleton, which is `Comments.svelte`'s.
- The "Ooops!" empty and error states are written three times (`Page.swift:395`, `Comments.swift:271`, `:316`).
- Suggested split: `Forums/Threads.swift` (cards, grid, skeleton, footer), `Forums/Comments.swift` (list, skeleton, states, footer), `Forums/Comment.swift`, `Forums/Write.swift`, and the route under `Routes/App/Anime/[id]/Thread/[threadId]/` (`Layout.swift` = `+layout.ts`, `Page.swift` = `+page.svelte`), with one shared empty/error state.

## What already matches

Checked, nothing to change:

| Part | Value |
| --- | --- |
| Grid | one column below 1040 of content width, two above (`repeat(auto-fit,minmax(500px,1fr))`), 40 across, 28 down, a single thread fills the row, a last odd card keeps its empty track; three columns cannot happen (`max-w-[1600px]`) |
| Page inset | 0 / 12 / 56 at 360 and 1280 |
| Card | radius 6, bg 0.04, paddings 12 / 16, title 12.8 bold one line with "…", date 9.6, scale 1.05 and `bg-accent` 0.08 on hover |
| Skeleton | 4 cards, 75 high, bars 112x8 and 80x8 at 18 / 16, pulse 2s, same columns |
| Page buttons | 36 high and wide, gap 8, `outline` for the current page, `ghost` the others, disabled 0.5, text 13 muted with bold numbers, desktop and mobile variants, `5000` shown as 17 |
| Empty and error | 320 high, "Ooops!" 36 bold, 18 muted lines, 20 side padding |
| Data | queries, `perPage` 16 and 15, `ID_DESC`, "Anime" category removed, `since()`, the first page taken from the anime page query |
| Post and comment | radii, paddings (24/32 and 16 / 24), avatars 32 and 20 with `mr-4` and `mr-2`, nested `pl-4 py-2 pr-2`, alternating backgrounds, icon buttons 25.6 / 11.2 icons / `rounded-sm` / disabled 0.5, like button and optimistic like, owner-only edit and delete, delete without confirmation |
| Route | the load before the page shows, the error page on a failed load, the anime header kept, the tab bar hidden |
| Rich text | the markdown pipeline (marked 18, DOMPurify 3, the same replacements), 16/24 for threads and 14/20 for comments, spoiler, YouTube and video handling |

## Documented deviations that stay

- Anime links in bodies keep the last digit of an id (`AniListRichText.js` comment); the interface cuts it when the URL has no trailing slash.
- A second DOMPurify pass and the iframe and video attributes, with `playsinline` (needed inline on iOS).
- Links open with `UIApplication.open` for `http`, `https` and `mailto` only.
- Offline queue for `ToggleLikeV2`, and a time limit on cached thread pages (`cacheFirstMaxAge`), because Swift's cache is in memory and the interface's is not.

## Not verified

- The reply writer in the interface: it needs an AniList sign-in, so its sizes come from the source and the OverType package.
- The `...` item (`TH-29`) and the profile popover opened from a thread avatar.
- The scroll offset (`TH-63`), the memory of many web views (`TH-53`), the link colour (`TH-51`), VoiceOver (`TH-11`).

## Proposed order, when the work starts

1. Spacing and colours: `TH-20`, `TH-21`, `TH-22`, `TH-01` to `TH-05`, `TH-50`, `TH-51` (the visible ones, small edits).
2. Page structure: `TH-25`, `TH-26`, `TH-27`, `TH-23`, `TH-30`, `TH-31`, `TH-32`, `TH-28`, `TH-29`.
3. The title tooltip (`TH-09`), the shadow (`TH-10`, with the episode cards), the card details (`TH-06` to `TH-08`, `TH-11`).
4. Opening a thread from the cache and sharing the thread data (`TH-60`, `TH-61`).
5. The writer (`TH-40`, `TH-41`, `TH-42`).
6. Web view cost (`TH-53`) and the file split (`TH-70`, `TH-62`).

## Decisions (made 2026-10-10: the better option, whatever the work)

- **Writer**: the interface's own editor. OverType 2.4 (MIT, 120 KB minified, bundled so nothing is fetched) runs in a web view with the same options as `markdown.svelte` (toolbar, theme colours, placeholder, `autoResize: false`), and its value comes back through a message handler on `onChange`. The dialog around it is native and follows `Dialog` (overlay, `flyAndScale`, the close button, anchored to the bottom), with native Close and Send buttons. A native clone of the editor would never match its list continuation, view mode, link tooltip and the syntax overlay, and would drift with every OverType release.
- **Web views**: the aim is a page whose cost does not grow with its replies.
  1. One shared `WKProcessPool` and data store, the font and scripts served from the bundle through a URL scheme (so each view's HTML is a few KB, not about 440 KB), and the markdown parsed and sanitised once in one shared renderer view, so a body view gets plain sanitised HTML and no scripts of its own.
  2. Only the bodies near the screen keep a live view; the shared renderer measures every body so card heights are known and the layout does not jump while scrolling.
  Step 1 first, step 2 after it has been run on the device: nothing here can be run on a Mac, so each step is tested before the next.
