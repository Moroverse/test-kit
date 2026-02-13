// AsyncSpyTests.swift
// Copyright (c) 2026 Moroverse
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
    var isLoading: Bool = false
    var onBeforeProcess: (() -> Void)?
    var onAfterProcess: (() -> Void)?

    init(processor: ProtocolA, param: String, param2: Int) {
        self.processor = processor
        self.param = param
        self.param2 = param2
    }

    func process() async {
        isLoading = true
        do {
            onBeforeProcess?()
            object = try await processor.method(param: param, param2: param2)
            onAfterProcess?()
        } catch {
            self.error = error
        }
        isLoading = false
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

private struct TestError: Error {}

@MainActor
private class CascadingProcessorClassA {
    let processor: ProtocolA
    var deleteCompleted: Bool = false
    var reloadedObject: Object?
    var error: Error?

    init(processor: ProtocolA) {
        self.processor = processor
    }

    func deleteAndReload(object: Object) async {
        do {
            try await processor.method2(param: object)
            deleteCompleted = true
            reloadedObject = try await processor.method(param: "reload", param2: 0)
        } catch {
            self.error = error
        }
    }
}

@Suite("AsyncSpy Tests")
@MainActor
struct AsyncSpyTests {
    @Test("Scenario records calls in async method")
    func scenarioRecordsCallsInAsyncMethod() async throws {
        let object = Object()
        let spy = AsyncSpy()
        let processor = AsyncProcessorClassA(processor: spy, param: "P", param2: 3)

        try await spy.scenario { step in
            await step.trigger { await processor.process() }
            await step.complete(with: object)
        }

        #expect(spy.callCount == 1)
        let (params, tag) = spy.params(at: 0)
        #expect(params[0] as? String == "P")
        #expect(params[1] as? Int == 3)
        #expect(tag == "method")
        #expect(processor.object != nil)
    }

    @Test("Scenario records calls in sync method")
    func scenarioRecordsCallsInSyncMethod() async throws {
        let object = Object()
        let spy = AsyncSpy()
        let processor = ProcessorClassA(processor: spy, param: "P", param2: 3)

        try await spy.scenario(yieldCount: 3) { step in
            await step.trigger(sync: { processor.process() })
            await step.complete(with: object)
        }

        #expect(spy.callCount == 1)
        let (params, tag) = spy.params(at: 0)
        #expect(params[0] as? String == "P")
        #expect(params[1] as? Int == 3)
        #expect(tag == "method")
        #expect(processor.object != nil)
    }

    @Test("Scenario verifies loading state")
    func scenarioVerifiesLoadingState() async throws {
        let object = Object()
        let spy = AsyncSpy()
        let processor = AsyncProcessorClassA(processor: spy, param: "P", param2: 3)

        try await spy.scenario { step in
            await step.trigger { await processor.process() }
            #expect(processor.isLoading)
            await step.complete(with: object)
            #expect(!processor.isLoading)
        }
    }

    @Test("Scenario handles failure")
    func scenarioHandlesFailure() async throws {
        let spy = AsyncSpy()
        let processor = AsyncProcessorClassA(processor: spy, param: "P", param2: 3)

        try await spy.scenario { step in
            await step.trigger { await processor.process() }
            await step.fail(with: TestError())
        }

        #expect(processor.error is TestError)
        #expect(processor.object == nil)
    }

    @Test("Scenario verifies execution order")
    func scenarioVerifiesExecutionOrder() async throws {
        let object = Object()
        let spy = AsyncSpy()
        let processor = AsyncProcessorClassA(processor: spy, param: "P", param2: 3)
        var calls: [String] = []

        processor.onBeforeProcess = { calls.append("onBefore") }
        processor.onAfterProcess = { calls.append("onAfter") }

        try await spy.scenario { step in
            await step.trigger { await processor.process() }
            calls.append("beforeCompletion")
            await step.complete(with: object)
            calls.append("afterCompletion")
        }

        #expect(calls == ["onBefore", "beforeCompletion", "onAfter", "afterCompletion"])
    }

    @Test("Scenario with cascade")
    func scenarioWithCascade() async throws {
        let reloadedObject = Object()
        let spy = AsyncSpy()
        let processor = CascadingProcessorClassA(processor: spy)

        try await spy.scenario { step in
            await step.trigger { await processor.deleteAndReload(object: Object()) }
            await step.complete(with: ())
            await step.cascade(.success(reloadedObject))
        }

        #expect(spy.callCount == 2)
        #expect(processor.deleteCompleted)
        #expect(processor.reloadedObject != nil)
    }

    @Test("Scenario with cascade skip")
    func scenarioWithCascadeSkip() async throws {
        let spy = AsyncSpy()
        let processor = CascadingProcessorClassA(processor: spy)

        try await spy.scenario { step in
            await step.trigger { await processor.deleteAndReload(object: Object()) }
            await step.fail(with: TestError())
            await step.cascade(.skip)
        }

        #expect(spy.callCount == 1)
        #expect(processor.error is TestError)
        #expect(!processor.deleteCompleted)
        #expect(processor.reloadedObject == nil)
    }

    @Test("Scenario with multiple triggers")
    func scenarioWithMultipleTriggers() async throws {
        let object1 = Object()
        let object2 = Object()
        let spy = AsyncSpy()
        let processor1 = AsyncProcessorClassA(processor: spy, param: "A", param2: 1)
        let processor2 = AsyncProcessorClassA(processor: spy, param: "B", param2: 2)

        try await spy.scenario { step in
            await step.trigger { await processor1.process() }
            await step.trigger { await processor2.process() }
            await step.complete(with: object1, at: 0)
            await step.complete(with: object2, at: 1)
        }

        #expect(spy.callCount == 2)
        #expect(spy.params(at: 0).params[0] as? String == "A")
        #expect(spy.params(at: 1).params[0] as? String == "B")
        #expect(processor1.object != nil)
        #expect(processor2.object != nil)
    }

    @Test("Scenario with sequential calls")
    func scenarioWithSequentialCalls() async throws {
        let object1 = Object()
        let object2 = Object()
        let spy = AsyncSpy()
        let processor = AsyncProcessorClassA(processor: spy, param: "P", param2: 3)

        try await spy.scenario { step in
            await step.trigger { await processor.process() }
            await step.complete(with: object1)
        }

        #expect(spy.callCount == 1)
        #expect(processor.object != nil)

        try await spy.scenario { step in
            await step.trigger { await processor.process() }
            await step.complete(with: object2, at: 1)
        }

        #expect(spy.callCount == 2)
    }

    @Test("Scenario sync trigger then async trigger")
    func scenarioSyncTriggerThenAsyncTrigger() async throws {
        let object1 = Object()
        let object2 = Object()
        let spy = AsyncSpy()
        let syncProcessor = ProcessorClassA(processor: spy, param: "S", param2: 1)
        let asyncProcessor = AsyncProcessorClassA(processor: spy, param: "A", param2: 2)

        try await spy.scenario(yieldCount: 3) { step in
            await step.trigger(sync: { syncProcessor.process() })
            await step.complete(with: object1, at: 0)
            await step.trigger { await asyncProcessor.process() }
            await step.complete(with: object2, at: 1)
        }

        #expect(spy.callCount == 2)
        #expect(spy.params(at: 0).params[0] as? String == "S")
        #expect(spy.params(at: 1).params[0] as? String == "A")
    }
}
