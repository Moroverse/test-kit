// ExpectationTracker.swift
// Copyright (c) 2026 Moroverse
// Created by Daniel Moro on 2025-04-05 06:52 GMT.

import ConcurrencyExtras
import Foundation
import Testing

// A struct that facilitates tracking expectations for asynchronous operations.
//
// `ExpectationTracker` provides a fluent interface for setting up expectations
// for asynchronous operations, including the ability to specify an event to occur
// before completion and the expected result.
//
// - Note: This struct is designed to be used with the `expect` function.

public struct ExpectationTracker<T: Equatable & Sendable, E: Error & Equatable>: @unchecked Sendable {
    private let action: @Sendable () async throws -> T
    private var expectedResult: (() async -> Result<T, E>)?
    private var event: (() async -> Void)?
    private let sourceLocation: SourceLocation

    public init(
        _ action: @escaping @Sendable () async throws -> T,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        self.action = action
        self.sourceLocation = sourceLocation
    }

    public init(
        _ action: @escaping @Sendable () async throws -> T,
        fileID: String = #fileID,
        file: String = #filePath,
        line: Int = #line,
        column: Int = #column
    ) {
        self.action = action
        sourceLocation = SourceLocation(fileID: fileID, filePath: file, line: line, column: column)
    }

    /// Specifies the expected result of the asynchronous operation.
    ///
    /// - Parameter result: A closure returning the expected result.
    /// - Returns: A new `ExpectationTracker` instance with the expected result configured.
    public func toCompleteWith(_ result: @escaping () async -> Result<T, E>) -> Self {
        var copy = self
        copy.expectedResult = result
        return copy
    }

    /// Specifies an event to occur before the completion of the asynchronous operation.
    ///
    /// - Parameter event: A closure representing the event to occur.
    /// - Returns: A new `ExpectationTracker` instance with the event configured.
    public func when(_ event: @escaping () async -> Void) -> Self {
        var copy = self
        copy.event = event
        return copy
    }

    /// Executes the configured expectation tracking operation.
    ///
    /// This method performs the asynchronous action, triggers the event if specified,
    /// and checks the result against the expected outcome.
    ///
    public func execute() async {
        guard let expectedResult else {
            Issue.record("Expected result not set", sourceLocation: sourceLocation)
            return
        }

        let expected = await expectedResult()

        do {
            let receivedValue = try await performAsync(process: action, onBeforeCompletion: event ?? {})

            switch expected {
            case let .success(expectedValue):
                #expect(receivedValue == expectedValue, "Received value did not match expectation", sourceLocation: sourceLocation)

            case .failure:
                Issue.record("Expected failure, but got success: \(receivedValue)", sourceLocation: sourceLocation)
            }
        } catch {
            switch expected {
            case .success:
                Issue.record("Expected success, but got error: \(error)", sourceLocation: sourceLocation)
            case let .failure(expectedError):
                if let error = error as? E {
                    #expect(error == expectedError, "Received error did not match expectation", sourceLocation: sourceLocation)
                } else {
                    Issue.record(error, sourceLocation: sourceLocation)
                }
            }
        }
    }

    private func performAsync(
        process: @escaping @Sendable () async throws -> T,
        onBeforeCompletion: @escaping () async -> Void
    ) async throws -> T {
        let task = Task {
            try await process()
        }
        await Task.megaYield()
        await onBeforeCompletion()
        return try await task.value
    }
}
