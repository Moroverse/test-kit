// AsyncSpy.swift
// Copyright (c) 2026 Moroverse
// Created by Daniel Moro on 2025-04-05 06:52 GMT.

import ConcurrencyExtras
#if canImport(Testing)
    import Testing
#endif

// A class for spying on asynchronous operations in Swift.
//
// `AsyncSpy` allows you to track and control the execution of asynchronous operations,
// making it useful for testing scenarios where you need to simulate or verify
// asynchronous behavior.
//
// - Note: This class is designed to be used in a testing environment.
// - Note: Conditionally compatible with both Swift Testing and XCTest frameworks.
//   Uses `SourceLocation` with Swift Testing, falls back to `StaticString file, UInt line` otherwise.
//
// # AsyncSpy Usage Guide
//
// AsyncSpy is a powerful tool for testing asynchronous code in Swift. Here's how to use it effectively:
//
// ## Setup
//
// 1. Given protocol for the asynchronous operation you want to test:
//
//    ```swift
//    protocol FetchUserProtocol {
//        func fetch(by id: Int) async throws -> User
//    }
//    ```
//
// 2. Implement AsyncSpy conformance to your protocol:
//
//    ```swift
//    extension AsyncSpy: FetchUserProtocol where Result == User {
//        func fetch(by id: Int) async throws -> User {
//            try await perform(id)
//        }
//    }
//    ```
// 2a. Implement AsyncSpy conformance to protocol with arbitrary number of arguments:
//
//    ```swift
//    extension AsyncSpy: UpdateUserProtocol where Result == Void {
//        func update(user: User, sessionID: UUID, time: Date) async throws -> Void {
//            try await perform(user, sessionID, time)
//        }
//    }
//    ```
//
// 3. In your test class, create a method to set up the system under test (SUT):
//
//    ```swift
//    final class ExampleTests: XCTestCase {
//        @MainActor
//        private func makeSUT() -> (sut: FetchUserViewModel, spy: AsyncSpy<User>) {
//            let spy = AsyncSpy<User>()
//            let sut = FetchUserViewModel(fetchUser: spy)
//            return (sut, spy)
//        }
//    }
//    ```
//
// ## Writing Tests
//
// ### Testing Successful Operations
//
// Use the `async` method to control the flow of asynchronous operations:
//
// ```swift
// @MainActor
// func testLoadSuccess() async throws {
//     let (sut, spy) = makeSUT()
//     try await spy.async {
//         await sut.fetchUser(by: 1)
//     } completeWith: {
//         .success(User(id: 1, name: "Alice"))
//     } expectationAfterCompletion: { _ in
//         XCTAssertEqual(spy.loadCallCount, 1)
//         XCTAssertEqual(spy.params(at: 0)[0] as? Int, 1)
//         XCTAssertEqual(sut.user?.id, 1)
//         XCTAssertEqual(sut.user?.name, "Alice")
//     }
// }
// ```
//
// ### Testing Loading States
//
// Use expectationBeforeCompletion and expectationAfterCompletion to verify state changes:
//
// ```swift
// @MainActor
// func testLoading() async throws {
//     let (sut, spy) = makeSUT()
//     try await spy.async {
//         await sut.fetchUser(by: 1)
//     } expectationBeforeCompletion: {
//         XCTAssertTrue(sut.isLoading)
//     } completeWith: {
//         .failure(NSError(domain: "", code: 0))
//     } expectationAfterCompletion: { _ in
//         XCTAssertFalse(sut.isLoading)
//     }
// }
// ```
//
// ### Controlling Timing with yieldCount
//
// Adjust the `yieldCount` to control when the completion happens:
//
// ```swift
// try await spy.async(yieldCount: 2) {
//     await sut.load()
// } completeWith: {
//     sut.cancel()
//     return .success(anyModel)
// } expectationAfterCompletion: { _ in
//     XCTAssertEqual(sut.state, .empty)
// }
// ```
//
// ### Handling Multiple Async Operations
//
// Use the `at` parameter to specify which completion to invoke:
//
// ```swift
// try await spy.async(at: 1) {
//     await sut.load()
// } completeWith: {
//     .success(model2)
// } expectationAfterCompletion: { _ in
//     XCTAssertEqual(sut.state, .ready(model2))
//     XCTAssertEqual(spy.loadCallCount, 2)
// }
// ```
//
// ## Best Practices
//
// 1. Leverage `expectationBeforeCompletion` and `expectationAfterCompletion` to verify state changes.
// 2. Use `params(at:)` to verify the parameters passed to async operations.
// 3. Adjust `yieldCount` to test different timing scenarios.
// 4. Use the `at` parameter when dealing with multiple async operations in a single test.

