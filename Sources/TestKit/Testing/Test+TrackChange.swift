// Test+TrackChange.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-04-05 06:52 GMT.

import Testing

public extension Test {
    /// Tracks changes to a property of a given object during a sequence of events and actions.
    ///
    /// This method provides a fluent interface to set up and execute a change tracking operation.
    /// It allows you to specify an initial setup, expectations before and after a change,
    /// and the action that causes the change. It uses the `Testing` framework for assertions.
    ///
    /// - Parameters:
    ///   - property: A KeyPath to the property you want to track in the subject under test.
    ///   - sut: The subject under test (SUT) containing the property to be tracked.
    ///   - sourceLocation: The source location where the tracking is being performed. Defaults to the current location.
    ///
    /// - Returns: A `ChangeTracker` instance that you can use to configure and execute the tracking.
    ///
    /// - Usage:
    ///   ```swift
    ///   await Test.trackChange(of: \.state, in: viewModel)
    ///       .givenInitialState { viewModel.updateQuery("new query") }
    ///       .expectInitialValue { .loading }
    ///       .whenChanging { await viewModel.performSearch() }
    ///       .expectFinalValue { .success(results) }
    ///       .execute()
    ///   ```
    ///
    /// - Note: The `execute()` method must be called at the end of the chain to perform the tracking.
    static func trackChange<SUT, T: Equatable>(
        of property: KeyPath<SUT, T>,
        in sut: SUT,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> ChangeTracker<SUT, T> {
        ChangeTracker(of: property, in: sut, sourceLocation: sourceLocation)
    }
}
