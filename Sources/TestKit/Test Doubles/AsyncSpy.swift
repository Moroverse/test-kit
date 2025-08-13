// AsyncSpy.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-01-17 06:03 GMT.

import ConcurrencyExtras
#if canImport(Testing)
import Testing
#endif

/// A class for spying on asynchronous operations in Swift.
///
/// `AsyncSpy` allows you to track and control the execution of asynchronous operations,
/// making it useful for testing scenarios where you need to simulate or verify
/// asynchronous behavior.
///
/// - Note: This class is designed to be used in a testing environment.
/// - Note: Conditionally compatible with both Swift Testing and XCTest frameworks.
///   Uses `SourceLocation` with Swift Testing, falls back to `StaticString file, UInt line` otherwise.
///
/// # AsyncSpy Usage Guide
///
/// AsyncSpy is a powerful tool for testing asynchronous code in Swift. Here's how to use it effectively:
///
/// ## Setup
///
/// 1. Given protocol for the asynchronous operation you want to test:
///
///    ```swift
///    protocol FetchUserProtocol {
///        func fetch(by id: Int) async throws -> User
///    }
///    ```
///
/// 2. Implement AsyncSpy conformance to your protocol:
///
///    ```swift
///    extension AsyncSpy: FetchUserProtocol where Result == User {
///        func fetch(by id: Int) async throws -> User {
///            try await perform(id)
///        }
///    }
///    ```
/// 2a. Implement AsyncSpy conformance to protocol with arbitrary number of arguments:
///
///    ```swift
///    extension AsyncSpy: UpdateUserProtocol where Result == Void {
///        func update(user: User, sessionID: UUID, time: Date) async throws -> Void {
///            try await perform(user, sessionID, time)
///        }
///    }
///    ```
///
/// 3. In your test class, create a method to set up the system under test (SUT):
///
///    ```swift
///    final class ExampleTests: XCTestCase {
///        @MainActor
///        private func makeSUT() -> (sut: FetchUserViewModel, spy: AsyncSpy<User>) {
///            let spy = AsyncSpy<User>()
///            let sut = FetchUserViewModel(fetchUser: spy)
///            return (sut, spy)
///        }
///    }
///    ```
///
/// ## Writing Tests
///
/// ### Testing Successful Operations
///
/// Use the `async` method to control the flow of asynchronous operations:
///
/// ```swift
/// @MainActor
/// func testLoadSuccess() async throws {
///     let (sut, spy) = makeSUT()
///     try await spy.async {
///         await sut.fetchUser(by: 1)
///     } completeWith: {
///         .success(User(id: 1, name: "Alice"))
///     } expectationAfterCompletion: { _ in
///         XCTAssertEqual(spy.loadCallCount, 1)
///         XCTAssertEqual(spy.params(at: 0)[0] as? Int, 1)
///         XCTAssertEqual(sut.user?.id, 1)
///         XCTAssertEqual(sut.user?.name, "Alice")
///     }
/// }
/// ```
///
/// ### Testing Loading States
///
/// Use expectationBeforeCompletion and expectationAfterCompletion to verify state changes:
///
/// ```swift
/// @MainActor
/// func testLoading() async throws {
///     let (sut, spy) = makeSUT()
///     try await spy.async {
///         await sut.fetchUser(by: 1)
///     } expectationBeforeCompletion: {
///         XCTAssertTrue(sut.isLoading)
///     } completeWith: {
///         .failure(NSError(domain: "", code: 0))
///     } expectationAfterCompletion: { _ in
///         XCTAssertFalse(sut.isLoading)
///     }
/// }
/// ```
///
/// ### Controlling Timing with yieldCount
///
/// Adjust the `yieldCount` to control when the completion happens:
///
/// ```swift
/// try await spy.async(yieldCount: 2) {
///     await sut.load()
/// } completeWith: {
///     sut.cancel()
///     return .success(anyModel)
/// } expectationAfterCompletion: { _ in
///     XCTAssertEqual(sut.state, .empty)
/// }
/// ```
///
/// ### Handling Multiple Async Operations
///
/// Use the `at` parameter to specify which completion to invoke:
///
/// ```swift
/// try await spy.async(at: 1) {
///     await sut.load()
/// } completeWith: {
///     .success(model2)
/// } expectationAfterCompletion: { _ in
///     XCTAssertEqual(sut.state, .ready(model2))
///     XCTAssertEqual(spy.loadCallCount, 2)
/// }
/// ```
///
/// ## Best Practices
///
/// 1. Leverage `expectationBeforeCompletion` and `expectationAfterCompletion` to verify state changes.
/// 2. Use `params(at:)` to verify the parameters passed to async operations.
/// 3. Adjust `yieldCount` to test different timing scenarios.
/// 4. Use the `at` parameter when dealing with multiple async operations in a single test.

@MainActor
public final class AsyncSpy {
    typealias ContinuationType = CheckedContinuation<any Sendable, Error>
    private var messages: [(parameters: [(any Sendable)?], continuation: ContinuationType, tag: String?)] = []

    /// The number of times the `perform` method has been called.
    public var callCount: Int {
        messages.count
    }

    public func callCount(forTag tag: String) -> Int {
        messages.filter { $0.tag == tag }.count
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

        _ = try await withCheckedThrowingContinuation { continuation in
            messages.append((packed, continuation, tag))
        }
    }

    /// Completes a pending operation with an error.
    ///
    /// - Parameters:
    ///   - error: The error to complete the operation with.
    ///   - index: The index of the operation to complete (default is 0).
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

    /// Completes a pending operation with a result.
    ///
    /// - Parameters:
    ///   - result: The result to complete the operation with.
    ///   - index: The index of the operation to complete (default is 0).
    #if canImport(Testing)
    public func complete<Result: Sendable>(
        with result: Result,
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
    public func complete<Result: Sendable>(
        with result: Result,
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

public
extension AsyncSpy {

    #if canImport(Testing)
    private func _async<ActionResult: Sendable, Result: Sendable>(
        yieldCount: Int = 1,
        at index: Int = 0,
        process: @escaping () async throws -> ActionResult,
        processAdvance: (() async -> Void)? = nil,
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
            await processAdvance?()
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
    func async<ActionResult: Sendable, Result: Sendable>(
        yieldCount: Int = 1,
        at index: Int = 0,
        process: @escaping () async throws -> ActionResult,
        processAdvance: (() async -> Void)? = nil,
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

    struct AdvancingProcess<T: Sendable> {
        let process: () async throws -> T
        let processAdvance: (() async -> Void)?

        public init(process: @escaping () async throws -> T, processAdvance: (() async -> Void)? = nil) {
            self.process = process
            self.processAdvance = processAdvance
        }
    }

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
    func async<Result: Sendable>(
        yieldCount: Int = 1,
        at index: Int = 0,
        process: @escaping () -> Void,
        processAdvance: (() async -> Void)? = nil,
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

    func async(
        yieldCount: Int = 1,
        at index: Int = 0,
        process: @escaping () -> Void,
        processAdvance: (() async -> Void)? = nil,
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
    
    func async<Result: Sendable>(
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
    
    func async(
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