@MainActor
public final class AsyncSpy {
    typealias ContinuationType = CheckedContinuation<any Sendable, Error>
    private var messages: [(parameters: [(any Sendable)?], continuation: ContinuationType, tag: String?)] = []

    /// The number of times the `perform` method has been called.
    public var callCount: Int {
        messages.count
    }

    public func callCount(forTag tag: String) -> Int {
        messages.count(where: { $0.tag == tag })
    }

    /// Initializes a new instance of `AsyncSpy`.
    public init() {}

    /// Retrieves the parameters passed to a specific call of `perform`.
    ///
    /// - Parameter index: The index of the call to retrieve parameters for.
    /// - Returns: An array of `Sendable` parameters.
    public func params(at index: Int) -> (params: [(any Sendable)?], tag: String?) {
        let params = messages[index].parameters
        let tag = messages[index].tag
        return (params, tag)
    }

    /// Simulates an asynchronous operation, capturing the parameters and providing a continuation.
    ///
    /// - Parameters:
    ///   - parameters: The parameters passed to the operation.
    /// - Returns: The result of the asynchronous operation.
    /// - Throws: An error if the operation fails.
    @Sendable
    public func perform<Result: Sendable, each Parameter: Sendable>(_ parameters: repeat each Parameter, tag: String? = nil) async throws -> Result {
        var packed: [(any Sendable)?] = []

        func add(element: some Sendable) {
            packed.append(element)
        }

        repeat add(element: each parameters)

        let result = try await withCheckedThrowingContinuation { continuation in
            messages.append((packed, continuation, tag))
        } as? Result

        guard let result else {
            fatalError("Missing result from async call")
        }

        return result
    }

    @Sendable
    public func perform<each Parameter: Sendable>(_ parameters: repeat each Parameter, tag: String? = nil) async throws {
        var packed: [(any Sendable)?] = []

        func add(element: some Sendable) {
            packed.append(element)
        }

        repeat add(element: each parameters)

        _ = try await withCheckedThrowingContinuation {
            continuation in
            messages.append((packed, continuation, tag))
        }
    }

    // Completes a pending operation with an error.
    //
    // - Parameters:
    //   - error: The error to complete the operation with.
    //   - index: The index of the operation to complete (default is 0).
    #if canImport(Testing)
        public func complete(
            with error: Error,
            at index: Int = 0,
            sourceLocation: SourceLocation = #_sourceLocation
        ) {
            guard messages.count > index else {
                Issue.record("Can't complete request never made", sourceLocation: sourceLocation)
                return
            }
            messages[index].continuation.resume(throwing: error)
        }
    #else
        public func complete(
            with error: Error,
            at index: Int = 0,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            guard messages.count > index else {
                assertionFailure("Can't complete request never made", file: file, line: line)
                return
            }
            messages[index].continuation.resume(throwing: error)
        }
    #endif

    // Completes a pending operation with a result.
    //
    // - Parameters:
    //   - result: The result to complete the operation with.
    //   - index: The index of the operation to complete (default is 0).
    #if canImport(Testing)
        public func complete(
            with result: some Sendable,
            at index: Int = 0,
            sourceLocation: SourceLocation = #_sourceLocation
        ) {
            guard messages.count > index else {
                Issue.record("Can't complete request never made", sourceLocation: sourceLocation)
                return
            }
            messages[index].continuation.resume(returning: result)
        }
    #else
        public func complete(
            with result: some Sendable,
            at index: Int = 0,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            guard messages.count > index else {
                assertionFailure("Can't complete request never made", file: file, line: line)
                return
            }
            messages[index].continuation.resume(returning: result)
        }
    #endif
}

