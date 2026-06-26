//
//  CoreDataService.swift
//
//  Created by Charles Augustine.
//  Copyright (c) 2015 Charles Augustine. All rights reserved.
//


import CoreData
import Foundation


public typealias SaveCompletionHandler = () -> Void


public class CoreDataService {
public func saveRootContext(completionHandler: @escaping SaveCompletionHandler) {
self.rootContext.perform {
do {
try self.rootContext.save()
DispatchQueue.main.async {
completionHandler()
}
} catch let error {
print("Failed to save root context: \(error as NSError)")
DispatchQueue.main.async {
completionHandler()
}
}
}
}

// MARK: Initialization
private init() {
let bundle = Bundle.main

guard let modelURL = bundle.url(forResource: CoreDataService.modelName, withExtension: "momd") else {
fatalError("Could not find model file with name \"\(CoreDataService.modelName)\", please set CoreDataService.modelName to the name of the model file (without the file extension)")
}

guard let someManagedObjectModel = NSManagedObjectModel(contentsOf: modelURL) else {
fatalError("Could not load model at URL \(modelURL)")
}

guard let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
fatalError("Could not find documents directory")
}

managedObjectModel = someManagedObjectModel
persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)

let storeRootURL = documentsDirectoryURL.appendingPathComponent("DataStore")

if !FileManager.default.fileExists(atPath: storeRootURL.path) {
do {
try FileManager.default.createDirectory(at: storeRootURL, withIntermediateDirectories: true, attributes: nil)
} catch let error {
fatalError("Error creating data store directory \(error as NSError)")
}
}

let persistentStoreURL = storeRootURL.appendingPathComponent("\(CoreDataService.storeName).sqlite")
let persistentStoreOptions: [String: Any] = [
NSMigratePersistentStoresAutomaticallyOption: true,
NSInferMappingModelAutomaticallyOption: true
]

do {
try persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: persistentStoreURL, options: persistentStoreOptions)
} catch let error {
print("CoreDataService: failed to open persistent store, resetting local store: \(error as NSError)")
Self.moveAsidePersistentStoreFiles(at: persistentStoreURL)
do {
try persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: persistentStoreURL, options: persistentStoreOptions)
} catch let retryError {
fatalError("Error creating persistent store after reset \(retryError as NSError)")
}
}

rootContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
rootContext.persistentStoreCoordinator = persistentStoreCoordinator
rootContext.undoManager = nil

mainQueueContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
mainQueueContext.parent = rootContext
mainQueueContext.undoManager = nil
}

private static func moveAsidePersistentStoreFiles(at storeURL: URL) {
let fileManager = FileManager.default
let timestamp = Int(Date().timeIntervalSince1970)
let urls = [
storeURL,
URL(fileURLWithPath: storeURL.path + "-wal"),
URL(fileURLWithPath: storeURL.path + "-shm")
]
for url in urls where fileManager.fileExists(atPath: url.path) {
let backupURL = url.deletingLastPathComponent()
.appendingPathComponent("\(url.lastPathComponent).corrupt.\(timestamp)")
do {
try fileManager.moveItem(at: url, to: backupURL)
} catch {
try? fileManager.removeItem(at: url)
}
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
public static var storeName = "Model"
public static let sharedCoreDataService = CoreDataService()
}
