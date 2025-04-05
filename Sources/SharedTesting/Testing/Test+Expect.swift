// Test+Expect.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2024-08-09 12:46 GMT.

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
    ///   func testAsyncOperation() async throws {
    ///       let viewModel = ViewModel()
    ///
    ///       await expect { try await viewModel.fetchData() }
    ///           .toCompleteWith { .success(["item1", "item2"]) }
    ///           .when { mockNetworkService.simulateNetworkDelay() }
    ///           .execute()
    ///   }
    ///   ```
    ///
    /// In this example:
    /// - `expect` is called with an async closure that fetches data from the view model.
    /// - `toCompleteWith` specifies the expected successful result.
    /// - `when` defines an action to be performed before the operation completes (simulating a network delay).
    /// - `execute()` runs the expectation and performs the assertions.
    ///
    /// You can also use it to test for expected errors:
    ///
    /// ```swift
    /// await expect { try await viewModel.fetchData() }
    ///     .toCompleteWith { .failure(NetworkError.connectionLost) }
    ///     .when { mockNetworkService.simulateConnectionLoss() }
    ///     .execute()
    /// ```
    ///
    /// - Note: The `execute()` method must be called at the end of the chain to perform the expectation.
    static func expect<T: Equatable & Sendable, E: Error & Equatable>(
        _ action: @escaping @Sendable () async throws -> T,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> ExpectationTracker<T, E> {
        ExpectationTracker(action, sourceLocation: sourceLocation)
    }
}