// MARK: - Scenario API

@MainActor
public extension AsyncSpy {
    /// A step-by-step orchestrator for structured async test scenarios.
    ///
    /// `ScenarioStep` replaces the multi-closure APIs (`async {}`, `synchronous {}`, `asyncWithCascade {}`)
    /// with an imperative, sequential interface. Instead of passing closures for each phase, you write
    /// steps in natural order with inline assertions between them.
    ///
    /// ## Basic Usage
    ///
    /// ```swift
    /// try await spy.scenario { step in
    ///     step.trigger { await sut.load() }
    ///     #expect(sut.isLoading)
    ///     await step.complete(with: data)
    ///     #expect(sut.items == expected)
    /// }
    /// ```
    ///
    /// ## Phases
    ///
    /// A scenario typically flows through these phases:
    /// 1. **Trigger** — Launch the SUT's async (or sync) operation
    /// 2. **Assert pre-completion state** — Verify loading indicators, intermediate state
    /// 3. **Complete** — Resume the spy's continuation with a success or failure
    /// 4. **Assert post-completion state** — Verify final state, call counts, parameters
    /// 5. *(Optional)* **Cascade** — Complete subsequent operations triggered by the first
    @MainActor final class ScenarioStep {
        private let spy: AsyncSpy
        private let yieldCount: Int
        private(set) var tasks: [Task<Void, any Error>] = []
        private var nextCascadeIndex: Int = 0

        #if canImport(Testing)
            private let sourceLocation: SourceLocation

            init(spy: AsyncSpy, yieldCount: Int, sourceLocation: SourceLocation) {
                self.spy = spy
                self.yieldCount = yieldCount
                self.sourceLocation = sourceLocation
            }
        #else
            private let file: StaticString
            private let line: UInt

            init(spy: AsyncSpy, yieldCount: Int, file: StaticString, line: UInt) {
                self.spy = spy
                self.yieldCount = yieldCount
                self.file = file
                self.line = line
            }
        #endif

        /// Launches an async process as a tracked `Task` and yields to let it execute.
        ///
        /// Use this when the SUT method you're testing is `async`. The process is wrapped in a `Task`,
        /// appended to the step's task list, and then the step yields `yieldCount` times to allow
        /// the process to reach the spy's continuation point.
        ///
        /// The returned task can be captured for cancellation or other control:
        /// ```swift
        /// try await spy.scenario { step in
        ///     let task = await step.trigger { await sut.load() }
        ///     task.cancel()
        ///     await step.complete(with: data)
        /// }
        /// ```
        ///
        /// - Parameter process: The async operation to execute (typically calls the SUT).
        /// - Returns: The `Task` wrapping the process, for optional cancellation or inspection.
        @discardableResult
        public func trigger(_ process: @escaping () async throws -> Void) async -> Task<Void, any Error> {
            let task = Task { try await process() }
            tasks.append(task)
            for _ in 0 ..< yieldCount {
                await Task.yield()
            }
            return task
        }

        /// Calls a synchronous process directly and yields to let internally-spawned tasks execute.
        ///
        /// Use this when the SUT method is synchronous but internally spawns a `Task` that calls
        /// the spy. The process is called directly (not wrapped in a Task), then the step yields
        /// `yieldCount` times to allow the internal Task to reach the spy's continuation point.
        ///
        /// ```swift
        /// try await spy.scenario(yieldCount: 3) { step in
        ///     await step.trigger(sync: { sut.process() })
        ///     await step.complete(with: result)
        /// }
        /// ```
        ///
        /// - Parameter process: The synchronous operation to execute.
        public func trigger(sync process: @MainActor () -> Void) async {
            process()
            for _ in 0 ..< yieldCount {
                await Task.yield()
            }
        }

