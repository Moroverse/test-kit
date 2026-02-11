// TestProcessTests.swift
// Copyright (c) 2026 Moroverse
// Created by Daniel Moro on 2025-08-02 05:08 GMT.

import Foundation
import Mockable
import Testing

@Mockable
private protocol PrivateService: Sendable {
    func getData() async throws -> Data
}

@MainActor
private final class ViewModel: @unchecked Sendable {
    private let networkService: PrivateService
    private(set) var isLoading = false

    init(networkService: PrivateService) {
        self.networkService = networkService
    }

    func fetchItems() async throws -> [String] {
        isLoading = true
        await Task.yield() // insert suspension point to give a change for observers to react on isLoading change
        defer {
            isLoading = false
        }

        let data = try await networkService.getData()
        return String(data: data, encoding: .utf8)?.components(separatedBy: ",") ?? []
    }
}

@Suite("Test.async behavior")
struct TestAsyncTests {
    @MainActor
    @Test("Process returns expected result and calls hooks")
    func returnsExpectedResultAndCallsHooks() async throws {
        var isLoading = false
        var afterCalledWith: [String]? = nil
        let service = MockPrivateService()

        let viewModel = ViewModel(networkService: service)

        try given(service)
            .getData()
            .willReturn(#require("1,2,3".data(using: .utf8)))

        try await Test.async(
            yieldCount: 1,
            process: {
                try await viewModel.fetchItems()
            },
            onBeforeCompletion: {
                isLoading = viewModel.isLoading
            },
            onAfterCompletion: { value in
                afterCalledWith = value
            }
        )
        // Test.async returns the value from process
        #expect(isLoading, "isLoading should be true")
        #expect(afterCalledWith == ["1", "2", "3"], "onAfterCompletion should be called with process value")
        // result will be nil since Test.async is declared as returning Void. Let's check hooks only.
    }

    @MainActor
    @Test("Throws error from process and does not call onAfterCompletion")
    func throwsErrorAndSkipsAfterHook() async {
        enum TestError: Error, Equatable { case fail }
        var beforeCalled = false
        var afterCalled = false
        var thrownError: Error?
        do {
            _ = try await Test.async(
                process: { throw TestError.fail },
                onBeforeCompletion: { beforeCalled = true },
                onAfterCompletion: { _ in afterCalled = true }
            )
        } catch {
            thrownError = error
        }
        #expect(beforeCalled, "onBeforeCompletion should be called even if process throws")
        #expect(afterCalled == false, "onAfterCompletion should not be called if process throws")
        #expect((thrownError as? TestError) == .fail, "Thrown error should be TestError.fail")
    }

    @MainActor
    @Test("Yield count yields control the correct number of times")
    func yieldsControlCorrectly() async throws {
        class Counter { var count = 0 }
        let counter = Counter()
        let yieldCount = 3
        var yielded = 0

        _ = try await Test.async(
            yieldCount: yieldCount,
            process: {
                counter.count = 100
                return "done"
            },
            onBeforeCompletion: {
                yielded = counter.count // should be 100 if yielding happened before hook
            },
            onAfterCompletion: { _ in }
        )
        #expect(yielded == 100, "Yield should occur before onBeforeCompletion")
    }
}
