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

let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
?? FileManager.default.temporaryDirectory

managedObjectModel = someManagedObjectModel
persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)

let preferredStoreRootURL = documentsDirectoryURL.appendingPathComponent("DataStore")
let storeRootURL: URL
if Self.createDirectoryIfNeeded(at: preferredStoreRootURL) {
storeRootURL = preferredStoreRootURL
} else {
let fallbackRootURL = FileManager.default.temporaryDirectory.appendingPathComponent("HayaseDataStore")
_ = Self.createDirectoryIfNeeded(at: fallbackRootURL)
storeRootURL = fallbackRootURL
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
print("CoreDataService: failed to recreate persistent store, using in-memory fallback: \(retryError as NSError)")
do {
try persistentStoreCoordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
} catch let memoryError {
fatalError("Error creating persistent store fallback \(memoryError as NSError)")
}
}
}

rootContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
rootContext.persistentStoreCoordinator = persistentStoreCoordinator
rootContext.undoManager = nil

mainQueueContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
mainQueueContext.parent = rootContext
mainQueueContext.undoManager = nil
}


private static func createDirectoryIfNeeded(at url: URL) -> Bool {
let fileManager = FileManager.default
if fileManager.fileExists(atPath: url.path) { return true }
do {
try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
return true
} catch {
print("CoreDataService: failed to create data store directory at \(url.path): \(error as NSError)")
return false
}
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
