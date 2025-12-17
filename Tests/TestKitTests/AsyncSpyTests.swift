// AsyncSpyTests.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-04-05 06:52 GMT.

import Foundation
import Testing
import TestKit

private struct Object: Sendable {}
@MainActor
private protocol ProtocolA {
    func method(param: String, param2: Int) async throws -> Object
    func method2(param: Object) async throws
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

extension AsyncSpy: ProtocolA {
    fileprivate func method2(param: Object) async throws {
        try await perform(param)
    }

    fileprivate func method(param: String, param2: Int) async throws -> Object {
        try await perform(param, param2, tag: "method")
    }
}

@Suite("AsyncSpy Tests")
@MainActor
struct AsyncSpyTests {
    @Test("AsyncSpy records calls in non async method")
    func asyncSpyRecordsCalls() async throws {
        let object = Object()
        let spy = AsyncSpy()
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
        #expect(spy.callCount == 1)
        let (params, tag) = spy.params(at: 0)
        #expect(params[0] as? String == "P")
        #expect(params[1] as? Int == 3)
        #expect(tag == "method")
    }

    @Test("AsyncSpy records calls in async method")
    func asyncSpyAsyncRecordsCalls() async throws {
        let object = Object()
        let spy = AsyncSpy()
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
        #expect(spy.callCount == 1)
        let (params, tag) = spy.params(at: 0)
        #expect(params[0] as? String == "P")
        #expect(params[1] as? Int == 3)
        #expect(tag == "method")
    }
}
