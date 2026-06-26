//
//  NSManagedObjectContext_Clear.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/9/16.
//

import Foundation
import CoreData

extension NSManagedObjectContext {
    func deleteAllData() {
        guard let persistentStore = persistentStoreCoordinator?.persistentStores.last else { return }
        guard let url = persistentStoreCoordinator?.url(for: persistentStore) else { return }

        performAndWait {
            self.reset()
            do {
                try self.persistentStoreCoordinator?.remove(persistentStore)
                try FileManager.default.removeItem(at: url)
                try self.persistentStoreCoordinator?.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
            } catch {
                print("Error clearing core data.")
            }
        }
    }

    func deleteAllData(_ request: NSFetchRequest<NSFetchRequestResult>) {
        do {
            let objs = try self.fetch(request).compactMap { $0 as? NSManagedObject }
            for obj in objs {
                self.delete(obj)
            }
        } catch {
            print("Error batch deleting request")
        }
    }
}
