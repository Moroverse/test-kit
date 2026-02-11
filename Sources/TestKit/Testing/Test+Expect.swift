// Test+Expect.swift
// Copyright (c) 2026 Moroverse
// Created by Daniel Moro on 2025-04-05 06:52 GMT.

import Testing

public extension Test {
    /// Creates an expectation tracker for an asynchronous operation using the Testing framework.
    ///
    /// This method provides a fluent interface to set up and execute expectations for asynchronous operations.
    /// It allows you to specify the expected result and an optional event to occur before completion.
    ///
    /// - Parameters:
    ///   - action: An asynchronous closure representing the operation to be tested.
    ///   - sourceLocation: The source location where the expectation is being set up. Defaults to the current location.
    ///
    /// - Returns: An `ExpectationTracker` instance that you can use to configure and execute the expectation.
    ///
    /// - Usage:
    ///   ```swift
    ///    @Test("ViewModel fetches data successfully")
    ///    func testFetchDataSuccess() async throws {
    ///        let spy = MockNetworkService()
    ///        let viewModel = ViewModel(networkService: spy)
    ///        let data = ["item1", "item2"].joined(separator: ",").data(using: .utf8)!
    ///
    ///        await Test.expect { try await viewModel.fetchItems() }
    ///            .toCompleteWith { .success(["item1", "item2"]) }
    ///            .when { await spy.completeWith(.success(data)) }
    ///            .execute()
    ///    }
    ///   ```
    ///
    /// In this example:
    /// - `expect` is called with an async closure that fetches data from the view model.
    /// - `toCompleteWith` specifies the expected successful result.
    /// - `when` defines an action to be performed before the operation completes .
    /// - `execute()` runs the expectation and performs the assertions.
    ///
    /// You can also use it to test for expected errors:
    ///
    /// ```swift
    ///     func testFetchDataError() async throws {
    ///         let spy = FailingNetworkService()
    ///         let viewModel = ViewModel(networkService: spy)
    ///         let error = NetworkError.connectionLost
    ///
    ///         await Test.expect { try await viewModel.fetchItems() }
    ///             .toCompleteWith { .failure(error) }
    ///             .when { await spy.completeWith(.failure(error)) }
    ///             .execute()
    ///     }
    /// ```
    ///
    /// - Note: The `execute()` method must be called at the end of the chain to perform the expectation.
    static func expect<T: Equatable & Sendable, E: Error & Equatable>(
        _ action: @escaping @Sendable () async throws -> T,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> ExpectationTracker<T, E> {
        ExpectationTracker(action, sourceLocation: sourceLocation)
    }

    static func expect<T: Equatable & Sendable>(
        _ action: @escaping @Sendable () async throws -> T,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> ExpectationTracker<T, Never> {
        ExpectationTracker(action, sourceLocation: sourceLocation)
    }
}
