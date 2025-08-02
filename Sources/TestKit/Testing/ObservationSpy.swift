//
//  ObservationSpy.swift
//  test-kit
//
//  Created by Daniel Moro on 2. 8. 2025..
//

import Observation
import Foundation

/// An actor class that observes changes emitted by an `Observations` sequence
/// and records them for later inspection. Designed for use in testing to spy
/// on values produced by observed objects or publishers.
///
/// This class leverages Swift Concurrency and the new Observation framework,
/// available on macOS 26.0, iOS 26.0, and later platforms.
///
/// The actor ensures that all access to the underlying state (`changes`) is
/// performed in a thread-safe manner. Observed values are collected in order,
/// and utility methods are provided for retrieving those values and waiting for
/// a desired count of changes.
///
/// - Important: The generic type `T` must conform to `Sendable` for safe use
///   in concurrent contexts.
///
/// - Parameters:
///   - T: The type of values emitted by the observed sequence.
///
/// - Usage:
///     ```swift
///     let spy = ObservationSpy(observation: observations)
///     let values = try await spy.waitForChanges(count: 2)
///     ```
///
/// - Note: The observation begins as soon as the actor is initialized, and is
///   cancelled when the actor is deinitialized. The observation is performed
///   on a background task to ensure it does not block the main thread.
///
/// - SeeAlso: `Observations`, `Observation` framework
@available(macOS 26.0, iOS 26.0, *)
public actor ObservationSpy<T: Sendable> {
    private struct TimeoutError: Error {}
    private var changes: [T] = []
    private var observationTask: Task<Void, Never>?

    /// Initializes an `ObservationSpy` actor that begins observing the provided
    /// `Observations` sequence immediately on a background task.
    ///
    /// - Parameter observation: An `Observations<T, Never>` sequence whose emitted
    ///   values will be recorded for later retrieval and inspection.
    ///
    /// Upon initialization, the actor spawns a new background task that listens
    /// asynchronously for values emitted by the `observation` sequence. Each
    /// received value is stored in order, enabling later retrieval using
    /// `getChanges()` or `waitForChanges(count:timeout:)`. The observation
    /// continues until the actor is deinitialized or the underlying task is
    /// cancelled.
    ///
    /// - Important: The observation task is managed internally and will be
    ///   cancelled automatically when the actor is deinitialized. Care should
    ///   be taken to avoid memory leaks by ensuring references to the actor
    ///   are released when observation is no longer needed.
    ///
    /// - Note: This initializer is actor-isolated and thread-safe. It is designed
    ///   primarily for use in testing, where capturing and asserting on observed
    ///   values is required.
    public init(observation: Observations<T, Never>) {
        // We need to create a task that captures the actor's isolated context
        let task = Task { [weak self] in
            guard let self = self else { return }

            // Now we're inside an async context that can access the actor
            await self.startObserving(observation)
        }

        // Store the task reference using an isolated async context
        Task { [weak self] in
            await self?.setTask(task)
        }
    }

    // Isolated method to store the task reference
    private func setTask(_ task: Task<Void, Never>) {
        self.observationTask = task
    }

    // Isolated method to start observing
    private func startObserving(_ observation: Observations<T, Never>) async {
        for await value in observation {
            changes.append(value)
        }
    }

    // Public method to get current changes
    func getChanges() -> [T] {
        changes
    }

    /// Waits asynchronously for a specified number of observed changes, or throws if the timeout elapses.
    ///
    /// This method suspends execution until at least `count` values have been observed and recorded, or until the given `timeout` interval expires.
    /// It polls the changes array in short intervals and throws an error if the timeout is reached before the requested number of changes are observed.
    ///
    /// - Parameters:
    ///   - count: The minimum number of changes to wait for.
    ///   - timeout: The maximum time interval (in seconds) to wait for the specified count of changes. Defaults to 0.01 seconds.
    ///
    /// - Returns: An array containing all values observed up to the point when the desired count is reached.
    ///
    /// - Throws: An error if the timeout interval elapses before the required number of changes have been observed.
    ///
    /// - Note: The returned array may contain more than `count` values if additional values are observed while waiting.
    ///
    /// - Important: Because this method uses polling and a fixed sleep interval, it is not suitable for production use, but is designed for testing scenarios where rapid, deterministic waits are required.
    public func waitForChanges(count: Int, timeout: TimeInterval = 0.01) async throws -> [T] {
        let deadline = Date().addingTimeInterval(timeout)

        while changes.count < count {
            if Date() > deadline {
                throw TimeoutError()
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        return getChanges()
    }

    deinit {
        observationTask?.cancel()
    }
}
