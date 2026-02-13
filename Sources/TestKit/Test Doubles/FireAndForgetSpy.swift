// FireAndForgetSpy.swift
// Copyright (c) 2026 Moroverse
// Created by Daniel Moro on 2025-11-20 08:00 GMT.

import Foundation
#if canImport(Testing)
    import Testing
#endif

/// A test spy for verifying fire-and-forget asynchronous operations where the system under test
/// calls a method **synchronously** (without `await`) that triggers async work internally.
///
/// ## Overview
///
/// `FireAndForgetSpy` is designed for testing code that initiates async operations through
/// fire-and-forget method calls. Unlike `AsyncSpy` where you `await` the SUT action directly,
/// `FireAndForgetSpy` handles scenarios where:
/// - The SUT method returns immediately (synchronous call)
/// - Async work is spawned internally (Task, async/await, etc.)
/// - You need to control when and how the async operation completes
/// - You want to verify intermediate states (loading, error states, etc.)
///
/// ## When to Use FireAndForgetSpy vs AsyncSpy
///
/// **Use `FireAndForgetSpy` when:**
/// - The SUT fires off async work without awaiting it (fire-and-forget pattern)
/// - Testing ViewModels with methods like `loadData()`, `refresh()`, etc.
/// - You need to verify state changes **before** and **after** async completion
/// - Testing cancellation behavior and cleanup
///
/// **Use `AsyncSpy` when:**
/// - You **await** the SUT action directly
/// - Testing repository/service methods that return async results
/// - You don't need fine-grained control over completion timing
///
/// ## Complete Example: Testing a ViewModel
///
/// ```swift
/// // 1. Define your protocol
/// protocol UserServiceProtocol {
///     func loadUser(id: Int) async throws -> User
/// }
///
/// // 2. Make FireAndForgetSpy conform to your protocol
/// extension FireAndForgetSpy: UserServiceProtocol {
///     func loadUser(id: Int) async throws -> User {
///         try await perform(id)
///     }
/// }
///
/// // 3. Create your ViewModel (non-blocking calls)
/// @Observable
/// class UserViewModel {
///     private let service: UserServiceProtocol
///
///     private(set) var isLoading = false
///     private(set) var user: User?
///     private(set) var error: Error?
///
///     init(service: UserServiceProtocol) {
///         self.service = service
///     }
///
///     // Note: This method is NOT async - it spawns async work internally
///     func loadUser(id: Int) {
///         isLoading = true
///         error = nil
///
///         Task {
///             do {
///                 user = try await service.loadUser(id: id)
///                 isLoading = false
///             } catch {
///                 self.error = error
///                 isLoading = false
///             }
///         }
///     }
/// }
///
/// // 4. Test using scenario API (recommended approach)
/// @Test func testLoadUserSuccess() async throws {
///     let spy = FireAndForgetSpy()
///     let sut = UserViewModel(service: spy)
///     let expectedUser = User(id: 1, name: "Alice")
///
///     try await spy.scenario { step in
///         await step.trigger { sut.loadUser(id: 1) }
///         #expect(sut.isLoading == true)
///         await step.complete(with: expectedUser)
///         #expect(sut.isLoading == false)
///         #expect(sut.user?.id == 1)
///     }
/// }
///
/// // 5. Test error handling
/// @Test func testLoadUserFailure() async throws {
///     let spy = FireAndForgetSpy()
///     let sut = UserViewModel(service: spy)
///     struct TestError: Error {}
///
///     try await spy.scenario { step in
///         await step.trigger { sut.loadUser(id: 999) }
///         #expect(sut.isLoading == true)
///         await step.fail(with: TestError())
///         #expect(sut.isLoading == false)
///         #expect(sut.error != nil)
///     }
/// }
///
/// // 6. Test cancellation
/// @Test func testLoadUserCancellation() async throws {
///     let spy = FireAndForgetSpy()
///     let sut = UserViewModel(service: spy)
///
///     try await spy.scenario { step in
///         await step.trigger { sut.loadUser(id: 1) }
///         try await step.cancel()
///         let result = try await spy.result(at: 0)
///         #expect(result == .cancelled)
///     }
/// }
/// ```
///
/// ## Key Features
///
/// - **State Verification**: Inspect and verify SUT state before/after async completion
/// - **Controlled Completion**: Precisely control when and how async operations complete
/// - **Cancellation Testing**: Built-in support for testing cancellation scenarios
/// - **Result Tracking**: Explicit tracking of success/failure/cancelled states
/// - **Multiple Operations**: Handle multiple concurrent async operations
/// - **Timeout Support**: Query results with timeout to prevent indefinite waiting
///
/// ## Common Pitfalls
///
/// - Don't await the SUT action: `await sut.loadUser()` defeats the purpose
/// - Do call synchronously: `sut.loadUser()` and control completion separately
/// - Don't forget to complete/fail: Pending requests will timeout
/// - Do use `scenario {}`: It handles cleanup automatically
/// - Don't use for methods you await: Use `AsyncSpy` instead
/// - Do verify intermediate states: That's the whole point of fire-and-forget testing
///
@MainActor
public final class FireAndForgetSpy {
    /// Represents the result state of an async operation tracked by the spy.
    ///
    /// Use this enum to verify the outcome of async operations in your tests, especially
    /// when testing cancellation scenarios or when you need to inspect the result state
    /// without having the actual value or error.
    ///
    /// ## Usage Example
    ///
    /// ```swift
    /// @Test func testCancellation() async throws {
    ///     let spy = FireAndForgetSpy()
    ///     let sut = MyViewModel(service: spy)
    ///
    ///     sut.loadData()  // Triggers async work
    ///     try await spy.cancelPendingRequests()
    ///
    ///     let result = try await spy.result(at: 0)
    ///     #expect(result == .cancelled)  // Verify it was cancelled
    /// }
    /// ```
    public enum Result: Equatable {
        /// The async operation completed successfully.
        ///
        /// Set when `perform` returns a value without throwing.
        case success

