// Test+Persistance.swift
// Copyright (c) 2026 Moroverse
// Created by Daniel Moro on 2025-05-31 08:52 GMT.

@preconcurrency import CoreData
import Testing

public actor PersistenceTestContainerManager {
    public let container: NSPersistentContainer

    @TaskLocal public static var current: PersistenceTestContainerManager?

    public init(with model: NSManagedObjectModel) {
        let storeURL = URL(fileURLWithPath: "/dev/null")
        let container = NSPersistentContainer(name: "TestContainer", managedObjectModel: model)
        let descriptor = NSPersistentStoreDescription(url: storeURL)
        descriptor.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        self.container = container
    }
}

@MainActor
public extension NSManagedObjectContext {
    enum Error: Swift.Error {
        case missingContainer
    }

    @TaskLocal static var test: NSManagedObjectContext = .init(concurrencyType: .mainQueueConcurrencyType)

    static func withTestContext(_ body: @MainActor (_ context: NSManagedObjectContext) async throws -> Void) async throws {
        guard let manager = PersistenceTestContainerManager.current else {
            throw Error.missingContainer
        }

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = manager.container.viewContext

        try await body(context)

        manager.container.viewContext.reset()
    }

    static func withTestContext(_ body: @MainActor (_ context: NSManagedObjectContext) throws -> Void) throws {
        guard let manager = PersistenceTestContainerManager.current else {
            throw Error.missingContainer
        }

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = manager.container.viewContext

        try body(context)

        manager.container.viewContext.reset()
    }
}

public struct PersistenceTestContainerTrait: SuiteTrait, TestScoping {
    let model: NSManagedObjectModel

    public init(model: NSManagedObjectModel) {
        self.model = model
    }

    public func provideScope(for _: Test, testCase _: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        let manager = PersistenceTestContainerManager(with: model)

        try await PersistenceTestContainerManager.$current.withValue(manager) {
            try await function()
        }
    }
}

public extension Trait where Self == PersistenceTestContainerTrait {
    static func persistenceTestContainer(for model: NSManagedObjectModel) -> Self {
        Self(model: model)
    }
}

public struct TestContextTrait: TestTrait, TestScoping {
    enum Error: Swift.Error {
        case missingContainer
    }

    public func provideScope(for _: Test, testCase _: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        guard let manager = PersistenceTestContainerManager.current else {
            throw Error.missingContainer
        }
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = manager.container.viewContext

        try await NSManagedObjectContext.$test.withValue(context) {
            try await function()
        }

        manager.container.viewContext.reset()
    }
}

public extension Trait where Self == TestContextTrait {
    static func testContext() -> Self {
        Self()
    }
}
