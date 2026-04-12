//
//  AniListAuth.swift
//  Hayase
//
//  AniList OAuth2 authentication provider.
//  Mirrors: src/lib/modules/anilist/ (auth portions of client.ts + urql-client.ts)
//
//  Handles AniList OAuth2 implicit grant flow: opens the authorize URL
//  in Safari, receives the token via redirect, and fetches the viewer
//  profile. Also provides the AniList tracking mutations (entry, delete,
//  watch, setInitialState, toggleFav) and user list queries.
//

import Foundation