        /// Resumes the spy's continuation at the given index with a success value.
        ///
        /// After completing, yields once to let the resumed task propagate its result,
        /// and updates `nextCascadeIndex` to `index + 1` for subsequent cascade completions.
        ///
        /// ```swift
        /// try await spy.scenario { step in
        ///     step.trigger { await sut.load() }
        ///     await step.complete(with: expectedData)
        ///     #expect(sut.data == expectedData)
        /// }
        /// ```
        ///
        /// For multiple pending calls, specify the index explicitly:
        /// ```swift
        /// await step.complete(with: firstResult, at: 0)
        /// await step.complete(with: secondResult, at: 1)
        /// ```
        ///
        /// - Parameters:
        ///   - result: The value to resume the continuation with.
        ///   - index: The index of the pending operation to complete (default is 0).
        public func complete(with result: some Sendable, at index: Int = 0) async {
            #if canImport(Testing)
                spy.complete(with: result, at: index, sourceLocation: sourceLocation)
            #else
                spy.complete(with: result, at: index, file: file, line: line)
            #endif
            nextCascadeIndex = index + 1
            await Task.yield()
        }

        /// Resumes the spy's continuation at the given index with an error.
        ///
        /// Use this to test error-handling paths. After failing, yields once and updates
        /// `nextCascadeIndex` to `index + 1`.
        ///
        /// ```swift
        /// try await spy.scenario { step in
        ///     step.trigger { await sut.load() }
        ///     await step.fail(with: NetworkError.timeout)
        ///     #expect(sut.error is NetworkError)
        /// }
        /// ```
        ///
        /// - Parameters:
        ///   - error: The error to resume the continuation with.
        ///   - index: The index of the pending operation to complete (default is 0).
        public func fail(with error: Error, at index: Int = 0) async {
            #if canImport(Testing)
                spy.complete(with: error, at: index, sourceLocation: sourceLocation)
            #else
                spy.complete(with: error, at: index, file: file, line: line)
            #endif
            nextCascadeIndex = index + 1
            await Task.yield()
        }

        /// Completes cascading operations that were triggered by the primary completion.
        ///
        /// When completing the primary operation causes the SUT to make additional async calls
        /// (e.g., delete → reload), use `cascade` to complete those subsequent operations.
        /// Each completion is applied at `nextCascadeIndex` (auto-incremented), with a yield
        /// between each to allow the task to progress.
        ///
        /// ```swift
        /// try await spy.scenario { step in
        ///     step.trigger { await sut.deleteAndReload(item) }
        ///     await step.complete(with: ())         // completes delete at index 0
        ///     await step.cascade(.success(newList))  // completes reload at index 1
        ///     #expect(sut.items == newList)
        /// }
        /// ```
        ///
        /// Use `.skip` for error paths where the cascading call doesn't fire:
        /// ```swift
        /// try await spy.scenario { step in
        ///     step.trigger { await sut.deleteAndReload(item) }
        ///     await step.fail(with: DeleteError.denied)
        ///     await step.cascade(.skip)  // reload never happens
        ///     #expect(sut.error is DeleteError)
        /// }
        /// ```
        ///
        /// - Parameter completions: One or more `CascadeCompletion` values to apply in order.
        public func cascade(_ completions: CascadeCompletion...) async {
            for completion in completions {
                completion.apply(to: spy, at: nextCascadeIndex)
                nextCascadeIndex += 1
                await Task.yield()
            }
        }
    }

