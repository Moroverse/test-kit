// AsyncSpyTests.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-04-05 05:07 GMT.

import Foundation
import SharedTesting
import Testing

private struct Object {}
@MainActor
private protocol ProtocolA {
    func method(param: String, param2: Int) async throws -> Object
}

@MainActor
private class ProcessorClassA {
    let processor: ProtocolA
    let param: String
    let param2: Int
    var object: Object?

    init(processor: ProtocolA, param: String, param2: Int) {
        self.processor = processor
        self.param = param
        self.param2 = param2
    }

    func process() {
        Task {
            object = try await processor.method(param: param, param2: param2)
        }
    }
}

extension AsyncSpy: ProtocolA where Result == Object {
    func method(param: String, param2: Int) async throws -> Object {
        try await perform(param, param2)
    }
}

@Suite("AsyncSpy Tests")
@MainActor
struct AsyncSpyTests {
    @Test("AsyncSpy records calls")
    func testAsyncSpyRecordsCalls() async throws {
        let object = Object()
        let spy = AsyncSpy<Object>()
        let processor = ProcessorClassA(processor: spy, param: "P", param2: 3)
        var isCalledBeforeCompletion = false
        var isCalledAfterCompletion = false
        var isCalledProcess = false

        try await spy.async(
            yieldCount: 3) {
                isCalledProcess = true
                processor.process()
            } expectationBeforeCompletion: {
                isCalledBeforeCompletion = true
            } completeWith: {
                .success(object)
            } expectationAfterCompletion: { _ in
                isCalledAfterCompletion = true
            }

        #expect(isCalledProcess == true)
        #expect(isCalledBeforeCompletion == true)
        #expect(isCalledAfterCompletion == true)
        #expect(spy.performCallCount == 1)
        #expect(spy.params(at: 0)[0] as? String == "P")
        #expect(spy.params(at: 0)[1] as? Int == 3)
    }
}
