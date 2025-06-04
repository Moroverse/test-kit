// PersistenceTestContainerTest.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-05-31 08:52 GMT.

@preconcurrency import CoreData
import Testing

enum Modelmanager {
    static let model: NSManagedObjectModel = {
        let model = NSManagedObjectModel()
        let entityDescription = NSEntityDescription()
        entityDescription.name = "TestObjectA"
        entityDescription.managedObjectClassName = "TestObjectA"

        let nameAttribute = NSAttributeDescription()
        nameAttribute.name = "name"
        nameAttribute.attributeType = .stringAttributeType
        nameAttribute.isOptional = true
        entityDescription.properties.append(nameAttribute)

        let idAttribute = NSAttributeDescription()
        idAttribute.name = "id"
        idAttribute.attributeType = .UUIDAttributeType
        idAttribute.isOptional = false
        entityDescription.properties.append(idAttribute)

        model.entities.append(entityDescription)

        return model
    }()
}

@objc(TestObjectA)
class TestObjectA: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String?
}

@Suite("When persistenceTestContainer is not declared in scope")
struct MissingPersistenceTestContainerTest {
    @Test(
        "Correct context does not exists"
    )
    func contextDoesNotExists() async throws {
        let context = NSManagedObjectContext.test
        #expect(context.parent == nil, "Context should not have parent context")
        #expect(context.concurrencyType == .mainQueueConcurrencyType, "Context should be main queue concurrency type")
        #expect(context.persistentStoreCoordinator == nil, "Context should not have persistent store coordinator")
    }

    @Test(
        "WithTestContext throws"
    )
    func withTestContextThrows() async throws {
        await #expect(throws: Error.self, performing: {
            try await NSManagedObjectContext.withTestContext { _ in
            }
        })
    }
}

@Suite(
    "When persistenceTestContainer is declared in scope for specific model",
    .persistenceTestContainer(for: Modelmanager.model),
    .serialized
)
struct PersistenceTestContainerTest {
    @Test(
        "In withTestContext context exists and can create objects"
    )
    func withContext() async throws {
        try await NSManagedObjectContext.withTestContext { context in
            #expect(context.parent != nil, "Context should have parent context")
            #expect(context.concurrencyType == .privateQueueConcurrencyType, "Context should be private queue concurrency type")
            #expect(context.persistentStoreCoordinator != nil, "Context should have persistent store coordinator")

            #expect(context.registeredObjects.isEmpty == true, "Context should be empty at the start")

            let objectA = TestObjectA(context: context)
            objectA.id = UUID()
            objectA.name = "Test Object"

            #expect(context.registeredObjects.isEmpty == false, "Context should have registered objects")
            #expect(context.registeredObjects.count == 1, "Context should have exactly one registered object")
        }
    }

    @Test(
        "In withTestContext changes are rolled back between tests"
    )
    func withContextChangesAreRolledBack() async throws {
        try await NSManagedObjectContext.withTestContext { context in
            let uniqueID = UUID()

            let objectA = TestObjectA(context: context)
            objectA.id = uniqueID
            objectA.name = "Temporary Object"

            try context.save()

            let fetchRequest = NSFetchRequest<TestObjectA>(entityName: "TestObjectA")
            fetchRequest.predicate = NSPredicate(format: "id == %@", argumentArray: [uniqueID])
            var results = try context.fetch(fetchRequest)

            #expect(results.count == 1, "Should find objects from this test")

            // Try to fetch any previously created objects with different IDs
            // This should return empty if context is properly reset between tests
            fetchRequest.predicate = NSPredicate(format: "id != %@", argumentArray: [uniqueID])
            results = try context.fetch(fetchRequest)

            #expect(results.isEmpty, "Should not find objects from previous tests")
        }
    }

    @Test(
        "Test Context exists and can create objects",
        .testContext()
    )
    func contextExists() async throws {
        let context = NSManagedObjectContext.test
        #expect(context.parent != nil, "Context should have parent context")
        #expect(context.concurrencyType == .privateQueueConcurrencyType, "Context should be private queue concurrency type")
        #expect(context.persistentStoreCoordinator != nil, "Context should have persistent store coordinator")

        #expect(context.registeredObjects.isEmpty == true, "Context should be empty at the start")

        let objectA = TestObjectA(context: context)
        objectA.id = UUID()
        objectA.name = "Test Object"

        #expect(context.registeredObjects.isEmpty == false, "Context should have registered objects")
        #expect(context.registeredObjects.count == 1, "Context should have exactly one registered object")
    }

    @Test(
        "Changes are rolled back between tests",
        .testContext()
    )
    func changesAreRolledBack() async throws {
        let context = NSManagedObjectContext.test
        let uniqueID = UUID()

        let objectA = TestObjectA(context: context)
        objectA.id = uniqueID
        objectA.name = "Temporary Object"

        try context.save()

        let fetchRequest = NSFetchRequest<TestObjectA>(entityName: "TestObjectA")
        fetchRequest.predicate = NSPredicate(format: "id == %@", argumentArray: [uniqueID])
        var results = try context.fetch(fetchRequest)

        #expect(results.count == 1, "Should find objects from this test")

        // Try to fetch any previously created objects with different IDs
        // This should return empty if context is properly reset between tests
        fetchRequest.predicate = NSPredicate(format: "id != %@", argumentArray: [uniqueID])
        results = try context.fetch(fetchRequest)

        #expect(results.isEmpty, "Should not find objects from previous tests")
    }
}
