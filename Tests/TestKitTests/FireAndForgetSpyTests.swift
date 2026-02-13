// FireAndForgetSpyTests.swift
// Copyright (c) 2026 Moroverse
// Created by Daniel Moro on 2026-02-13 10:00 GMT.

import Foundation
import Testing
import TestKit

private struct User: Sendable, Equatable {
    let id: Int
    let name: String
}

private struct TestError: Error {}

@MainActor
private protocol ServiceProtocol {
    func loadUser(id: Int) async throws -> User
    func deleteUser(id: Int) async throws
}

extension FireAndForgetSpy: ServiceProtocol {
    fileprivate func loadUser(id: Int) async throws -> User {
        try await perform(id, tag: "loadUser")
    }

    fileprivate func deleteUser(id: Int) async throws {
        try await perform(id, tag: "deleteUser")
    }
}

@MainActor
private class UserViewModel {
    let service: ServiceProtocol
    var isLoading = false
    var user: User?
    var error: Error?

    init(service: ServiceProtocol) {
        self.service = service
    }

    func loadUser(id: Int) {
        isLoading = true
        error = nil
        Task {
            do {
                user = try await service.loadUser(id: id)
                isLoading = false
            } catch {
                self.error = error
                isLoading = false
            }
        }
    }
}

@MainActor
private class CascadingViewModel {
    let service: ServiceProtocol
    var deleteCompleted = false
    var reloadedUser: User?
    var error: Error?

    init(service: ServiceProtocol) {
        self.service = service
    }

    func deleteAndReload(userId: Int) {
        Task {
            do {
                try await service.deleteUser(id: userId)
                deleteCompleted = true
                reloadedUser = try await service.loadUser(id: userId)
            } catch {
                self.error = error
            }
        }
    }
}

@Suite("FireAndForgetSpy Tests")
@MainActor
struct FireAndForgetSpyTests {
    @Test("Scenario completes with success")
    func scenarioCompletesWithSuccess() async throws {
        let spy = FireAndForgetSpy()
        let sut = UserViewModel(service: spy)
        let expectedUser = User(id: 1, name: "Alice")

        try await spy.scenario { step in
            await step.trigger { sut.loadUser(id: 1) }
            #expect(sut.isLoading)
            await step.complete(with: expectedUser)
            #expect(!sut.isLoading)
            #expect(sut.user == expectedUser)
        }

        #expect(spy.callCount == 1)
        #expect(spy.requests[0].params[0] as? Int == 1)
        #expect(spy.callCount(forTag: "loadUser") == 1)
    }

    @Test("Scenario completes with failure")
    func scenarioCompletesWithFailure() async throws {
        let spy = FireAndForgetSpy()
        let sut = UserViewModel(service: spy)

        try await spy.scenario { step in
            await step.trigger { sut.loadUser(id: 999) }
            #expect(sut.isLoading)
            await step.fail(with: TestError())
            #expect(!sut.isLoading)
            #expect(sut.error is TestError)
            #expect(sut.user == nil)
        }
    }

    @Test("Scenario cancel terminates pending requests")
    func scenarioCancelTerminatesPendingRequests() async throws {
        let spy = FireAndForgetSpy()
        let sut = UserViewModel(service: spy)

        try await spy.scenario { step in
            await step.trigger { sut.loadUser(id: 1) }
            try await step.cancel()
            let result = try await spy.result(at: 0)
            #expect(result == .failure)
            #expect(sut.error is CancellationError)
        }
    }

    @Test("Scenario completes void operation")
    func scenarioCompletesVoidOperation() async throws {
        let spy = FireAndForgetSpy()
        var deleted = false

        try await spy.scenario { step in
            await step.trigger {
                Task { [spy] in
                    try await spy.deleteUser(id: 42)
                    deleted = true
                }
            }
            await step.complete(with: ())
        }

        let result = try await spy.result(at: 0)
        #expect(result == .success)
        #expect(deleted)
        #expect(spy.callCount(forTag: "deleteUser") == 1)
    }

    @Test("Scenario with cascade completes chained operations")
    func scenarioWithCascade() async throws {
        let spy = FireAndForgetSpy()
        let sut = CascadingViewModel(service: spy)
        let reloadedUser = User(id: 1, name: "Alice")

        try await spy.scenario { step in
            await step.trigger { sut.deleteAndReload(userId: 1) }
            await step.complete(with: ())
            await step.cascade(.success(reloadedUser))
        }

        #expect(spy.callCount == 2)
        #expect(sut.deleteCompleted)
        #expect(sut.reloadedUser == reloadedUser)
    }

    @Test("Scenario with cascade skip on failure")
    func scenarioWithCascadeSkip() async throws {
        let spy = FireAndForgetSpy()
        let sut = CascadingViewModel(service: spy)

        try await spy.scenario { step in
            await step.trigger { sut.deleteAndReload(userId: 1) }
            await step.fail(with: TestError())
            await step.cascade(.skip)
        }

        #expect(spy.callCount == 1)
        #expect(sut.error is TestError)
        #expect(!sut.deleteCompleted)
        #expect(sut.reloadedUser == nil)
    }

    @Test("Scenario auto-cancels pending requests after body")
    func scenarioAutoCancels() async throws {
        let spy = FireAndForgetSpy()
        let sut = UserViewModel(service: spy)

        try await spy.scenario { step in
            await step.trigger { sut.loadUser(id: 1) }
            // Don't complete — scenario should auto-cancel via cancelPendingRequests()
        }

        let result = try await spy.result(at: 0)
        #expect(result == .failure)
        #expect(sut.error is CancellationError)
    }

    @Test("Scenario with custom yieldCount")
    func scenarioWithCustomYieldCount() async throws {
        let spy = FireAndForgetSpy()
        let sut = UserViewModel(service: spy)
        let expectedUser = User(id: 1, name: "Alice")

        try await spy.scenario(yieldCount: 3) { step in
            await step.trigger { sut.loadUser(id: 1) }
            await step.complete(with: expectedUser)
        }

        #expect(sut.user == expectedUser)
    }

    @Test("Scenario verifies result state for success")
    func scenarioVerifiesResultStateForSuccess() async throws {
        let spy = FireAndForgetSpy()
        let sut = UserViewModel(service: spy)

        try await spy.scenario { step in
            await step.trigger { sut.loadUser(id: 1) }
            await step.complete(with: User(id: 1, name: "Alice"))
        }

        let result = try await spy.result(at: 0)
        #expect(result == .success)
    }

    @Test("Scenario verifies result state for failure")
    func scenarioVerifiesResultStateForFailure() async throws {
        let spy = FireAndForgetSpy()
        let sut = UserViewModel(service: spy)

        try await spy.scenario { step in
            await step.trigger { sut.loadUser(id: 1) }
            await step.fail(with: TestError())
        }

        let result = try await spy.result(at: 0)
        #expect(result == .failure)
    }
}
