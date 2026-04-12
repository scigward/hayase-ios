//
//  Client.swift
//  Hayase
//
//  Auth aggregator — manages multiple authentication providers.
//  Mirrors: src/lib/modules/auth/client.ts
//
//  The AuthAggregator class coordinates between AniList, Kitsu, MAL,
//  and Local auth providers. It delegates queries to the appropriate
//  provider, handles multi-provider sync for watch/delete/entry
//  operations, and manages sync settings per-provider.
//

import Foundation
