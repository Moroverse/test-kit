// NonBlockingAsyncSpy.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-11-20 08:00 GMT.

import Foundation

/// A test spy for verifying non-blocking asynchronous operations where the system under test
/// calls a method **synchronously** (without `await`) that triggers async work internally.
///
/// ## Overview
///
/// `NonBlockingAsyncSpy` is designed for testing code that initiates async operations through
/// fire-and-forget method calls. Unlike `AsyncSpy` where you `await` the SUT action directly,
/// `NonBlockingAsyncSpy` handles scenarios where:
/// - The SUT method returns immediately (synchronous call)
/// - Async work is spawned internally (Task, async/await, etc.)
/// - You need to control when and how the async operation completes
/// - You want to verify intermediate states (loading, error states, etc.)
///
/// ## When to Use NonBlockingAsyncSpy vs AsyncSpy
///
/// **Use `NonBlockingAsyncSpy` when:**
/// - SUT methods are called **without `await`** (fire-and-forget pattern)
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
/// // 2. Make NonBlockingAsyncSpy conform to your protocol
/// extension NonBlockingAsyncSpy: UserServiceProtocol {
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
/// // 4. Test using withSpy helper (recommended approach)
/// @Test func testLoadUserSuccess() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = UserViewModel(service: spy)
///     let expectedUser = User(id: 1, name: "Alice")
///
///     try await withSpy(spy) {
///         sut.loadUser(id: 1)  // ← No await! Non-blocking call
///     } beforeCompletion: {
///         #expect(sut.isLoading == true)   // Verify loading state
///         #expect(sut.user == nil)
///         #expect(sut.error == nil)
///     } completeWith: {
///         expectedUser  // Control when/what the async operation returns
///     } afterCompletion: {
///         #expect(sut.isLoading == false)  // Verify final state
///         #expect(sut.user?.id == 1)
///         #expect(sut.error == nil)
///     }
/// }
///
/// // 5. Test error handling
/// @Test func testLoadUserFailure() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = UserViewModel(service: spy)
///     struct TestError: Error {}
///
///     try await withSpy(spy) {
///         sut.loadUser(id: 999)
///     } beforeCompletion: {
///         #expect(sut.isLoading == true)
///         #expect(sut.error == nil)
///     } failWith: {
///         TestError()  // Simulate failure
///     } afterCompletion: {
///         #expect(sut.isLoading == false)
///         #expect(sut.user == nil)
///         #expect(sut.error != nil)
///     }
/// }
///
/// // 6. Advanced: Direct usage without withSpy helper
/// @Test func testLoadUserCancellation() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = UserViewModel(service: spy)
///
///     // Trigger the operation
///     sut.loadUser(id: 1)
///
///     // Verify loading state
///     #expect(sut.isLoading == true)
///
///     // Cancel all pending requests
///     try await spy.cancelPendingRequests()
///
///     // Wait for result and verify cancellation
///     let result = try await spy.result(at: 0)
///     #expect(result == .cancelled)
///     #expect(sut.isLoading == false)
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
/// - ❌ **Don't await the SUT action**: `await sut.loadUser()` defeats the purpose
/// - ✅ **Do call synchronously**: `sut.loadUser()` and control completion separately
/// - ❌ **Don't forget to complete/fail**: Pending requests will timeout
/// - ✅ **Do use `withSpy` helpers**: They handle completion and cleanup automatically
/// - ❌ **Don't use for methods you await**: Use `AsyncSpy` instead
/// - ✅ **Do verify intermediate states**: That's the whole point of non-blocking testing
///
public final class NonBlockingAsyncSpy {
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
    ///     let spy = NonBlockingAsyncSpy()
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
    ///     let spy = NonBlockingAsyncSpy()
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
    /// extension NonBlockingAsyncSpy: UserServiceProtocol {
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
    ///     let spy = NonBlockingAsyncSpy()
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
    /// extension NonBlockingAsyncSpy: UserServiceProtocol {
    ///     func loadUser(id: Int) async throws -> User {
    ///         try await perform(id, tag: "loadUser")
    ///     }
    /// }
    /// ```
    ///
    /// ## Testing with Direct Usage
    ///
    /// ```swift
    /// @Test func testLoadUserDirect() async throws {
    ///     let spy = NonBlockingAsyncSpy()
    ///     let sut = UserViewModel(service: spy)
    ///     let expectedUser = User(id: 1, name: "Alice")
    ///
    ///     // Trigger non-blocking call
    ///     sut.loadUser(id: 1)
    ///
    ///     // Verify intermediate state
    ///     #expect(sut.isLoading == true)
    ///
    ///     // Complete the operation
    ///     spy.complete(with: expectedUser, at: 0)
    ///
    ///     // Wait for result
    ///     let result = try await spy.result(at: 0)
    ///     #expect(result == .success)
    ///
    ///     // Verify final state
    ///     #expect(sut.user?.id == 1)
    ///     #expect(sut.isLoading == false)
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
    ///   test will hang (or timeout with `withSpy` helpers).
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
    /// extension NonBlockingAsyncSpy: UserServiceProtocol {
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
    /// ## Testing Example
    ///
    /// ```swift
    /// @Test func testDeleteUser() async throws {
    ///     let spy = NonBlockingAsyncSpy()
    ///     let sut = UserViewModel(service: spy)
    ///
    ///     try await withSpy(spy) {
    ///         sut.deleteUser(id: 42)  // No await - non-blocking
    ///     } beforeCompletion: {
    ///         #expect(sut.isDeleting == true)
    ///     } completeWith: {
    ///         () // Complete successfully with no value
    ///     } afterCompletion: {
    ///         #expect(sut.isDeleting == false)
    ///         #expect(sut.userWasDeleted == true)
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
    ///   you pass an empty tuple `()` as the resource, or use the `withSpy` helpers which
    ///   handle this automatically.
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
    /// It blocks synchronously (using RunLoop polling) until the result state is updated,
    /// ensuring the async operation has fully processed the completion before continuing.
    ///
    /// ## Direct Usage Example
    ///
    /// ```swift
    /// @Test func testManualCompletion() async throws {
    ///     let spy = NonBlockingAsyncSpy()
    ///     let sut = UserViewModel(service: spy)
    ///     let expectedUser = User(id: 1, name: "Alice")
    ///
    ///     // Trigger the operation
    ///     sut.loadUser(id: 1)
    ///
    ///     // Verify loading state
    ///     #expect(sut.isLoading == true)
    ///
    ///     // Complete the first request (index 0)
    ///     spy.complete(with: expectedUser, at: 0)
    ///
    ///     // Wait for result propagation
    ///     let result = try await spy.result(at: 0)
    ///     #expect(result == .success)
    ///
    ///     // Verify final state
    ///     #expect(sut.user?.id == 1)
    ///     #expect(sut.isLoading == false)
    /// }
    /// ```
    ///
    /// ## Multiple Operations Example
    ///
    /// ```swift
    /// @Test func testMultipleOperations() async throws {
    ///     let spy = NonBlockingAsyncSpy()
    ///     let sut = UserViewModel(service: spy)
    ///
    ///     // Trigger two operations
    ///     sut.loadUser(id: 1)  // Will be at index 0
    ///     sut.loadUser(id: 2)  // Will be at index 1
    ///
    ///     // Complete them in any order
    ///     spy.complete(with: User(id: 2, name: "Bob"), at: 1)
    ///     spy.complete(with: User(id: 1, name: "Alice"), at: 0)
    ///
    ///     #expect(spy.callCount == 2)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - resource: The value to return from the `perform` call. Must match the `Resource`
    ///     type expected by the `perform` method.
    ///   - index: The zero-based index of the request to complete. First call is 0, second is 1, etc.
    ///
    /// - Important: This method blocks the current thread using RunLoop until the result
    ///   is processed. Use `withSpy` helpers for automatic handling in most cases.
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
    /// It blocks synchronously (using RunLoop polling) until the result state is updated,
    /// ensuring the async operation has fully processed the failure before continuing.
    ///
    /// ## Direct Usage Example
    ///
    /// ```swift
    /// @Test func testManualFailure() async throws {
    ///     let spy = NonBlockingAsyncSpy()
    ///     let sut = UserViewModel(service: spy)
    ///     struct NetworkError: Error {}
    ///
    ///     // Trigger the operation
    ///     sut.loadUser(id: 999)
    ///
    ///     // Verify loading state
    ///     #expect(sut.isLoading == true)
    ///     #expect(sut.error == nil)
    ///
    ///     // Fail the request
    ///     spy.fail(with: NetworkError(), at: 0)
    ///
    ///     // Wait for result propagation
    ///     let result = try await spy.result(at: 0)
    ///     #expect(result == .failure)
    ///
    ///     // Verify error state
    ///     #expect(sut.isLoading == false)
    ///     #expect(sut.error != nil)
    /// }
    /// ```
    ///
    /// ## Testing Different Error Types
    ///
    /// ```swift
    /// @Test func testDifferentErrors() async throws {
    ///     let spy = NonBlockingAsyncSpy()
    ///     let sut = UserViewModel(service: spy)
    ///
    ///     // Test network error
    ///     sut.loadUser(id: 1)
    ///     spy.fail(with: URLError(.notConnectedToInternet), at: 0)
    ///     #expect(sut.errorMessage == "No internet connection")
    ///
    ///     // Test authentication error
    ///     sut.loadUser(id: 2)
    ///     spy.fail(with: URLError(.userAuthenticationRequired), at: 1)
    ///     #expect(sut.errorMessage == "Please log in")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - error: The error to throw from the `perform` call.
    ///   - index: The zero-based index of the request to fail. First call is 0, second is 1, etc.
    ///
    /// - Important: This method blocks the current thread using RunLoop until the error
    ///   is processed. Use `withSpy` helpers for automatic handling in most cases.
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
    /// ## Usage Example
    ///
    /// ```swift
    /// @Test func testResultStates() async throws {
    ///     let spy = NonBlockingAsyncSpy()
    ///     let sut = UserViewModel(service: spy)
    ///
    ///     // Trigger operation
    ///     sut.loadUser(id: 1)
    ///
    ///     // Complete it
    ///     spy.complete(with: User(id: 1, name: "Alice"), at: 0)
    ///
    ///     // Wait for and verify result state
    ///     let result = try await spy.result(at: 0, timeout: 2.0)
    ///     #expect(result == .success)
    /// }
    /// ```
    ///
    /// ## Testing Cancellation
    ///
    /// ```swift
    /// @Test func testCancellation() async throws {
    ///     let spy = NonBlockingAsyncSpy()
    ///     let sut = UserViewModel(service: spy)
    ///
    ///     // Trigger operation
    ///     sut.loadUser(id: 1)
    ///
    ///     // Cancel it
    ///     try await spy.cancelPendingRequests()
    ///
    ///     // Verify cancellation
    ///     let result = try await spy.result(at: 0)
    ///     #expect(result == .cancelled)
    /// }
    /// ```
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
    /// `CancellationError`. It's essential for testing cancellation scenarios and for cleanup
    /// in tests using direct spy usage (the `withSpy` helpers handle this automatically).
    ///
    /// ## Basic Cancellation Test
    ///
    /// ```swift
    /// @Test func testLoadCancellation() async throws {
    ///     let spy = NonBlockingAsyncSpy()
    ///     let sut = UserViewModel(service: spy)
    ///
    ///     // Trigger operation
    ///     sut.loadUser(id: 1)
    ///
    ///     // Verify loading state
    ///     #expect(sut.isLoading == true)
    ///
    ///     // Cancel all pending requests
    ///     try await spy.cancelPendingRequests()
    ///
    ///     // Verify cancellation was handled
    ///     let result = try await spy.result(at: 0)
    ///     #expect(result == .cancelled)
    ///     #expect(sut.isLoading == false)
    /// }
    /// ```
    ///
    /// ## Multiple Operations Cancellation
    ///
    /// ```swift
    /// @Test func testCancelMultipleOperations() async throws {
    ///     let spy = NonBlockingAsyncSpy()
    ///     let sut = UserViewModel(service: spy)
    ///
    ///     // Trigger multiple operations
    ///     sut.loadUser(id: 1)
    ///     sut.loadUser(id: 2)
    ///     sut.loadUser(id: 3)
    ///
    ///     // Complete one
    ///     spy.complete(with: User(id: 1, name: "Alice"), at: 0)
    ///
    ///     // Cancel remaining pending requests (indices 1 and 2)
    ///     try await spy.cancelPendingRequests()
    ///
    ///     // Verify states
    ///     #expect(try await spy.result(at: 0) == .success)
    ///     #expect(try await spy.result(at: 1) == .cancelled)
    ///     #expect(try await spy.result(at: 2) == .cancelled)
    /// }
    /// ```
    ///
    /// - Throws: This method is marked `throws` for consistency but doesn't currently throw errors.
    ///
    /// - Important: This method only cancels **pending** requests (those without a result).
    ///   Completed, failed, or already-cancelled requests are unaffected.
    ///
    /// - Note: The `withSpy` helper functions automatically call this method for cleanup,
    ///   so you typically don't need to call it manually when using helpers.
    public func cancelPendingRequests() async throws {
        for (index, request) in requests.enumerated() where request.result == nil {
            request.continuation.finish(throwing: CancellationError())

            while requests[index].result == nil {
                await Task.yield()
            }
        }
    }
}

