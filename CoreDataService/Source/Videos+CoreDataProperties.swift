//
//  Videos+CoreDataProperties.swift
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

extension Videos {

    @NSManaged var videoName: String?
    @NSManaged var videoPath: String?
    /// LAN-reachable stream URL (torrent-client's `file.lan`, same path as
    /// `videoPath` but addressed to this device's Wi-Fi IP instead of
    /// localhost). `videoPath` stays loopback-only for local MPV playback;
    /// this is what a Chromecast/DLNA display fetches the stream from.
    @NSManaged var videoLanPath: String?
    @NSManaged var videoDownloadPercent: NSNumber?
    @NSManaged var videoIndex: NSNumber?
    @NSManaged var videoSize: NSNumber?
    @NSManaged var torrents: Torrents?

}