    /// Executes a structured test scenario with step-by-step phase control.
    ///
    /// `scenario` wraps execution in `withMainSerialExecutor` for deterministic scheduling,
    /// creates a `ScenarioStep` context, and auto-awaits all triggered tasks after the body completes.
    ///
    /// ## Overview
    ///
    /// The scenario API replaces the multi-closure orchestration methods (`async {}`, `synchronous {}`,
    /// `asyncWithCascade {}`) with a single, imperative interface. Write test phases in natural order
    /// with inline assertions between them:
    ///
    /// ```swift
    /// try await spy.scenario(yieldCount: 3) { step in
    ///     step.trigger { await sut.load() }
    ///     #expect(sut.isLoading)
    ///     await step.complete(with: data)
    ///     #expect(sut.items == expected)
    /// }
    /// ```
    ///
    /// ## How `yieldCount` Affects Timing
    ///
    /// The `yieldCount` controls how many times `Task.yield()` is called after each trigger.
    /// Higher values give the triggered task more opportunities to progress before your assertions
    /// run. The default of 1 is sufficient for most cases; increase it when the SUT has multiple
    /// suspension points before reaching the spy.
    ///
    /// ## Deterministic Scheduling
    ///
    /// The entire body runs inside `withMainSerialExecutor`, which forces all `@MainActor` tasks
    /// to execute serially. Combined with `Task.yield()`, this gives you precise control over
    /// execution order.
    ///
    /// - Parameters:
    ///   - yieldCount: Number of times to yield after each trigger (default is 1).
    ///   - body: A closure receiving a ``ScenarioStep`` for orchestrating the test phases.
    ///
    /// ## Auto-Await
    ///
    /// After the body completes, all tasks created via `trigger` are automatically awaited.
    /// Errors from those tasks are intentionally swallowed (since test scenarios often
    /// use `fail(with:)` to trigger error paths).
    ///
    /// - MARK: Migration Guide
    ///
    /// | Old Pattern | New Pattern |
    /// |-------------|-------------|
    /// | `spy.async { await sut.load() } completeWith: { .success(data) } expectationAfterCompletion: { ... }` | `spy.scenario { step in step.trigger { await sut.load() }; await step.complete(with: data); ... }` |
    /// | `spy.synchronous { sut.setFilter(.active) } completeWith: { .success(data) }` | `spy.scenario { step in step.trigger(sync: { sut.setFilter(.active) }); await step.complete(with: data) }` |
    /// | `spy.async { ... } expectationBeforeCompletion: { #expect(sut.isLoading) } completeWith: { ... }` | `spy.scenario { step in step.trigger { ... }; #expect(sut.isLoading); await step.complete(with: ...) }` |
    /// | `spy.asyncWithCascade { ... } completeWith: { .success(()) } cascade: { .init([.success(list)]) }` | `spy.scenario { step in step.trigger { ... }; await step.complete(with: ()); await step.cascade(.success(list)) }` |
    /// | `spy.asyncWithCascade { ... } completeWith: { .failure(err) } cascade: { .init([.skip]) }` | `spy.scenario { step in step.trigger { ... }; await step.fail(with: err); await step.cascade(.skip) }` |
    /// | `spy.async { ... } processAdvance: { task in task.cancel() } completeWith: { ... }` | `spy.scenario { step in let task = step.trigger { ... }; task.cancel(); await step.complete(with: ...) }` |
    /// | `spy.async(at: 1) { await sut.reload() } completeWith: { .success(data) }` | `spy.scenario { step in step.trigger { await sut.reload() }; await step.complete(with: data, at: 1) }` |
    func scenario(
        yieldCount: Int = 1,
        _ body: (ScenarioStep) async throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await withMainSerialExecutor {
            let step = ScenarioStep(spy: self, yieldCount: yieldCount, sourceLocation: sourceLocation)
            try await body(step)
            for task in step.tasks {
                _ = try? await task.value
            }
        }
    }
}

// MARK: - XCTest/Scenario Fallback