// MARK: - Test Helpers

/// Helper function for testing non-blocking async operations with successful completion.
///
/// This is the **recommended** way to test with `NonBlockingAsyncSpy`. It provides a clean,
/// fluent API for executing actions, verifying intermediate states, controlling completion,
/// and verifying final states. It automatically handles cleanup by cancelling any remaining
/// pending requests.
///
/// ## Flow
///
/// 1. **`action`**: Triggers the non-blocking SUT method (no `await`)
/// 2. **`beforeCompletion`**: Verifies intermediate state (e.g., loading indicators)
/// 3. **`completeWith`**: Provides the success value for the async operation
/// 4. **`afterCompletion`**: Verifies final state after async completion
/// 5. **Cleanup**: Automatically cancels any other pending requests
///
/// ## Basic Example
///
/// ```swift
/// @Test func testLoadUserSuccess() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = UserViewModel(service: spy)
///     let expectedUser = User(id: 1, name: "Alice")
///
///     try await withSpy(spy) {
///         sut.loadUser(id: 1)  // ← No await! Non-blocking
///     } beforeCompletion: {
///         #expect(sut.isLoading == true)
///         #expect(sut.user == nil)
///     } completeWith: {
///         expectedUser
///     } afterCompletion: {
///         #expect(sut.isLoading == false)
///         #expect(sut.user?.id == 1)
///     }
/// }
/// ```
///
/// ## Testing Void-Returning Operations
///
/// ```swift
/// @Test func testSyncData() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = DataManager(service: spy)
///
///     try await withSpy(spy) {
///         sut.syncData()
///     } beforeCompletion: {
///         #expect(sut.isSyncing == true)
///     } completeWith: {
///         ()  // Empty tuple for void operations
///     } afterCompletion: {
///         #expect(sut.isSyncing == false)
///         #expect(sut.lastSyncDate != nil)
///     }
/// }
/// ```
///
/// ## Multiple Operations
///
/// ```swift
/// @Test func testMultipleLoads() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = UserViewModel(service: spy)
///
///     // First operation (index 0)
///     try await withSpy(spy, at: 0) {
///         sut.loadUser(id: 1)
///     } beforeCompletion: {
///         #expect(sut.isLoading == true)
///     } completeWith: {
///         User(id: 1, name: "Alice")
///     } afterCompletion: {
///         #expect(sut.user?.name == "Alice")
///     }
///
///     // Second operation (index 1)
///     try await withSpy(spy, at: 1) {
///         sut.loadUser(id: 2)
///     } beforeCompletion: {
///         #expect(sut.isLoading == true)
///     } completeWith: {
///         User(id: 2, name: "Bob")
///     } afterCompletion: {
///         #expect(sut.user?.name == "Bob")
///     }
/// }
/// ```
///
/// - Parameters:
///   - spy: The `NonBlockingAsyncSpy` instance being tested.
///   - index: The zero-based index of the request to complete. Defaults to 0 (first call).
///   - action: Closure that triggers the non-blocking SUT method. Called **synchronously**.
///   - beforeCompletion: Closure to verify intermediate state before async completion.
///   - completeWith: Closure that returns the resource to complete the async operation with.
///   - afterCompletion: Closure to verify final state after async completion.
///
/// - Throws: Errors from `cancelPendingRequests()` or if the test expectations fail.
///
/// - Note: This helper automatically cancels all other pending requests after completion,
///   ensuring clean test isolation.
public func withSpy(
    _ spy: NonBlockingAsyncSpy,
    at index: Int = 0,
    action: @escaping () -> Void,
    beforeCompletion: @escaping () -> Void,
    completeWith: @escaping () -> some Sendable,
    afterCompletion: @escaping () -> Void
) async throws {
    action()
    beforeCompletion()
    let resource = completeWith()
    await spy.complete(with: resource, at: index)
    afterCompletion()
    try await spy.cancelPendingRequests()
}

