//
//  MALAuth.swift
//  Hayase
//
//  MyAnimeList OAuth2 PKCE authentication provider.
//  Mirrors: src/lib/modules/auth/mal.ts
//
//  Handles MAL OAuth2 PKCE flow: generates code verifier/challenge,
//  opens the authorize URL, exchanges the authorization code for an
//  access token, and fetches the viewer profile. Provides list sync
//  and entry update capabilities matching the interface's mal.ts.
//

import Foundation
