//
//  CoreDataService.swift
//
//  Created by Charles Augustine.
//  Copyright (c) 2015 Charles Augustine. All rights reserved.
//


import CoreData
import Foundation


/// The graph of `Torrents`, `Animes` and `Videos` that the player is built from is the session of the app, what the
/// interface keeps in `server.last` and `server.active`: the backend is where the files of a torrent are, and a session
/// is made again from the saved state of the player (`MiniPlayerManager`) when the app is opened. So it lives in memory
/// and starts empty on every launch; nothing is written to disk.
public class CoreDataService {

// MARK: Initialization
private init() {
let bundle = Bundle.main

guard let modelURL = bundle.url(forResource: CoreDataService.modelName, withExtension: "momd") else {
fatalError("Could not find model file with name \"\(CoreDataService.modelName)\", please set CoreDataService.modelName to the name of the model file (without the file extension)")
}

guard let someManagedObjectModel = NSManagedObjectModel(contentsOf: modelURL) else {
fatalError("Could not load model at URL \(modelURL)")
}

managedObjectModel = someManagedObjectModel
persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
do {
try persistentStoreCoordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
} catch let error {
fatalError("Error creating the in-memory store \(error as NSError)")
}
Self.removeLegacyStore()

rootContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
rootContext.persistentStoreCoordinator = persistentStoreCoordinator
rootContext.undoManager = nil

mainQueueContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
mainQueueContext.parent = rootContext
mainQueueContext.undoManager = nil
}

/// The sessions that earlier versions wrote to disk
private static func removeLegacyStore() {
let fileManager = FileManager.default
let folders = [
fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("DataStore"),
fileManager.temporaryDirectory.appendingPathComponent("HayaseDataStore"),
]
for folder in folders.compactMap({ $0 }) where fileManager.fileExists(atPath: folder.path) {
try? fileManager.removeItem(at: folder)
}
}

// MARK: Properties
public let mainQueueContext: NSManagedObjectContext

// MARK: Properties (Private)
private let managedObjectModel: NSManagedObjectModel
private let persistentStoreCoordinator: NSPersistentStoreCoordinator
private let rootContext: NSManagedObjectContext

// MARK: Properties (Static)
public static var modelName = "Model"
public static let sharedCoreDataService = CoreDataService()
}
