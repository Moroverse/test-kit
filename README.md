# TestKit

A comprehensive Swift testing utilities library designed to simplify and enhance unit testing with the Swift Testing framework.

## Features

- **Async Test Doubles**: `AsyncSpy` and `NonBlockingAsyncSpy` for controlling and verifying async operations
- **Memory Leak Detection**: Track objects and verify proper deallocation with `.teardownTracking()`
- **Expectation Tracking**: Fluent API for verifying async operation results
- **Change Tracking**: Verify property mutations with before/after assertions
- **UI Presentation Testing**: Intercept `UIViewController` present/dismiss via method swizzling
- **Sequential UUIDs**: Generate predictable UUIDs for deterministic tests
- **Observation Spying**: Capture and assert on Observation framework changes
- **Core Data Testing**: In-memory persistent containers via test traits

## Installation

Add this package to your Swift package dependencies:

```swift
.package(url: "https://github.com/moroverse/test-kit.git", from: "0.3.1")
```

Then add the dependency to your test target:

```swift
.testTarget(
    name: "YourTests",
    dependencies: ["TestKit"]
)
```

## Usage Examples

### AsyncSpy

`AsyncSpy` lets you control the timing and results of async operations in tests. Conform it to your protocol, then use the `scenario` API to orchestrate test phases step by step.

```swift
// 1. Conform AsyncSpy to your protocol
extension AsyncSpy: FetchUserProtocol {
    func fetch(by id: Int) async throws -> User {
        try await perform(id)
    }
}

// 2. Write tests with the scenario API
@Test("Verifies loading state during fetch")
@MainActor
func testLoadingState() async throws {
    let spy = AsyncSpy()
    let sut = UserViewModel(service: spy)

    try await spy.scenario { step in
        await step.trigger { await sut.fetch(by: 1) }
        #expect(sut.isLoading)
        await step.complete(with: User(id: 1, name: "Alice"))
        #expect(!sut.isLoading)
        #expect(sut.user?.name == "Alice")
    }

    #expect(spy.callCount == 1)
    #expect(spy.params(at: 0).params[0] as? Int == 1)
}
```

### Memory Leak Tracking

```swift
@Test("No memory leaks", .teardownTracking())
func testNoLeaks() async throws {
    let sut = MyViewModel()
    await Test.trackForMemoryLeaks(sut)
    // Test will fail if sut is not deallocated after the test
}
```

### Expectation Tracking

```swift
@Test("ViewModel fetches data successfully")
func testFetchDataSuccess() async throws {
    let spy = MockNetworkService()
    let viewModel = ViewModel(networkService: spy)

    await Test.expect { try await viewModel.fetchItems() }
        .toCompleteWith { .success(["item1", "item2"]) }
        .when { await spy.completeWith(.success(data)) }
        .execute()
}
```

### Change Tracking

```swift
@Test("Filter updates displayed items")
func testFilterChange() async {
    let sut = ItemListViewModel()

    await Test.trackChange(of: \.displayedItems, in: sut)
        .givenInitialState { sut.items = [item1, item2, item3] }
        .expectInitialValue { [item1, item2, item3] }
        .whenChanging { sut.filter = .active }
        .expectFinalValue { [item1] }
        .execute()
}
```

### Sequential UUIDs

```swift
@Test("Sequential UUID generation", .sequentialUUIDGeneration())
func testSequentialUUIDs() async throws {
    let uuid1 = try await UUID.incrementing()
    #expect(uuid1.uuidString == "00000000-0000-0000-0000-000000000000")

    let uuid2 = try await UUID.incrementing()
    #expect(uuid2.uuidString == "00000000-0000-0000-0000-000000000001")
}
```

### UI Presentation Testing

```swift
@Test("Presents view controller", .serialized)
@MainActor
func testPresentation() async throws {
    let spy = PresentationSpy()
    let dummyVC = UIViewController()
    let presenter = UIViewController()

    presenter.present(dummyVC, animated: true)

    #expect(spy.presentations.count == 1)
    #expect(spy.presentations[0].controller === dummyVC)
    #expect(spy.presentations[0].state == .presented)
}
```

## Requirements

- iOS 17.0+, macOS 14.0+, macCatalyst 17.0+
- Swift 6.2+
- Xcode 16.0+

## Dependencies

- [swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump)
- [swift-concurrency-extras](https://github.com/pointfreeco/swift-concurrency-extras)

## License

MIT License - See [LICENSE.txt](LICENSE.txt) for details.

[Documentation]: https://moroverse.github.io/test-kit

