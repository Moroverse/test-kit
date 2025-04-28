// Test+TrackMemoryLeaks.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2024-08-09 12:46 GMT.

import Foundation
import Testing

actor TearDownBlocks {
    @TaskLocal static var current: TearDownBlocks?
    private var teardownOperations: [@Sendable () -> Void] = []

    func addTeardownOperation(_ operation: @Sendable @escaping () -> Void) {
        teardownOperations.append(operation)
    }

    func runTeardownOperations() {
        teardownOperations.forEach { $0() }
        teardownOperations.removeAll()
    }
}

public struct TeardownTrackingTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(for _: Test, testCase _: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        let tracker = TearDownBlocks()
        try await TearDownBlocks.$current.withValue(tracker) {
            try await function()
        }
        await MainActor.run {
            RunLoop.current.run(until: .now)
        }
        await tracker.runTeardownOperations()
    }
}

public extension Trait where Self == TeardownTrackingTrait {
    static func teardownTracking() -> Self {
        .init()
    }
}

public extension Test {
    static func trackForMemoryLeaks(_ instance: AnyObject, isKnowIssue: Bool = false, sourceLocation: SourceLocation = #_sourceLocation) async {
        let weakInstance = WeakRef(instance)
        guard let current = TearDownBlocks.current else {
            func issue() {
                Issue.record(
                    """
                    No associated tear down tracker for current test.
                    Use `.teardownTracking()` trait to track for memory leaks.
                    """,
                    sourceLocation: sourceLocation
                )
            }
            if isKnowIssue {
                withKnownIssue {
                    issue()
                }
            } else {
                issue()
            }
            return
        }
        await current.addTeardownOperation {
            func expect() {
                #expect(weakInstance.value == nil, "Instance should have been deallocated. Potential memory leak.", sourceLocation: sourceLocation)
            }
            if isKnowIssue {
                withKnownIssue {
                    expect()
                }
            } else {
                expect()
            }
        }
    }
}

private class WeakRef<T: AnyObject>: @unchecked Sendable {
    private(set) weak var value: T?
    init(_ value: T) { self.value = value }
}
