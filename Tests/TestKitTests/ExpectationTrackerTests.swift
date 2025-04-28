// ExpectationTrackerTests.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-04-06 10:39 GMT.

import Foundation
import Testing

private enum TestError: Error, Equatable {
    case testError
    case anotherError
}

private protocol NetworkService: Sendable {
    func getData() async throws -> Data
}

private actor MockNetworkService: NetworkService {
    var completionHandler: ((Result<Data, Error>) -> Void)?

    func getData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.completionHandler = { result in
                switch result {
                case let .success(data):
                    continuation.resume(returning: data)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func complete(with result: Result<Data, Error>) {
        completionHandler?(result)
    }
}

private final class ViewModel: @unchecked Sendable {
    private let networkService: NetworkService
    @MainActor private(set) var isLoading = false

    init(networkService: NetworkService) {
        self.networkService = networkService
    }

    func fetchItems() async throws -> [String] {
        await MainActor.run { isLoading = true }
        defer {
            Task { @MainActor in self.isLoading = false }
        }

        let data = try await networkService.getData()
        let items = String(data: data, encoding: .utf8)?.components(separatedBy: ",") ?? []
        return items
    }
}

private actor CallCollector {
    var calls: [String] = []
    func record(_ call: String) {
        calls.append(call)
    }
}

@Suite("ExpectationTracker Tests", .teardownTracking())
struct ExpectationTrackerTests {
    @Test("expect tracks async operation")
    func testExpectTracksSuccessfulAsyncOperation() async throws {
        let networkService = MockNetworkService()
        await Test.trackForMemoryLeaks(networkService)

        let viewModel = ViewModel(networkService: networkService)
        await Test.trackForMemoryLeaks(viewModel)

        let expectedItems: [String] = ["Item1", "Item2"]
        let data = expectedItems.joined(separator: ",").data(using: .utf8)!

        let callCollector = CallCollector()

        await Test.expect {
            await callCollector.record("action starts")
            return try await viewModel.fetchItems()
        }
        .toCompleteWith {
            await callCollector.record("Completion handler called")
            return .success(expectedItems)
        }
        .when {
            await callCollector.record("action completes")
            return await networkService.complete(with: .success(data))
        }
        .execute()

        #expect(await viewModel.isLoading == false)
        #expect(await callCollector.calls == ["Completion handler called", "action starts", "action completes"])
    }
}
