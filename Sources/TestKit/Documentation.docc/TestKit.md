# ``TestKit``

A comprehensive testing utility package designed to simplify and enhance the process of writing unit tests in Swift.

## Overview

TestKit provides utilities and extensions to streamline creation and verification of unit tests with the Swift Testing framework. It includes async test doubles, memory leak detection, fluent expectation APIs, change tracking, UI presentation testing, and more.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:MigratingToScenarioAPI>

### Async Test Doubles

Control and verify asynchronous operations with test spies.

- ``AsyncSpy``
- ``AsyncSpy/ScenarioStep``
- ``AsyncSpy/CascadeCompletion``
- ``AsyncSpy/CascadePolicy``
- ``NonBlockingAsyncSpy``

### Fluent Expectations

Verify async operation results and property changes with chainable APIs.

- ``ExpectationTracker``
- ``ChangeTracker``
- ``Testing/Test/expect(_:sourceLocation:)->ExpectationTracker<T,E>``
- ``Testing/Test/expect(_:sourceLocation:)->ExpectationTracker<T,Never>``
- ``Testing/Test/trackChange(of:in:sourceLocation:)``

### Memory Leak Tracking

Ensure instances are properly deallocated to prevent potential memory leaks.

- ``TeardownTrackingTrait``

### Async Process Control

- ``Testing/Test/async(yieldCount:process:onBeforeCompletion:onAfterCompletion:)``

### Observation Testing

- ``ObservationSpy``

### JSON Utilities

Create and compare JSON data for testing.

- ``Testing/Test/makeJSON(withObjects:)``
- ``Testing/Test/makeJSON(withObject:)``
- ``Testing/Test/makeJSON(withArray:)``
- ``Testing/Test/assertEqual(_:_:sourceLocation:)``

### Localization Testing

- ``localized(_:in:sourceLocation:)``
- ``localized(_:in:table:sourceLocation:)``
- ``assertLocalizedKeyAndValuesExist(in:_:sourceLocation:)``

### UI Testing Utilities

- ``InstantAnimationStub``
- ``PresentationSpy``

### Additional Utilities

- ``Foundation/UUID/incrementing()``
- ``ModelPresentation``
- ``SequentialUUIDGenerationTrait``
