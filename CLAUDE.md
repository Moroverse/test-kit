# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TestKit is a comprehensive Swift testing utilities library designed to simplify and enhance unit testing with Swift Testing framework. It provides utilities for memory leak detection, asynchronous testing, UI presentation verification, and testing helpers.

## Development Commands

### Building and Testing
```bash
# Build the package
swift build

# Run tests
swift test

# Run tests for specific platform
swift test --destination "generic/platform=iOS"
swift test --destination "generic/platform=macOS"
```

### Documentation Generation
```bash
# Generate documentation for iOS (default)
bash scripts/package_docc.sh

# Generate documentation for multiple platforms
bash scripts/package_docc.sh iOS macOS

# Build documentation directly with target name
bash scripts/docc.sh TestKit iOS macOS
```

## Architecture

### Core Components

**Test Doubles (`Sources/TestKit/Test Doubles/`)**
- `AsyncSpy`: Advanced spy for asynchronous operations with controlled timing and completion. Supports parameter tracking, multiple completions, and fluent testing API. **Now conditionally compatible with both Swift Testing and XCTest frameworks.**

**Testing Utilities (`Sources/TestKit/Testing/`)**
- `Test+Expect.swift`: Expectation tracking for async operations with fluent interface
- `Test+TrackMemoryLeaks.swift`: Memory leak detection using weak references and teardown tracking
- `Test+Process.swift`: Process execution utilities
- `Test+JSON.swift`: JSON creation and comparison utilities
- `Test+Persistance.swift`: Persistence testing helpers
- `Test+TrackChange.swift`: State change tracking utilities

**UI Testing (`Sources/TestKit/UI/`)**
- `PresentationSpy`: Method swizzling-based spy for UIViewController presentation/dismissal tracking
- `InstantAnimationStub`: Animation control for deterministic UI testing
- `ModelPresentation`: UI presentation state management

**Common Utilities (`Sources/TestKit/Common/`)**
- `ChangeTracker`: Generic change tracking implementation
- `ExpectationTracker`: Async expectation management

**Helpers (`Sources/TestKit/Helpers/`)**
- `UUID+Incrementing.swift`: Sequential UUID generation for deterministic tests
- `LocalizationHelpers.swift`: Localization validation utilities

### Key Dependencies
- `swift-custom-dump`: For enhanced debugging output
- `swift-concurrency-extras`: For advanced concurrency utilities
- `Mockable` (test target only): For mock generation

### Testing Patterns

**AsyncSpy Framework Compatibility:**
```swift
// Works automatically with both Swift Testing and XCTest
let spy = AsyncSpy<User>()

// Swift Testing - uses sourceLocation parameter
try await spy.async {
    await sut.load()
} completeWith: {
    .success(user)
}

// XCTest - uses file/line parameters automatically  
// (same API, different internal implementation)
```

**Memory Leak Testing:**
```swift
@Test("No memory leaks", .teardownTracking())
func testNoLeaks() async throws {
    let sut = MyViewModel()
    await Test.trackForMemoryLeaks(sut)
}
```

**AsyncSpy Usage:**
```swift
extension AsyncSpy: MyProtocol where Result == MyType {
    func myMethod(_ param: String) async throws -> MyType {
        try await perform(param)
    }
}
```

**Expectation Testing:**
```swift
await Test.expect { try await viewModel.fetchItems() }
    .toCompleteWith { .success(["item1", "item2"]) }
    .when { await spy.completeWith(.success(data)) }
    .execute()
```

### Framework Compatibility
- **Swift Testing**: Full support with `SourceLocation` and `Issue.record()` 
- **XCTest/Fallback**: Automatic fallback using `StaticString file, UInt line` parameters and `assertionFailure()`
- Conditional compilation ensures seamless operation in both environments

### Platform Support
- iOS 17.0+
- macOS 14.0+
- macCatalyst 17.0+
- Swift 6.2+

### Test Organization
- Tests are located in `Tests/TestKitTests/`
- Each major component has corresponding test files
- Uses Swift Testing framework with traits for specialized testing scenarios (`.teardownTracking()`, `.sequentialUUIDGeneration()`)