//
//  Torrents+CoreDataProperties.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/17/16.
//
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Torrents {

    @NSManaged var torrentLeechers: NSNumber?
    @NSManaged var torrentName: String?
    @NSManaged var torrentSeeders: NSNumber?
    @NSManaged var torrentSize: NSNumber?
    @NSManaged var torrentHashString: String?
    @NSManaged var torrentDownloadURL: String?
    @NSManaged var animes: Animes?
    @NSManaged var videos: NSSet?

}