        /// The async operation failed with an error.
        ///
        /// Set when `perform` throws an error (except `CancellationError`).
        case failure

        /// The async operation was cancelled.
        ///
        /// Set when `perform` throws `CancellationError` or `Task.isCancelled` is true.
        case cancelled
    }

    public private(set) var requests = [(
        params: [Any],
        stream: AsyncThrowingStream<any Sendable, Error>,
        continuation: AsyncThrowingStream<any Sendable, Error>.Continuation,
        tag: String?,
        result: Result?
    )]()

    public init() {}

    private struct NoResponse: Error {}
    private struct Timeout: Error {}
    private struct IncompatibleResourceType: Error {}

    /// The total number of times the `perform` method has been called.
    ///
    /// Use this property to verify that your SUT invoked the spy the expected number of times.
    /// Each call to `perform` (regardless of parameters or tag) increments this count.
    ///
    /// ## Usage Example
    ///
    /// ```swift
    /// @Test func testMultipleLoadCalls() async throws {
    ///     let spy = FireAndForgetSpy()
    ///     let sut = UserViewModel(service: spy)
    ///
    ///     sut.loadUser(id: 1)
    ///     sut.loadUser(id: 2)
    ///
    ///     #expect(spy.callCount == 2)  // Verify both calls were made
    /// }
    /// ```
    ///
    /// - Returns: The total number of `perform` invocations.
    ///
    /// - Note: This count includes all requests regardless of their completion state
    ///   (pending, completed, failed, or cancelled).
    public var callCount: Int {
        requests.count
    }

    /// Returns the number of times `perform` was called with a specific tag.
    ///
    /// Use tags to distinguish between different operations when the same spy is used
    /// for multiple protocol methods. This allows you to verify that specific operations
    /// were called the expected number of times.
    ///
    /// ## Usage Example
    ///
    /// ```swift
    /// extension FireAndForgetSpy: UserServiceProtocol {
    ///     func loadUser(id: Int) async throws -> User {
    ///         try await perform(id, tag: "loadUser")
    ///     }
    ///
    ///     func deleteUser(id: Int) async throws {
    ///         try await perform(id, tag: "deleteUser")
    ///     }
    /// }
    ///
    /// @Test func testUserOperations() async throws {
    ///     let spy = FireAndForgetSpy()
    ///     let sut = UserViewModel(service: spy)
    ///
    ///     sut.loadUser(id: 1)
    ///     sut.deleteUser(id: 2)
    ///     sut.loadUser(id: 3)
    ///
    ///     #expect(spy.callCount(forTag: "loadUser") == 2)
    ///     #expect(spy.callCount(forTag: "deleteUser") == 1)
    /// }
    /// ```
    ///
    /// - Parameter tag: The tag string to filter by.
    /// - Returns: The number of times `perform` was called with the specified tag.
    ///
    /// - Note: Returns 0 if no calls were made with the specified tag.
    public func callCount(forTag tag: String) -> Int {
        requests.count(where: { $0.tag == tag })
    }

