// TeardownTrackingTests.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-04-03 09:14 GMT.

import Foundation
import SharedTesting
import Testing

class ClassA {
    var b: ClassB?
    init() {}
}

class ClassB {
    private let a: ClassA
    init(a: ClassA) {
        self.a = a
    }
}

@Suite("TeardownTracking Tests")
struct TeardownTrackingTests {
    @Test("Expect no leaks", .teardownTracking())
    func noLeaks() async throws {
        let a = ClassA()
        let b = ClassB(a: a)
        await Test.trackForMemoryLeaks(a)
        await Test.trackForMemoryLeaks(b)
    }

    @Test("Expect issue")
    func noTrackingTraitSet() async throws {
        let a = ClassA()
        let b = ClassB(a: a)
        await Test.trackForMemoryLeaks(a, isKnowIssue: true)
        await Test.trackForMemoryLeaks(b, isKnowIssue: true)
    }

    @Test("Expect leaks", .teardownTracking())
    func leaks() async throws {
        let a = ClassA()
        let b = ClassB(a: a)
        a.b = b
        await Test.trackForMemoryLeaks(a, isKnowIssue: true)
        await Test.trackForMemoryLeaks(b, isKnowIssue: true)
    }
}
