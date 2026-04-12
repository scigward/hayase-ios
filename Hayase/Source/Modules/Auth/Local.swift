//
//  Local.swift
//  Hayase
//
//  Local offline-first media tracking provider.
//  Mirrors: src/lib/modules/auth/local.ts
//
//  Provides offline-first local media tracking using persistent storage.
//  Manages a local watchlist with favourite, progress, and status
//  tracking. Derives continueIDs and planningIDs from local entries,
//  matching the interface's LocalSync class in auth/local.ts.
//

import Foundation
