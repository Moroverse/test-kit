// AsyncSpy.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-01-17 06:03 GMT.

import ConcurrencyExtras
import Testing

/// A class for spying on asynchronous operations in Swift.
///
/// `AsyncSpy` allows you to track and control the execution of asynchronous operations,
/// making it useful for testing scenarios where you need to simulate or verify
/// asynchronous behavior.
///
/// - Note: This class is designed to be used in a testing environment.
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
public final class AsyncSpy<Result> where Result: Sendable {
    typealias ContinuationType = CheckedContinuation<Result, Error>
    private var messages: [(parameters: [any Sendable], continuation: ContinuationType)] = []

    /// The number of times the `perform` method has been called.
    public var performCallCount: Int {
        messages.count
    }

    /// Initializes a new instance of `AsyncSpy`.
    public init() {}

    /// Retrieves the parameters passed to a specific call of `perform`.
    ///
    /// - Parameter index: The index of the call to retrieve parameters for.
    /// - Returns: An array of `Sendable` parameters.
    public func params(at index: Int) -> [any Sendable] {
        messages[index].parameters
    }

    /// Simulates an asynchronous operation, capturing the parameters and providing a continuation.
    ///
    /// - Parameters:
    ///   - parameters: The parameters passed to the operation.
    /// - Returns: The result of the asynchronous operation.
    /// - Throws: An error if the operation fails.
    @Sendable
    public func perform<each Parameter: Sendable>(_ parameters: repeat each Parameter) async throws -> Result {
        var packed: [any Sendable] = []

        func add(element: some Sendable) {
            packed.append(element)
        }

        repeat add(element: each parameters)

        return try await withCheckedThrowingContinuation { continuation in
            messages.append((packed, continuation))
        }
    }

    /// Completes a pending operation with an error.
    ///
    /// - Parameters:
    ///   - error: The error to complete the operation with.
    ///   - index: The index of the operation to complete (default is 0).
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

    /// Completes a pending operation with a result.
    ///
    /// - Parameters:
    ///   - result: The result to complete the operation with.
    ///   - index: The index of the operation to complete (default is 0).
    public func complete(
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
}

public
extension AsyncSpy {
    /// Executes an asynchronous process with controlled timing and completion.
    ///
    /// - Parameters:
    ///   - yieldCount: The number of times to yield before completing (default is 1).
    ///   - process: The asynchronous process to execute.
    ///   - expectationBeforeCompletion: A closure to execute before completing the operation.
    ///   - completeWith: A closure that provides the result or error to complete with.
    ///   - expectationAfterCompletion: A closure to execute after completing the operation.
    /// - Throws: Any error that occurs during the process.
    func async<T: Sendable>(
        yieldCount: Int = 1,
        process: @escaping () async throws -> T,
        expectationBeforeCompletion: (() -> Void)? = nil,
        completeWith: (() -> Swift.Result<Result, Error>)? = nil,
        expectationAfterCompletion: ((T) -> Void)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await async(
            yieldCount: yieldCount,
            at: 0,
            process: process,
            expectationBeforeCompletion: expectationBeforeCompletion,
            completeWith: completeWith,
            expectationAfterCompletion: expectationAfterCompletion,
            sourceLocation: sourceLocation
        )
    }

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
    func async<T: Sendable>(
        yieldCount: Int = 1,
        at index: Int = 0,
        process: @escaping () async throws -> T,
        expectationBeforeCompletion: (() -> Void)? = nil,
        completeWith: (() -> Swift.Result<Result, Error>)? = nil,
        expectationAfterCompletion: ((T) -> Void)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await withMainSerialExecutor {
            let task = Task { try await process() }
            for _ in 0..<yieldCount {
                await Task.megaYield()
            }
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
            expectationAfterCompletion?(value)
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
    func async(
        yieldCount: Int = 1,
        at index: Int = 0,
        process: @escaping () -> Void,
        expectationBeforeCompletion: (() -> Void)? = nil,
        completeWith: (() -> Swift.Result<Result, Error>)? = nil,
        expectationAfterCompletion: (() -> Void)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        await withMainSerialExecutor {
            process()
            await Task.megaYield(count: yieldCount)
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

            expectationAfterCompletion?()
        }
    }
}