/// Helper function for testing non-blocking async operations with failure completion.
///
/// Use this variant when testing error scenarios. It follows the same flow as the success
/// helper but completes the async operation with an error instead of a success value.
/// Automatically handles cleanup by cancelling remaining pending requests.
///
/// ## Flow
///
/// 1. **`action`**: Triggers the non-blocking SUT method (no `await`)
/// 2. **`beforeCompletion`**: Verifies intermediate state before failure
/// 3. **`failWith`**: Provides the error to fail the async operation with
/// 4. **`afterCompletion`**: Verifies final error state
/// 5. **Cleanup**: Automatically cancels any other pending requests
///
/// ## Basic Error Handling Example
///
/// ```swift
/// @Test func testLoadUserFailure() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = UserViewModel(service: spy)
///     struct NetworkError: Error {}
///
///     try await withSpy(spy) {
///         sut.loadUser(id: 999)  // ← No await! Non-blocking
///     } beforeCompletion: {
///         #expect(sut.isLoading == true)
///         #expect(sut.error == nil)
///     } failWith: {
///         NetworkError()
///     } afterCompletion: {
///         #expect(sut.isLoading == false)
///         #expect(sut.user == nil)
///         #expect(sut.error != nil)
///     }
/// }
/// ```
///
/// ## Testing Different Error Types
///
/// ```swift
/// @Test func testNetworkErrors() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = UserViewModel(service: spy)
///
///     // Test no internet connection
///     try await withSpy(spy, at: 0) {
///         sut.loadUser(id: 1)
///     } beforeCompletion: {
///         #expect(sut.isLoading == true)
///     } failWith: {
///         URLError(.notConnectedToInternet)
///     } afterCompletion: {
///         #expect(sut.errorMessage == "No internet connection")
///     }
///
///     // Test server error
///     try await withSpy(spy, at: 1) {
///         sut.loadUser(id: 2)
///     } beforeCompletion: {
///         #expect(sut.isLoading == true)
///     } failWith: {
///         URLError(.badServerResponse)
///     } afterCompletion: {
///         #expect(sut.errorMessage == "Server error")
///     }
/// }
/// ```
///
/// ## Testing Error Recovery
///
/// ```swift
/// @Test func testRetryAfterFailure() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = UserViewModel(service: spy)
///     let user = User(id: 1, name: "Alice")
///
///     // First attempt fails
///     try await withSpy(spy, at: 0) {
///         sut.loadUser(id: 1)
///     } beforeCompletion: {
///         #expect(sut.isLoading == true)
///     } failWith: {
///         NetworkError()
///     } afterCompletion: {
///         #expect(sut.error != nil)
///     }
///
///     // Retry succeeds
///     try await withSpy(spy, at: 1) {
///         sut.retry()
///     } beforeCompletion: {
///         #expect(sut.isLoading == true)
///         #expect(sut.error == nil)  // Error cleared on retry
///     } completeWith: {
///         user
///     } afterCompletion: {
///         #expect(sut.user?.id == 1)
///         #expect(sut.error == nil)
///     }
/// }
/// ```
///
/// - Parameters:
///   - spy: The `NonBlockingAsyncSpy` instance being tested.
///   - index: The zero-based index of the request to fail. Defaults to 0 (first call).
///   - action: Closure that triggers the non-blocking SUT method. Called **synchronously**.
///   - beforeCompletion: Closure to verify intermediate state before failure.
///   - failWith: Closure that returns the error to fail the async operation with.
///   - atIndex: Deprecated parameter, not used. Will be removed in future versions.
///   - afterCompletion: Closure to verify final error state after async completion.
///
/// - Throws: Errors from `cancelPendingRequests()` or if the test expectations fail.
///
/// - Note: This helper automatically cancels all other pending requests after failure,
///   ensuring clean test isolation.
public func withSpy(
    _ spy: NonBlockingAsyncSpy,
    at index: Int = 0,
    action: @escaping () -> Void,
    beforeCompletion: @escaping () -> Void,
    failWith: @escaping () -> some Error,
    atIndex: @escaping () -> Int = { 0 },
    afterCompletion: @escaping () -> Void
) async throws {
    action()
    beforeCompletion()
    let error = failWith()
    await spy.fail(with: error, at: index)
    afterCompletion()
    try await spy.cancelPendingRequests()
}