#if !canImport(Testing)
    @MainActor
    public extension AsyncSpy {
        func scenario(
            yieldCount: Int = 1,
            _ body: (ScenarioStep) async throws -> Void,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws {
            try await withMainSerialExecutor {
                let step = ScenarioStep(spy: self, yieldCount: yieldCount, file: file, line: line)
                try await body(step)
                for task in step.tasks {
                    _ = try? await task.value
                }
            }
        }
    }
#endif

public extension AsyncSpy {
    #if canImport(Testing)
        private func _async<ActionResult: Sendable, Result: Sendable>(
            yieldCount: Int = 1,
            at index: Int = 0,
            process: @escaping () async throws -> ActionResult,
            processAdvance: ((Task<ActionResult, any Error>) async -> Void)? = nil,
            expectationBeforeCompletion: (() -> Void)? = nil,
            completeWith: (() -> Swift.Result<Result, Error>)? = nil,
            expectationAfterCompletion: ((ActionResult) -> Void)? = nil,
            sourceLocation: SourceLocation = #_sourceLocation
        ) async throws {
            try await withMainSerialExecutor {
                let task = Task { try await process() }
                for _ in 0 ..< yieldCount {
                    await Task.yield()
                }
                await processAdvance?(task)
                expectationBeforeCompletion?()
                switch completeWith?() {
                case let .success(result):
                    complete(
                        with: result,
                        at: index,
                        sourceLocation: sourceLocation
                    )

                case let .failure(error):
                    complete(
                        with: error,
                        at: index,
                        sourceLocation: sourceLocation
                    )

                case .none:
                    break
                }
                let value = try await task.value
                await Task.yield()
                expectationAfterCompletion?(value)
            }
        }
    #else
        private func _async<ActionResult: Sendable, Result: Sendable>(
            yieldCount: Int = 1,
            at index: Int = 0,
            process: @escaping () async throws -> ActionResult,
            processAdvance: (() async -> Void)? = nil,
            expectationBeforeCompletion: (() -> Void)? = nil,
            completeWith: (() -> Swift.Result<Result, Error>)? = nil,
            expectationAfterCompletion: ((ActionResult) -> Void)? = nil,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws {
            try await withMainSerialExecutor {
                let task = Task { try await process() }
                for _ in 0 ..< yieldCount {
                    await Task.yield()
                }
                await processAdvance?()
                expectationBeforeCompletion?()
                switch completeWith?() {
                case let .success(result):
                    complete(
                        with: result,
                        at: index,
                        file: file,
                        line: line
                    )

                case let .failure(error):
                    complete(
                        with: error,
                        at: index,
                        file: file,
                        line: line
                    )

                case .none:
                    break
                }
                let value = try await task.value
                await Task.yield()
                expectationAfterCompletion?(value)
            }
        }
    #endif

    /// Executes an asynchronous process with controlled timing and completion at a specific index.
    ///
    /// - Parameters:
    ///   - yieldCount: The number of times to yield before completing (default is 1).
    ///   - index: The index of the operation to complete (default is 0).
    ///   - process: The asynchronous process to execute.
    ///   - expectationBeforeCompletion: A closure to execute before completing the operation.
    ///   - completeWith: A closure that provides the result or error to complete with.
    ///   - expectationAfterCompletion: A closure to execute after completing the operation.
    /// - Throws: Any error that occurs during the process.
    @available(*, deprecated, message: "Use scenario {} instead")
    func async<ActionResult: Sendable, Result: Sendable>(
        yieldCount: Int = 1,
        at index: Int = 0,
        process: @escaping () async throws -> ActionResult,
        processAdvance: ((Task<ActionResult, any Error>) async -> Void)? = nil,
        expectationBeforeCompletion: (() -> Void)? = nil,
        completeWith: (() -> Swift.Result<Result, Error>)? = nil,
        expectationAfterCompletion: ((ActionResult) -> Void)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await _async(
            yieldCount: yieldCount,
            at: index,
            process: process,
            processAdvance: processAdvance,
            expectationBeforeCompletion: expectationBeforeCompletion,
            completeWith: completeWith,
            expectationAfterCompletion: expectationAfterCompletion,
            sourceLocation: sourceLocation
        )
    }

    @available(*, deprecated, message: "Use scenario {} instead")
    struct AdvancingProcess<T: Sendable> {
        let process: () async throws -> T
        let processAdvance: (() async -> Void)?

        public init(process: @escaping () async throws -> T, processAdvance: (() async -> Void)? = nil) {
            self.process = process
            self.processAdvance = processAdvance
        }
    }

    @available(*, deprecated, message: "Use scenario {} instead")
    func async<ActionResult: Sendable, Result: Sendable>(
        yieldCount: Int = 1,
        at index: Int = 0,
        processes: [AdvancingProcess<ActionResult>],
        expectationBeforeCompletion: (() -> Void)? = nil,
        completeWith: (() -> Swift.Result<Result, Error>)? = nil,
        expectationAfterCompletion: (([ActionResult]) -> Void)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await withMainSerialExecutor {
            var tasks: [Task<ActionResult, Error>] = []
            for advancingProcess in processes {
                let task = Task { try await advancingProcess.process() }
                tasks.append(task)
                for _ in 0 ..< yieldCount {
                    await Task.yield()
                }
                if let advance = advancingProcess.processAdvance {
                    await advance()
                }
            }
            expectationBeforeCompletion?()
            switch completeWith?() {
            case let .success(result):
                #if canImport(Testing)
                    complete(
                        with: result,
                        at: index,
                        sourceLocation: sourceLocation
                    )
                #else
                    complete(
                        with: result,
                        at: index,
                        file: file,
                        line: line
                    )
                #endif

            case let .failure(error):
                #if canImport(Testing)
                    complete(
                        with: error,
                        at: index,
                        sourceLocation: sourceLocation
                    )
                #else
                    complete(
                        with: error,
                        at: index,
                        file: file,
                        line: line
                    )
                #endif

            case .none:
                break
            }

            var result: [ActionResult] = []
            for task in tasks {
                let value = try await task.value
                result.append(value)
            }
            await Task.yield()
            expectationAfterCompletion?(result)
        }
    }

    /// Executes an asynchronous process with controlled timing and completion at a specific index.
    ///
    /// - Parameters:
    ///   - yieldCount: The number of times to yield before completing (default is 1).
    ///   - index: The index of the operation to complete (default is 0).
    ///   - process: The  synchronous process with hidden asynchronicity to execute.
    ///   - expectationBeforeCompletion: A closure to execute before completing the operation.
    ///   - completeWith: A closure that provides the result or error to complete with.
    ///   - expectationAfterCompletion: A closure to execute after completing the operation.
    @available(*, deprecated, message: "Use scenario {} instead")
    func synchronous<Result: Sendable>(
        yieldCount: Int = 1,
        at index: Int = 0,
        process: @escaping () -> Void,
        processAdvance: ((Task<Void, any Error>) async -> Void)? = nil,
        expectationBeforeCompletion: (() -> Void)? = nil,
        completeWith: (() -> Swift.Result<Result, Error>)? = nil,
        expectationAfterCompletion: (() -> Void)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await _async(
            yieldCount: yieldCount,
            at: index,
            process: process,
            processAdvance: processAdvance,
            expectationBeforeCompletion: expectationBeforeCompletion,
            completeWith: completeWith,
            expectationAfterCompletion: { (_: Void) in
                expectationAfterCompletion?()
            },
            sourceLocation: sourceLocation
        )
    }

    @available(*, deprecated, message: "Use scenario {} instead")
    func synchronous(
        yieldCount: Int = 1,
        at index: Int = 0,
        process: @escaping () -> Void,
        processAdvance: ((Task<Void, any Error>) async -> Void)? = nil,
        expectationBeforeCompletion: (() -> Void)? = nil,
        completeWith: (() -> Swift.Result<Void, Error>)? = nil,
        expectationAfterCompletion: (() -> Void)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await _async(
            yieldCount: yieldCount,
            at: index,
            process: process,
            processAdvance: processAdvance,
            expectationBeforeCompletion: expectationBeforeCompletion,
            completeWith: completeWith,
            expectationAfterCompletion: { (_: Void) in
                expectationAfterCompletion?()
            },
            sourceLocation: sourceLocation
        )
    }

    // MARK: - XCTest/Fallback Overloads

    #if !canImport(Testing)

        /// Executes an asynchronous process with controlled timing and completion at a specific index.
        @available(*, deprecated, message: "Use scenario {} instead")
        func async<ActionResult: Sendable, Result: Sendable>(
            yieldCount: Int = 1,
            at index: Int = 0,
            process: @escaping () async throws -> ActionResult,
            processAdvance: (() async -> Void)? = nil,
            expectationBeforeCompletion: (() -> Void)? = nil,
            completeWith: (() -> Swift.Result<Result, Error>)? = nil,
            expectationAfterCompletion: ((ActionResult) -> Void)? = nil,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws {
            try await _async(
                yieldCount: yieldCount,
                at: index,
                process: process,
                processAdvance: processAdvance,
                expectationBeforeCompletion: expectationBeforeCompletion,
                completeWith: completeWith,
                expectationAfterCompletion: expectationAfterCompletion,
                file: file,
                line: line
            )
        }

        @available(*, deprecated, message: "Use scenario {} instead")
        func async<ActionResult: Sendable, Result: Sendable>(
            yieldCount: Int = 1,
            at index: Int = 0,
            processes: [AdvancingProcess<ActionResult>],
            expectationBeforeCompletion: (() -> Void)? = nil,
            completeWith: (() -> Swift.Result<Result, Error>)? = nil,
            expectationAfterCompletion: (([ActionResult]) -> Void)? = nil,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws {
            try await withMainSerialExecutor {
                var tasks: [Task<ActionResult, Error>] = []
                for advancingProcess in processes {
                    let task = Task { try await advancingProcess.process() }
                    tasks.append(task)
                    for _ in 0 ..< yieldCount {
                        await Task.yield()
                    }
                    if let advance = advancingProcess.processAdvance {
                        await advance()
                    }
                }
                expectationBeforeCompletion?()
                switch completeWith?() {
                case let .success(result):
                    complete(
                        with: result,
                        at: index,
                        file: file,
                        line: line
                    )

                case let .failure(error):
                    complete(
                        with: error,
                        at: index,
                        file: file,
                        line: line
                    )

                case .none:
                    break
                }

                var result: [ActionResult] = []
                for task in tasks {
                    let value = try await task.value
                    result.append(value)
                }
                await Task.yield()
                expectationAfterCompletion?(result)
            }
        }

        @available(*, deprecated, message: "Use scenario {} instead")
        func synchronous<Result: Sendable>(
            yieldCount: Int = 1,
            at index: Int = 0,
            process: @escaping () -> Void,
            processAdvance: (() async -> Void)? = nil,
            expectationBeforeCompletion: (() -> Void)? = nil,
            completeWith: (() -> Swift.Result<Result, Error>)? = nil,
            expectationAfterCompletion: (() -> Void)? = nil,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws {
            try await _async(
                yieldCount: yieldCount,
                at: index,
                process: process,
                processAdvance: processAdvance,
                expectationBeforeCompletion: expectationBeforeCompletion,
                completeWith: completeWith,
                expectationAfterCompletion: { (_: Void) in
                    expectationAfterCompletion?()
                },
                file: file,
                line: line
            )
        }

        @available(*, deprecated, message: "Use scenario {} instead")
        func synchronous(
            yieldCount: Int = 1,
            at index: Int = 0,
            process: @escaping () -> Void,
            processAdvance: (() async -> Void)? = nil,
            expectationBeforeCompletion: (() -> Void)? = nil,
            completeWith: (() -> Swift.Result<Void, Error>)? = nil,
            expectationAfterCompletion: (() -> Void)? = nil,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws {
            try await _async(
                yieldCount: yieldCount,
                at: index,
                process: process,
                processAdvance: processAdvance,
                expectationBeforeCompletion: expectationBeforeCompletion,
                completeWith: completeWith,
                expectationAfterCompletion: { (_: Void) in
                    expectationAfterCompletion?()
                },
                file: file,
                line: line
            )
        }

    #endif
}