    /// Performs an async operation that returns a value, tracking the call for later completion.
    ///
    /// This is the core method you'll use when implementing protocol conformances. It records
    /// the call parameters and waits for you to complete it using `complete(with:at:)` or
    /// `fail(with:at:)`. The method suspends until completion, allowing your tests to control
    /// exactly when and how the operation completes.
    ///
    /// ## Usage in Protocol Extension
    ///
    /// ```swift
    /// protocol UserServiceProtocol {
    ///     func loadUser(id: Int) async throws -> User
    /// }
    ///
    /// extension FireAndForgetSpy: UserServiceProtocol {
    ///     func loadUser(id: Int) async throws -> User {
    ///         try await perform(id, tag: "loadUser")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - parameters: Zero or more parameters of any `Sendable` type. These are stored
    ///     for inspection via the `requests` property.
    ///   - tag: Optional string tag to identify this operation. Useful when the same spy
    ///     handles multiple protocol methods. Defaults to `nil`.
    ///
    /// - Returns: The resource of type `Resource` provided via `complete(with:at:)`.
    ///
    /// - Throws:
    ///   - The error provided via `fail(with:at:)`
    ///   - `CancellationError` if cancelled via `cancelPendingRequests()`
    ///   - `IncompatibleResourceType` if the completed value cannot be cast to `Resource`
    ///   - `NoResponse` if the stream finishes without yielding a value
    ///
    /// - Note: This method suspends until `complete(with:at:)`, `fail(with:at:)`, or
    ///   `cancelPendingRequests()` is called. It **must** be completed eventually or the
    ///   test will hang.
    public func perform<each Parameter, Resource: Sendable>(_ parameters: repeat each Parameter, tag: String? = nil) async throws -> Resource {
        let (stream, continuation) = AsyncThrowingStream<any Sendable, Error>.makeStream()
        let index = requests.count

        var packed: [Any] = []

        func add(element: Any) {
            packed.append(element)
        }

        repeat add(element: each parameters)

        requests.append(
            (
                params: packed,
                stream: stream,
                continuation: continuation,
                tag: tag,
                result: nil
            )
        )

        do {
            for try await result in stream {
                try Task.checkCancellation()
                requests[index].result = .success
                if let result = result as? Resource {
                    return result
                } else {
                    throw IncompatibleResourceType()
                }
            }

            try Task.checkCancellation()

            throw NoResponse()
        } catch {
            if Task.isCancelled {
                requests[index].result = .cancelled
            } else {
                requests[index].result = .failure
            }
            throw error
        }
    }

    /// Performs an async operation that doesn't return a value, tracking the call for later completion.
    ///
    /// This overload is used for async methods that don't return a result (only side effects).
    /// Like the returning variant, it records the call parameters and waits for completion,
    /// allowing your tests to control timing and outcome.
    ///
    /// ## Usage in Protocol Extension
    ///
    /// ```swift
    /// protocol UserServiceProtocol {
    ///     func deleteUser(id: Int) async throws
    ///     func syncData() async throws
    /// }
    ///
    /// extension FireAndForgetSpy: UserServiceProtocol {
    ///     func deleteUser(id: Int) async throws {
    ///         try await perform(id, tag: "deleteUser")
    ///     }
    ///
    ///     func syncData() async throws {
    ///         try await perform(tag: "syncData")  // No parameters
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - parameters: Zero or more parameters of any `Sendable` type. These are stored
    ///     for inspection via the `requests` property.
    ///   - tag: Optional string tag to identify this operation. Useful when the same spy
    ///     handles multiple protocol methods. Defaults to `nil`.
    ///
    /// - Throws:
    ///   - The error provided via `fail(with:at:)`
    ///   - `CancellationError` if cancelled via `cancelPendingRequests()`
    ///   - `NoResponse` if the stream finishes without yielding a value
    ///
    /// - Note: Complete this operation by calling `complete(with: (), at: index)` where
    ///   you pass an empty tuple `()` as the resource.
    public func perform<each Parameter>(_ parameters: repeat each Parameter, tag: String? = nil) async throws {
        let (stream, continuation) = AsyncThrowingStream<any Sendable, Error>.makeStream()
        let index = requests.count

        var packed: [Any] = []

        func add(element: Any) {
            packed.append(element)
        }

        repeat add(element: each parameters)

        requests.append(
            (
                params: packed,
                stream: stream,
                continuation: continuation,
                tag: tag,
                result: nil
            )
        )

        do {
            for try await _ in stream {
                try Task.checkCancellation()
                requests[index].result = .success
                return
            }

            try Task.checkCancellation()

            throw NoResponse()
        } catch {
            if Task.isCancelled {
                requests[index].result = .cancelled
            } else {
                requests[index].result = .failure
            }
            throw error
        }
    }

