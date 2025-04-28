// AsyncSpyTests.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-04-05 06:52 GMT.

import Foundation
import Testing
import TestKit

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

@MainActor
private class AsyncProcessorClassA {
    let processor: ProtocolA
    let param: String
    let param2: Int
    var object: Object?
    var error: Error?
    var onBeforeProcess: (() -> Void)?
    var onAfterProcess: (() -> Void)?

    init(processor: ProtocolA, param: String, param2: Int) {
        self.processor = processor
        self.param = param
        self.param2 = param2
    }

    func process() async {
        do {
            onBeforeProcess?()
            object = try await processor.method(param: param, param2: param2)
            onAfterProcess?()
        } catch {
            self.error = error
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
    @Test("AsyncSpy records calls in non async method")
    func testAsyncSpyRecordsCalls() async throws {
        let object = Object()
        let spy = AsyncSpy<Object>()
        let processor = ProcessorClassA(processor: spy, param: "P", param2: 3)
        var calls: [String] = []

        try await spy.async(
            yieldCount: 3) {
                calls.append("Called Process")
                processor.process()
            } expectationBeforeCompletion: {
                calls.append("Called On Before")
            } completeWith: {
                calls.append("Called Complete")
                return .success(object)
            } expectationAfterCompletion: {
                calls.append("Called on After with \($0)")
            }
        #expect(calls == ["Called Process", "Called On Before", "Called Complete", "Called on After with ()"])
        #expect(spy.performCallCount == 1)
        #expect(spy.params(at: 0)[0] as? String == "P")
        #expect(spy.params(at: 0)[1] as? Int == 3)
    }

    @Test("AsyncSpy records calls in async method")
    func testAsyncSpyAsyncRecordsCalls() async throws {
        let object = Object()
        let spy = AsyncSpy<Object>()
        let processor = AsyncProcessorClassA(processor: spy, param: "P", param2: 3)
        var calls: [String] = []

        processor.onBeforeProcess = {
            calls.append("Called On Before Process")
        }
        processor.onAfterProcess = {
            calls.append("Called On After Process")
        }

        try await spy.async(
            yieldCount: 3) {
                calls.append("Called Process")
                await processor.process()
            } expectationBeforeCompletion: {
                calls.append("Called On Before Expectation")
            } completeWith: {
                calls.append("Called Complete")
                return .success(object)
            } expectationAfterCompletion: {
                calls.append("Called on After Expectation with \($0)")
            }
        #expect(
            calls == [
                "Called Process",
                "Called On Before Process",
                "Called On Before Expectation",
                "Called Complete",
                "Called On After Process",
                "Called on After Expectation with ()"
            ]
        )
        #expect(spy.performCallCount == 1)
        #expect(spy.params(at: 0)[0] as? String == "P")
        #expect(spy.params(at: 0)[1] as? Int == 3)
    }
}
