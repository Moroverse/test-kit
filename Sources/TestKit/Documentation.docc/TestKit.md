# ``TestKit``

A comprehensive testing utility package designed to simplify and enhance the process of writing unit tests in Swift.

## Overview

`TestKit` provides a set of utilities and extensions to streamline the creation and verification of unit tests. It includes functionalities for JSON data creation, memory leak tracking, asynchronous process handling, and more. This package is particularly useful for developers looking to improve the reliability and readability of their test code.

## Topics

### JSON Utilities

The JSON utilities allow you to easily create JSON data from dictionaries and arrays, and to assert the equality of JSON data objects.

- ``Testing/Test/makeJSON(withObjects:)``
- ``Testing/Test/makeJSON(withObject:)``
- ``Testing/Test/makeJSON(withArray:)``
- ``Testing/Test/assertEqual(_:_:sourceLocation:)``

### Memory Leak Tracking

Ensure instances are properly deallocated to prevent potential memory leaks.

- ``TeardownTrackingTrait``

### Asynchronous Process Handling

Manage and test asynchronous code more effectively with utilities for performing asynchronous processes, setting expectations, tracking changes, and general-purpose spying.

- ``AsyncSpy``
- ``Testing/Test/async(yieldCount:process:onBeforeCompletion:onAfterCompletion:)``
- ``Testing/Test/expect(_:sourceLocation:)-7ezxb``
- ``Testing/Test/expect(_:sourceLocation:)->ExpectationTracker<T,Never>``
- ``Testing/Test/trackChange(of:in:sourceLocation:)``

Verify that localizetrackChange(of:in:sourceLocation:)``

### Localized keys and values exist.

- ``localized(_:in:sourceLocation:)``
- ``localized(_:in:table:sourceLocation:)``
- ``assertLocalizedKeyAndValuesExist(in:_:sourceLocation:)``

### UI Testing Utilities

Utilities to assist with UI testing.

- ``InstantAnimationStub``
- ``PresentationSpy``

### Additional Utilities

Other helpful utilities for testing.

- ``Foundation/UUID/incrementing()``
- ``ModelPresentation``

