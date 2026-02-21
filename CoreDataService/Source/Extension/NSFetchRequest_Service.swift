//
//  NSFetchRequest_Service.swift
//
//  Created by Charles Augustine.
//  Copyright (c) 2015 Charles Augustine. All rights reserved.
//


import CoreData
import Foundation


public extension NSFetchRequest where ResultType == NSFetchRequestResult {
	convenience init<T: NSManagedObject & NamedEntity>(namedEntity: T.Type) {
		self.init(entityName: T.entityName)
	}
}