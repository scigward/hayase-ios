---
# Fill in the fields below to create a basic custom agent for your repository.
# The Copilot CLI can be used for local testing: https://gh.io/customagents/cli
# To make this agent available, merge this file into the default repository branch.
# For format details, see: https://gh.io/customagents/config

name: scig
description: Hayase iOS port agent
---

# My Agent

1: When working on adding new features from "https://github.com/hayase-app/interface/tree/master" when creating files for the new feature you have to preserve the interface Architecture here, That includes: 
     1: Preserving identical directory/folder names
     2: Preserving identical file names
     3: When files are seperated in interface for one component for easier maintainability for example "interface/src/lib/components/ui
/player" is seperated into 20 different files, These files are 
```
animations.svelte

castplayer.svelte

chapters.ts

downloadstats.svelte

episodesmodal.svelte

externalplayer.svelte

index.ts

keybinds.svelte

maps.ts

mediahandler.svelte

options.svelte

pip.ts

player.svelte

resolver.ts

seekbar.svelte

subtitles.ts

thumbnailer.ts

util.ts

volume.svelte

wrapper.svelte
```
So what this means is that you HAVE to preserve an identical repository architecture of interface here.

Though please note that there are exceptions, Because the hayase web Interface app is designed to run for desktop and Android devices, So we have to remove some features because they aren't possible on iOS devices, That said, We've currently ported basically everything except some small features we still haven't worked to port yet.

2: When working with UI you HAVE to read the "https://github.com/hayase-app/interface" source code and match the same identical interface UI here in swift with EVERY single detail preserved and identically replicated in swift, No features added and no features removed, Perfect identical preservation.

3: When working on certain functionality components of the app (For example AniList) you HAVE to read "https://github.com/hayase-app/interface/tree/master" source code and replicate it here in swift with every single detail preserved, No features added and no features removed, Perfect identical preservation.

4: Lastly, You need to validate your changes matches interface identically after you're done with the user request.
