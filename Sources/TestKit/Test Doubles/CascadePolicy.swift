// CascadePolicy.swift
// Copyright (c) 2026 Moroverse
// Created by Daniel Moro on 2026-02-11 10:33 GMT.

import ConcurrencyExtras
#if canImport(Testing)
    import Testing
#endif

// MARK: - Cascading Async Operations Support

@MainActor
public extension AsyncSpy {
    /// Configuration for how to handle cascading async operations
    struct CascadePolicy {
        let continuations: [CascadeCompletion]

        public init(_ continuations: [CascadeCompletion]) {
            self.continuations = continuations
        }
    }

    /// Defines how to complete a cascading operation
    enum CascadeCompletion {
        case void
        case success(any Sendable)
        case failure(Error)
        case skip

        @MainActor
        func apply(to spy: AsyncSpy, at index: Int) {
            switch self {
            case .void:
                spy.complete(with: (), at: index)
            case let .success(value):
                spy.complete(with: value, at: index)
            case let .failure(error):
                spy.complete(with: error, at: index)
            case .skip:
                break
            }
        }
    }

    #if canImport(Testing)
        /// Executes an asynchronous process that triggers cascading async calls
        ///
        /// Use this when your operation triggers multiple async calls in sequence.
        /// For example, a delete operation that calls `delete()` then `reload()`.
        ///
        /// - Parameters:
        ///   - yieldCount: The number of times to yield before completing (default is 1).
        ///   - at: The index of the first operation to complete (default is 0).
        ///   - process: The asynchronous process to execute.
        ///   - completeWith: A closure that provides the result for the first operation.
        ///   - cascade: Policy for completing subsequent operations triggered by the first.
        ///   - expectationAfterCompletion: A closure to execute after all operations complete.
        ///
        /// Example:
        /// ```swift
        /// try await spy.asyncWithCascade {
        ///     await sut.deleteEncounter(encounter)
        /// } completeWith: {
        ///     .success(()) // Complete the delete
        /// } cascade: {
        ///     .autoComplete(count: 1) // Auto-complete the reload
        /// } expectationAfterCompletion: {
        ///     #expect(spy.callCount(forTag: "Delete") == 1)
        /// }
        /// ```
        func asyncWithCascade<ActionResult: Sendable, Result: Sendable>(
            yieldCount: Int = 1,
            at index: Int = 0,
            process: @escaping () async throws -> ActionResult,
            expectationBeforeCompletion: (() -> Void)? = nil,
            completeWith: (() -> Swift.Result<Result, Error>)? = nil,
            cascade: () -> CascadePolicy,
            expectationAfterCompletion: ((ActionResult) -> Void)? = nil,
            sourceLocation: SourceLocation = #_sourceLocation
        ) async throws {
            try await withMainSerialExecutor {
                let task = Task { try await process() }
                for _ in 0 ..< yieldCount {
                    await Task.yield()
                }
                expectationBeforeCompletion?()

                // Complete the primary operation
                switch completeWith?() {
                case let .success(result):
                    complete(with: result, at: index, sourceLocation: sourceLocation)
                case let .failure(error):
                    complete(with: error, at: index, sourceLocation: sourceLocation)
                case .none:
                    break
                }

                // Complete cascading operations
                await Task.yield()
                for (offset, completion) in cascade().continuations.enumerated() {
                    completion.apply(to: self, at: index + offset + 1)
                    await Task.yield()
                }

                let value = try await task.value
                await Task.yield()
                expectationAfterCompletion?(value)
            }
        }

        /// Synchronous version for operations that hide async work
        func synchronousWithCascade<Result: Sendable>(
            yieldCount: Int = 1,
            at index: Int = 0,
            process: @escaping () -> Void,
            expectationBeforeCompletion: (() -> Void)? = nil,
            completeWith: (() -> Swift.Result<Result, Error>)? = nil,
            cascade: () -> CascadePolicy,
            expectationAfterCompletion: (() -> Void)? = nil,
            sourceLocation: SourceLocation = #_sourceLocation
        ) async throws {
            try await asyncWithCascade(
                yieldCount: yieldCount,
                at: index,
                process: process,
                expectationBeforeCompletion: expectationBeforeCompletion,
                completeWith: completeWith,
                cascade: cascade,
                expectationAfterCompletion: { (_: Void) in
                    expectationAfterCompletion?()
                },
                sourceLocation: sourceLocation
            )
        }
    #else

        /// XCTest versions
        func asyncWithCascade<ActionResult: Sendable, Result: Sendable>(
            yieldCount: Int = 1,
            at index: Int = 0,
            process: @escaping () async throws -> ActionResult,
            expectationBeforeCompletion: (() -> Void)? = nil,
            completeWith: (() -> Swift.Result<Result, Error>)? = nil,
            cascade: () -> CascadePolicy,
            expectationAfterCompletion: ((ActionResult) -> Void)? = nil,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws {
            try await withMainSerialExecutor {
                let task = Task { try await process() }
                for _ in 0 ..< yieldCount {
                    await Task.yield()
                }
                expectationBeforeCompletion?()

                // Complete the primary operation
                switch completeWith?() {
                case let .success(result):
                    complete(with: result, at: index, file: file, line: line)
                case let .failure(error):
                    complete(with: error, at: index, file: file, line: line)
                case .none:
                    break
                }

                // Complete cascading operations
                await Task.yield()
                for (offset, completion) in cascade.continuations.enumerated() {
                    completion.apply(to: self, at: index + offset + 1)
                    await Task.yield()
                }

                let value = try await task.value
                await Task.yield()
                expectationAfterCompletion?(value)
            }
        }

        func asyncWithCascade<Result: Sendable>(
            yieldCount: Int = 1,
            at index: Int = 0,
            process: @escaping () -> Void,
            expectationBeforeCompletion: (() -> Void)? = nil,
            completeWith: (() -> Swift.Result<Result, Error>)? = nil,
            cascade: () -> CascadePolicy,
            expectationAfterCompletion: (() -> Void)? = nil,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws {
            try await asyncWithCascade(
                yieldCount: yieldCount,
                at: index,
                process: process,
                expectationBeforeCompletion: expectationBeforeCompletion,
                completeWith: completeWith,
                cascade: cascade,
                expectationAfterCompletion: { (_: Void) in
                    expectationAfterCompletion?()
                },
                file: file,
                line: line
            )
        }
    #endif
}
