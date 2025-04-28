// UUID+Incrementing.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-04-05 06:52 GMT.

import Foundation
import Testing

actor SequentialUUIDGenerator {
    @TaskLocal static var current: SequentialUUIDGenerator = .init()

    private var uuid: Int = 0

    var incrementing: UUID {
        defer { uuid += 1 }
        return UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", uuid))")!
    }

    func reset() {
        uuid = 0
    }
}

public struct SequentialUUIDGenerationTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(for _: Test, testCase _: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        let current = SequentialUUIDGenerator()
        try await SequentialUUIDGenerator.$current.withValue(current) {
            try await function()
        }
    }
}

public extension Trait where Self == SequentialUUIDGenerationTrait {
    static func sequentialUUIDGeneration() -> Self { Self() }
}

public extension UUID {
    /// Returns a UUID that increments with each call.
    ///
    /// The UUID is generated with a fixed prefix "00000000-0000-0000-0000-" and a suffix
    /// that increments by 1 with each call. The suffix is formatted as a 12-digit hexadecimal number.
    ///
    /// - Returns: An incrementing UUID.
    static func incrementing() async throws -> UUID {
        await SequentialUUIDGenerator.current.incrementing
    }

    /// Resets the incrementing UUID counter to 0.
    ///
    /// This function sets the static `uuid` variable back to 0, effectively resetting the
    /// incrementing UUID sequence.
    static func reset() async {
        await SequentialUUIDGenerator.current.reset()
    }
}