    /// Completes a pending async operation with a successful result.
    ///
    /// This method causes the corresponding `perform` call to return the provided resource.
    /// It polls asynchronously (using `Task.yield()`) until the result state is updated,
    /// ensuring the async operation has fully processed the completion before continuing.
    ///
    /// - Parameters:
    ///   - resource: The value to return from the `perform` call. Must match the `Resource`
    ///     type expected by the `perform` method.
    ///   - index: The zero-based index of the request to complete. First call is 0, second is 1, etc.
    ///
    /// - Note: For void-returning `perform` methods, pass an empty tuple: `complete(with: (), at: 0)`.
    func complete(with resource: some Sendable, at index: Int) async {
        requests[index].continuation.yield(resource)
        requests[index].continuation.finish()

        while requests[index].result == nil {
            await Task.yield()
        }
    }

    /// Completes a pending async operation with a failure.
    ///
    /// This method causes the corresponding `perform` call to throw the provided error.
    /// It polls asynchronously (using `Task.yield()`) until the result state is updated,
    /// ensuring the async operation has fully processed the failure before continuing.
    ///
    /// - Parameters:
    ///   - error: The error to throw from the `perform` call.
    ///   - index: The zero-based index of the request to fail. First call is 0, second is 1, etc.
    ///
    /// - Note: The result state will be set to `.failure` (not `.cancelled`) even if you
    ///   pass a `CancellationError`. Use `cancelPendingRequests()` for proper cancellation.
    func fail(with error: Error, at index: Int) async {
        requests[index].continuation.finish(throwing: error)

        while requests[index].result == nil {
            await Task.yield()
        }
    }

    /// Waits for and returns the result state of an async operation with a timeout.
    ///
    /// This method polls the result state asynchronously until it becomes available or the
    /// timeout expires. Use it when you need to wait for an operation to complete and inspect
    /// whether it succeeded, failed, or was cancelled.
    ///
    /// - Parameters:
    ///   - index: The zero-based index of the request to query. First call is 0, second is 1, etc.
    ///   - timeout: Maximum time to wait for the result, in seconds. Defaults to 1 second.
    ///
    /// - Returns: The result state (`.success`, `.failure`, or `.cancelled`) once available.
    ///
    /// - Throws: `Timeout` error if the result is not available within the timeout period.
    ///
    /// - Note: This method yields repeatedly while waiting, allowing other tasks to run.
    ///   Increase timeout if you expect slow state updates in your ViewModel.
    public func result(at index: Int, timeout: TimeInterval = 1) async throws -> Result {
        let endDate = Date().addingTimeInterval(timeout)
        while Date() < endDate {
            if let result = requests[index].result {
                return result
            }

            await Task.yield()
        }

        throw Timeout()
    }

    /// Cancels all pending async operations that haven't completed yet.
    ///
    /// This method finds all requests that don't have a result yet and finishes them with
    /// `CancellationError`. It's essential for testing cancellation scenarios and for cleanup.
    /// The `scenario {}` API calls this automatically after the body completes.
    ///
    /// - Throws: This method is marked `throws` for consistency but doesn't currently throw errors.
    ///
    /// - Important: This method only cancels **pending** requests (those without a result).
    ///   Completed, failed, or already-cancelled requests are unaffected.
    public func cancelPendingRequests() async throws {
        for (index, request) in requests.enumerated() where request.result == nil {
            request.continuation.finish(throwing: CancellationError())

            while requests[index].result == nil {
                await Task.yield()
            }
        }
    }
}

// MARK: - Scenario API

public extension FireAndForgetSpy {
    /// Defines how to complete a cascading operation.
    enum CascadeCompletion {
        case void
        case success(any Sendable)
        case failure(Error)
        case skip
    }

    /// A step-by-step orchestrator for structured fire-and-forget test scenarios.
    ///
    /// `ScenarioStep` provides an imperative, sequential interface for testing fire-and-forget
    /// operations. Instead of passing closures for each phase, you write steps in natural order
    /// with inline assertions between them.
    ///
    /// ## Basic Usage
    ///
    /// ```swift
    /// try await spy.scenario { step in
    ///     await step.trigger { sut.loadUser(id: 1) }
    ///     #expect(sut.isLoading)
    ///     await step.complete(with: expectedUser)
    ///     #expect(sut.user?.id == 1)
    /// }
    /// ```
    @MainActor final class ScenarioStep {
        private let spy: FireAndForgetSpy
        private let yieldCount: Int
        private var nextCascadeIndex: Int = 0

        init(spy: FireAndForgetSpy, yieldCount: Int) {
            self.spy = spy
            self.yieldCount = yieldCount
        }

