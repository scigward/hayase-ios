//
//  NSEntityDescription_Service.swift
//
//  Created by Charles Augustine.
//  Copyright (c) 2015 Charles Augustine. All rights reserved.
//


import CoreData
import Foundation


public extension NSEntityDescription {
	class func insertNewObjectForNamedEntity<T: NSManagedObject>(_ namedEntity: T.Type, inManagedObjectContext context: NSManagedObjectContext) -> T where T: NamedEntity {
		return self.insertNewObject(forEntityName: T.entityName, into: context) as! T
	}
}