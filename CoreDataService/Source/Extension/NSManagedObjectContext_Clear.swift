//
//  NSManagedObjectContext_Clear.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/9/16.
//

import Foundation
import CoreData

extension NSManagedObjectContext {
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