        /// Calls the synchronous process and yields to let internally-spawned tasks execute.
        ///
        /// Use this for fire-and-forget SUT methods that are synchronous but internally spawn
        /// a `Task`. The process is called directly, then yields `yieldCount` times to allow
        /// the internal Task to reach the spy's stream.
        ///
        /// ```swift
        /// try await spy.scenario { step in
        ///     await step.trigger { sut.loadUser(id: 1) }
        ///     await step.complete(with: expectedUser)
        /// }
        /// ```
        ///
        /// - Parameter process: The synchronous operation to execute (typically calls the SUT).
        public func trigger(_ process: () -> Void) async {
            process()
            for _ in 0 ..< yieldCount {
                await Task.yield()
            }
        }

        /// Completes the pending operation at the given index with a success value.
        ///
        /// Delegates to the spy's `complete(with:at:)` which polls until the result propagates,
        /// then updates `nextCascadeIndex` to `index + 1` for subsequent cascade completions.
        ///
        /// - Parameters:
        ///   - result: The value to complete the operation with.
        ///   - index: The index of the pending operation to complete (default is 0).
        public func complete(with result: some Sendable, at index: Int = 0) async {
            await spy.complete(with: result, at: index)
            nextCascadeIndex = index + 1
        }

        /// Fails the pending operation at the given index with an error.
        ///
        /// Delegates to the spy's `fail(with:at:)` which polls until the result propagates,
        /// then updates `nextCascadeIndex` to `index + 1`.
        ///
        /// - Parameters:
        ///   - error: The error to fail the operation with.
        ///   - index: The index of the pending operation to fail (default is 0).
        public func fail(with error: Error, at index: Int = 0) async {
            await spy.fail(with: error, at: index)
            nextCascadeIndex = index + 1
        }

        /// Cancels all pending requests that haven't completed yet.
        ///
        /// Delegates to the spy's `cancelPendingRequests()`.
        public func cancel() async throws {
            try await spy.cancelPendingRequests()
        }

        /// Completes cascading operations that were triggered by the primary completion.
        ///
        /// When completing the primary operation causes the SUT to make additional async calls
        /// (e.g., delete then reload), use `cascade` to complete those subsequent operations.
        /// Each completion is applied at `nextCascadeIndex` (auto-incremented).
        ///
        /// ```swift
        /// try await spy.scenario { step in
        ///     await step.trigger { sut.deleteAndReload(item) }
        ///     await step.complete(with: ())          // completes delete at index 0
        ///     await step.cascade(.success(newList))   // completes reload at index 1
        ///     #expect(sut.items == newList)
        /// }
        /// ```
        ///
        /// - Parameter completions: One or more `CascadeCompletion` values to apply in order.
        public func cascade(_ completions: CascadeCompletion...) async {
            for completion in completions {
                switch completion {
                case .void:
                    await spy.complete(with: (), at: nextCascadeIndex)
                case let .success(value):
                    await spy.complete(with: value, at: nextCascadeIndex)
                case let .failure(error):
                    await spy.fail(with: error, at: nextCascadeIndex)
                case .skip:
                    break
                }
                nextCascadeIndex += 1
            }
        }
    }

    /// Executes a structured test scenario with step-by-step phase control.
    ///
    /// `scenario` creates a `ScenarioStep` context and auto-cancels all pending operations
    /// after the body completes (matching previous `withSpy` cleanup behavior).
    ///
    /// ## Overview
    ///
    /// ```swift
    /// try await spy.scenario { step in
    ///     await step.trigger { sut.loadUser(id: 1) }
    ///     #expect(sut.isLoading)
    ///     await step.complete(with: expectedUser)
    ///     #expect(sut.user?.id == 1)
    /// }
    /// ```
    ///
    /// ## How `yieldCount` Affects Timing
    ///
    /// The `yieldCount` controls how many times `Task.yield()` is called after each trigger.
    /// Higher values give internally-spawned tasks more opportunities to progress. The default
    /// of 1 is sufficient for most cases; increase it when the SUT has multiple suspension
    /// points before reaching the spy.
    ///
    /// - Parameters:
    ///   - yieldCount: Number of times to yield after each trigger (default is 1).
    ///   - body: A closure receiving a ``ScenarioStep`` for orchestrating the test phases.
    func scenario(
        yieldCount: Int = 1,
        _ body: (ScenarioStep) async throws -> Void
    ) async throws {
        let step = ScenarioStep(spy: self, yieldCount: yieldCount)
        try await body(step)
        try await cancelPendingRequests()
    }
}
