//
//  Animes+CoreDataProperties.swift
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

extension Animes {

    @NSManaged var animeAnilistId: NSNumber?
    @NSManaged var animeDescription: String?
    @NSManaged var animeImgL: String?
    @NSManaged var animeImgM: String?
    @NSManaged var animeImgS: String?
    @NSManaged var animeScore: NSNumber?
    @NSManaged var animeStatus: String?
    @NSManaged var animeTitleEnglish: String?
    @NSManaged var animeTitleJapanese: String?
    @NSManaged var animeTotalEps: NSNumber?
    @NSManaged var torrents: NSSet?

}
