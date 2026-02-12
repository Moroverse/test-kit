# Getting Started with TestKit

Add TestKit to your project and write your first async test.

## Overview

TestKit is a testing utilities library for the Swift Testing framework. It provides async test doubles, memory leak detection, fluent expectation APIs, and more. This guide walks you through installation, setting up your first `AsyncSpy` test, and using the most common utilities.

## Installation

Add TestKit to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/moroverse/test-kit.git", from: "0.3.1")
]
```

Then add it to your test target:

```swift
.testTarget(
    name: "YourTests",
    dependencies: ["TestKit"]
)
```

## Your First AsyncSpy Test

`AsyncSpy` lets you control the timing and results of async operations in tests. The typical workflow is:

1. Define a protocol for the async operation you want to test.
2. Conform `AsyncSpy` to that protocol by calling `perform`.
3. Use the `scenario` API to orchestrate test phases step by step.

### Step 1: Define a Protocol

```swift
protocol UserService {
    func fetchUser(by id: Int) async throws -> User
}
```

### Step 2: Conform AsyncSpy

```swift
import TestKit

extension AsyncSpy: UserService {
    func fetchUser(by id: Int) async throws -> User {
        try await perform(id)
    }
}
```

The `perform` method records the call parameters and suspends until you explicitly complete it in your test.

### Step 3: Write the Test

```swift
import Testing
import TestKit

@Suite("UserViewModel Tests")
@MainActor
struct UserViewModelTests {

    @Test("Shows loading state during fetch")
    func loadingState() async throws {
        let spy = AsyncSpy()
        let sut = UserViewModel(service: spy)

        try await spy.scenario { step in
            // Trigger the async operation
            await step.trigger { await sut.fetchUser(by: 1) }

            // Assert pre-completion state
            #expect(sut.isLoading)

            // Complete the spy with a result
            await step.complete(with: User(id: 1, name: "Alice"))

            // Assert post-completion state
            #expect(!sut.isLoading)
            #expect(sut.user?.name == "Alice")
        }

        // Verify call parameters
        #expect(spy.callCount == 1)
        #expect(spy.params(at: 0).params[0] as? Int == 1)
    }
}
```

The `scenario` API wraps execution in `withMainSerialExecutor` for deterministic scheduling. Each call to `trigger` launches the SUT's async operation, then yields to let it reach the spy's suspension point. You write assertions inline between phases.

### Testing Error Paths

Use `step.fail(with:)` to test error handling:

```swift
@Test("Shows error on fetch failure")
func fetchError() async throws {
    let spy = AsyncSpy()
    let sut = UserViewModel(service: spy)

    try await spy.scenario { step in
        await step.trigger { await sut.fetchUser(by: 1) }
        await step.fail(with: NetworkError.timeout)
        #expect(sut.error is NetworkError)
        #expect(sut.user == nil)
    }
}
```

### Testing Synchronous Methods with Hidden Async

When the SUT method is synchronous but internally spawns a `Task`, use `trigger(sync:)`:

```swift
@Test("Sync method triggers async work")
func syncTrigger() async throws {
    let spy = AsyncSpy()
    let sut = UserViewModel(service: spy)

    try await spy.scenario(yieldCount: 3) { step in
        await step.trigger(sync: { sut.refresh() })
        await step.complete(with: User(id: 1, name: "Bob"))
        #expect(sut.user?.name == "Bob")
    }
}
```

Increase `yieldCount` when the SUT has multiple suspension points before reaching the spy.

### Testing Cascading Operations

When one operation triggers a follow-up (e.g., delete then reload), use `cascade`:

```swift
@Test("Delete triggers reload")
func deleteAndReload() async throws {
    let spy = AsyncSpy()
    let sut = ItemListViewModel(service: spy)

    try await spy.scenario { step in
        await step.trigger { await sut.deleteAndReload(item) }
        await step.complete(with: ())              // completes delete
        await step.cascade(.success(updatedList))   // completes reload
        #expect(sut.items == updatedList)
    }
}
```

## Memory Leak Detection

Use the `.teardownTracking()` trait and `trackForMemoryLeaks` to verify objects are deallocated:

```swift
@Test("No memory leaks", .teardownTracking())
func noLeaks() async throws {
    let sut = MyViewModel()
    await Test.trackForMemoryLeaks(sut)
    // Test fails if sut is still alive after the test completes
}
```

> Important: The `.teardownTracking()` trait is required. Without it, `trackForMemoryLeaks` will record a test issue.

## Expectation Tracking

The `Test.expect {}` API provides a fluent way to verify async results:

```swift
@Test("Fetches items successfully")
func fetchItems() async throws {
    let spy = MockNetworkService()
    let viewModel = ViewModel(networkService: spy)

    await Test.expect { try await viewModel.fetchItems() }
        .toCompleteWith { .success(["item1", "item2"]) }
        .when { await spy.completeWith(.success(data)) }
        .execute()
}
```

The chain works as follows:
- `expect {}` — wraps the async action
- `toCompleteWith {}` — specifies the expected `Result`
- `when {}` — defines an event that triggers before the action completes
- `execute()` — runs the expectation

## Change Tracking

Track property mutations with `Test.trackChange(of:in:)`:

```swift
@Test("Filter updates displayed items")
func filterChange() async {
    let sut = ItemListViewModel()

    await Test.trackChange(of: \.displayedItems, in: sut)
        .givenInitialState { sut.items = [item1, item2, item3] }
        .expectInitialValue { [item1, item2, item3] }
        .whenChanging { sut.filter = .active }
        .expectFinalValue { [item1] }
        .execute()
}
```

## Sequential UUIDs

Generate predictable UUIDs for deterministic tests using the `.sequentialUUIDGeneration()` trait:

```swift
@Test("Generates sequential UUIDs", .sequentialUUIDGeneration())
func sequentialUUIDs() async throws {
    let uuid1 = try await UUID.incrementing()
    #expect(uuid1.uuidString == "00000000-0000-0000-0000-000000000000")

    let uuid2 = try await UUID.incrementing()
    #expect(uuid2.uuidString == "00000000-0000-0000-0000-000000000001")
}
```

Each test gets its own counter scoped by the trait, so tests don't interfere with each other.