/// Helper function for testing non-blocking async operations by inspecting their result state.
///
/// Use this variant when you want to test how the SUT handles async operations without
/// manually controlling completion. This is particularly useful for testing **cancellation**
/// scenarios or when the SUT itself controls how the async operation completes.
///
/// ## Flow
///
/// 1. **`action`**: Triggers the non-blocking SUT method (no `await`)
/// 2. **Wait**: Waits for the async operation to complete (with timeout)
/// 3. **`expect`**: Receives the result state and allows you to verify it
///
/// ## Testing Cancellation
///
/// ```swift
/// @Test func testUserCancelsLoad() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = UserViewModel(service: spy)
///
///     try await withSpy(spy) {
///         sut.loadUser(id: 1)
///         sut.cancelLoad()  // SUT handles cancellation internally
///     } expect: { result in
///         #expect(result == .cancelled)
///         #expect(sut.user == nil)
///         #expect(sut.isLoading == false)
///     }
/// }
/// ```
///
/// ## Testing Self-Completing Operations
///
/// ```swift
/// @Test func testAutoRetrySuccess() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = ResilientViewModel(service: spy)
///
///     try await withSpy(spy, at: 0) {
///         // SUT handles retry logic and completes the spy internally
///         sut.loadWithAutoRetry(id: 1)
///     } expect: { result in
///         #expect(result == .success)
///         #expect(sut.retryCount == 2)  // Auto-retried twice
///         #expect(sut.user != nil)
///     }
/// }
/// ```
///
/// ## Testing Multiple Independent Operations
///
/// ```swift
/// @Test func testConcurrentLoads() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = UserListViewModel(service: spy)
///
///     // Trigger concurrent loads
///     sut.loadUser(id: 1)
///     sut.loadUser(id: 2)
///     sut.loadUser(id: 3)
///
///     // First completes successfully
///     try await withSpy(spy, at: 0) {
///         // Operation already triggered above
///     } expect: { result in
///         #expect(result == .success)
///     }
///
///     // Second is cancelled
///     try await withSpy(spy, at: 1) {
///         // Already triggered
///     } expect: { result in
///         #expect(result == .cancelled)
///     }
///
///     // Third fails
///     try await withSpy(spy, at: 2) {
///         // Already triggered
///     } expect: { result in
///         #expect(result == .failure)
///     }
/// }
/// ```
///
/// ## Inspecting Request Parameters
///
/// ```swift
/// @Test func testRequestParameters() async throws {
///     let spy = NonBlockingAsyncSpy()
///     let sut = UserViewModel(service: spy)
///
///     try await withSpy(spy, at: 0) {
///         sut.loadUser(id: 42)
///     } expect: { result in
///         // Verify the spy was called with correct parameters
///         #expect(spy.requests[0].params.count == 1)
///         #expect(spy.requests[0].params[0] as? Int == 42)
///         #expect(result == .success)
///     }
/// }
/// ```
///
/// - Parameters:
///   - spy: The `NonBlockingAsyncSpy` instance being tested.
///   - index: The zero-based index of the request to inspect. Defaults to 0 (first call).
///   - action: Closure that triggers the non-blocking SUT method. Called **synchronously**.
///   - expect: Closure that receives the result state for verification.
///
/// - Throws: `Timeout` error if the result is not available within the default 1-second timeout,
///   or if the test expectations fail.
///
/// - Important: Unlike the other `withSpy` helpers, this variant does **NOT** automatically
///   cancel pending requests. You must manually call `spy.cancelPendingRequests()` if needed
///   for test cleanup.
///
/// - Note: The SUT is responsible for completing the async operation. If it never completes,
///   this will timeout after 1 second (default timeout in `spy.result(at:)`).
public func withSpy(
    _ spy: NonBlockingAsyncSpy,
    at index: Int = 0,
    action: @escaping () -> Void,
    expect: @escaping (NonBlockingAsyncSpy.Result) -> Void
) async throws {
    action()
    let result = try await spy.result(at: index)
    expect(result)
}
