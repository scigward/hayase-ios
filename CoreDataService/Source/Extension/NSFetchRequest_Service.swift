//
//  NSFetchRequest_Service.swift
//
//  Created by Charles Augustine.
//  Copyright (c) 2015 Charles Augustine. All rights reserved.
//


import CoreData
import Foundation


/// Returns a typed NSFetchRequest for the given NamedEntity subclass.
public func makeFetchRequest<T: NSManagedObject & NamedEntity>(for entityType: T.Type) -> NSFetchRequest<T> {
	return NSFetchRequest<T>(entityName: T.entityName)
}