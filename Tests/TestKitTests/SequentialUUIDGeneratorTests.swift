// SequentialUUIDGeneratorTests.swift
// Copyright (c) 2026 Moroverse
// Created by Daniel Moro on 2025-04-05 06:52 GMT.

import Foundation
import Testing

@Suite("SequentialUUIDGeneration Tests")
struct SequentialUUIDGenerationTests {
    @Test("UUID incrementing produces sequential UUIDs", .sequentialUUIDGeneration())
    func uuidIncrementing() async throws {
        // Reset the counter before test
        await UUID.reset()

        // Get the first UUID
        let uuid1 = try await UUID.incrementing()
        #expect(uuid1.uuidString == "00000000-0000-0000-0000-000000000000")

        // Get the next UUID
        let uuid2 = try await UUID.incrementing()
        #expect(uuid2.uuidString == "00000000-0000-0000-0000-000000000001")

        // Get one more UUID
        let uuid3 = try await UUID.incrementing()
        #expect(uuid3.uuidString == "00000000-0000-0000-0000-000000000002")
    }

    @Test("UUID reset resets the counter to zero", .sequentialUUIDGeneration())
    func uuidReset() async throws {
        // Reset the counter initially
        await UUID.reset()

        // Get a few UUIDs
        _ = try await UUID.incrementing()
        _ = try await UUID.incrementing()
        let uuid3 = try await UUID.incrementing()
        #expect(uuid3.uuidString == "00000000-0000-0000-0000-000000000002")

        // Reset the counter
        await UUID.reset()

        // Get a new UUID, should be back to the first one
        let uuidAfterReset = try await UUID.incrementing()
        #expect(uuidAfterReset.uuidString == "00000000-0000-0000-0000-000000000000")
    }

    @Test("UUID incrementing works with larger numbers", .sequentialUUIDGeneration())
    func uuidIncrementingWithLargerNumbers() async throws {
        await UUID.reset()

        // Skip ahead to test formatting of larger numbers
        for _ in 0 ..< 16 {
            _ = try await UUID.incrementing()
        }

        let uuid = try await UUID.incrementing()
        #expect(uuid.uuidString == "00000000-0000-0000-0000-000000000010")
    }
}
