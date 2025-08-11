// Test+Process.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-04-05 06:52 GMT.

import ConcurrencyExtras
import Foundation
import Testing

public
extension Test {
    /// Executes an asynchronous process with optional hooks before and after completion.
    ///
    /// This function runs the provided asynchronous process, yielding control to the main serial executor
    /// a specified number of times. Optional hooks can be executed before and after the process completes.
    ///
    /// - Parameters:
    ///   - yieldCount: The number of times to yield control to the main serial executor. Defaults to 1.
    ///   - process: The asynchronous process to execute.
    ///   - onBeforeCompletion: An optional closure to execute before the process completes.
    ///   - onAfterCompletion: An optional closure to execute after the process completes, with the result of the process.
    /// - Throws: An error if the process throws an error.
    /// - Returns: The result of the asynchronous process.
    ///
    /// - Example:
    /// ```swift
    /// try await Test.async(
    ///     yieldCount: 2,
    ///     process: {
    ///         // Your asynchronous process here
    ///         return "Result"
    ///     },
    ///     onBeforeCompletion: {
    ///         print("Before completion")
    ///     },
    ///     onAfterCompletion: { result in
    ///         print("After completion with result: \(result)")
    ///     }
    /// )
    /// ```
    @MainActor
    static func async<T: Sendable>(
        yieldCount: Int = 1,
        process: @escaping () async throws -> T,
        onBeforeCompletion: (() -> Void)? = nil,
        onAfterCompletion: ((T) -> Void)? = nil
    ) async throws {
        try await withMainSerialExecutor {
            let task = Task { try await process() }
            for _ in 0 ..< yieldCount {
                await Task.yield()
            }
            onBeforeCompletion?()
            let value = try await task.value
            onAfterCompletion?(value)
        }
    }
}
