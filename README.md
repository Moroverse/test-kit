# TestKit

A comprehensive Swift testing utilities library designed to simplify and enhance unit testing with Swift Testing framework.

## Features

- **Memory Leak Detection**: Track objects and verify proper deallocation
- **Asynchronous Testing**: Control timing and verify state changes in async operations
- **UI Presentation Testing**: Verify view controller presentation and dismissal
- **Sequential UUIDs**: Generate predictable UUIDs for deterministic tests
- **Expectation Testing**: Verify asynchronous operation results
- **Localization Testing**: Validate localization strings exist

## Installation

Add this package to your Swift package dependencies:

```swift
.package(url: "https://github.com/moroverse/test-kit.git", from: "0.3.1")
```

Then add the dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["TestKit"]
)
```

## Usage Examples

### Memory Leak Tracking

```swift
@Test("No memory leaks", .teardownTracking())
func testNoLeaks() async throws {
    let sut = MyViewModel()
    await Test.trackForMemoryLeaks(sut)
    // Test will fail if sut is not deallocated
}
```

### AsyncSpy

```swift
@Test("Async operation succeeds")
func testAsyncSuccess() async throws {
    let spy = AsyncSpy<String>()
    let sut = MyViewModel(service: spy)
    
    try await spy.async {
        await sut.loadData()
    } expectationBeforeCompletion: {
        #expect(sut.isLoading == true)
    } completeWith: {
        .success("Result")
    } expectationAfterCompletion: { _ in
        #expect(sut.isLoading == false)
        #expect(sut.data == "Result")
    }
}
```

### Expectation Tracking

```swift
    @Test("ViewModel fetches data successfully")
    func testFetchDataSuccess() async throws {
        let spy = MockNetworkService()
        let viewModel = ViewModel(networkService: spy)
        let data = ["item1", "item2"].joined(separator: ",").data(using: .utf8)!
        
        await Test.expect { try await viewModel.fetchItems() }
            .toCompleteWith { .success(["item1", "item2"]) }
            .when { await spy.completeWith(.success(data)) }
            .execute()
    }

    @Test("ViewModel handles fetch error")
    func testFetchDataError() async throws {
        let viewModel = ViewModel(networkService: FailingNetworkService())
        let error = NetworkError.connectionLost
        
        await Test.expect { try await viewModel.fetchItems() }
            .toCompleteWith { .failure(error) }
            .when { await spy.completeWith(.failure(error)) }
            .execute()
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

### Sequential UUIDs

```swift
@Test("Sequential UUID generation", .sequentialUUIDGeneration())
func testSequentialUUIDs() async throws {
    await UUID.reset()
    
    let uuid1 = try await UUID.incrementing()
    #expect(uuid1.uuidString == "00000000-0000-0000-0000-000000000000")
    
    let uuid2 = try await UUID.incrementing()
    #expect(uuid2.uuidString == "00000000-0000-0000-0000-000000000001")
}
```

## Requirements

- iOS 17.0+, macOS 14.0+
- Swift 6.1+
- Xcode 15.0+

## Dependencies

- [swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump)
- [swift-concurrency-extras](https://github.com/pointfreeco/swift-concurrency-extras)

## License

MIT License - See [LICENSE.txt](LICENSE.txt) for details.
