//
//  KitsuAuth.swift
//  Hayase
//
//  Kitsu email/password authentication.
//  Mirrors: src/lib/modules/auth/kitsu.ts (`login`); the rest is in KitsuSync.
//

import Foundation

enum KitsuAuth {
    static func login(email: String, password: String, completion: @escaping (Bool) -> Void) {
        Task {
            let signedIn = await KitsuSync.shared.login(username: email, password: password)
            await MainActor.run { completion(signedIn) }
        }
    }
}
