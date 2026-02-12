# Migrating to the Scenario API

Replace the deprecated multi-closure AsyncSpy methods with the imperative scenario API.

## Overview

The `async {}`, `synchronous {}`, `asyncWithCascade {}`, and `synchronousWithCascade {}` methods on `AsyncSpy` are deprecated. The new ``AsyncSpy/scenario(yieldCount:_:sourceLocation:)`` method replaces all of them with a single, imperative interface where you write test phases in natural order with inline assertions.

### Why Migrate?

The old multi-closure API required you to split your test logic across several trailing closures (`process:`, `expectationBeforeCompletion:`, `completeWith:`, `expectationAfterCompletion:`). This made tests harder to read and reason about, especially when the execution order differed from the source order.

The scenario API fixes this:
- **Natural ordering** — write steps top to bottom in execution order
- **Inline assertions** — place `#expect` calls between steps instead of in separate closures
- **Composable** — mix triggers, completions, failures, and cascades freely
- **Single entry point** — one method replaces four deprecated ones

## Migration Reference

### Basic Async Operation

**Before:**
```swift
try await spy.async {
    await sut.load()
} expectationBeforeCompletion: {
    #expect(sut.isLoading)
} completeWith: {
    .success(data)
} expectationAfterCompletion: { _ in
    #expect(!sut.isLoading)
    #expect(sut.data == data)
}
```

**After:**
```swift
try await spy.scenario { step in
    await step.trigger { await sut.load() }
    #expect(sut.isLoading)
    await step.complete(with: data)
    #expect(!sut.isLoading)
    #expect(sut.data == data)
}
```

### Error Handling

**Before:**
```swift
try await spy.async {
    await sut.load()
} completeWith: {
    .failure(NetworkError.timeout)
} expectationAfterCompletion: { _ in
    #expect(sut.error is NetworkError)
}
```

**After:**
```swift
try await spy.scenario { step in
    await step.trigger { await sut.load() }
    await step.fail(with: NetworkError.timeout)
    #expect(sut.error is NetworkError)
}
```

### Synchronous Method with Hidden Async

**Before:**
```swift
try await spy.synchronous {
    sut.setFilter(.active)
} completeWith: {
    .success(filteredData)
} expectationAfterCompletion: {
    #expect(sut.items == filteredData)
}
```

**After:**
```swift
try await spy.scenario { step in
    await step.trigger(sync: { sut.setFilter(.active) })
    await step.complete(with: filteredData)
    #expect(sut.items == filteredData)
}
```

Use `trigger(sync:)` when the SUT method is synchronous but internally spawns a `Task` that calls the spy.

### Custom yieldCount

**Before:**
```swift
try await spy.async(yieldCount: 3) {
    await sut.load()
} completeWith: {
    .success(data)
}
```

**After:**
```swift
try await spy.scenario(yieldCount: 3) { step in
    await step.trigger { await sut.load() }
    await step.complete(with: data)
}
```

### Completing at a Specific Index

**Before:**
```swift
try await spy.async(at: 1) {
    await sut.reload()
} completeWith: {
    .success(data)
}
```

**After:**
```swift
try await spy.scenario { step in
    await step.trigger { await sut.reload() }
    await step.complete(with: data, at: 1)
}
```

### Task Cancellation (processAdvance)

**Before:**
```swift
try await spy.async {
    await sut.load()
} processAdvance: { task in
    task.cancel()
} completeWith: {
    .success(data)
}
```

**After:**
```swift
try await spy.scenario { step in
    let task = await step.trigger { await sut.load() }
    task.cancel()
    await step.complete(with: data)
}
```

The `trigger` method returns the underlying `Task`, which you can cancel or inspect.

### Cascading Operations

**Before:**
```swift
try await spy.asyncWithCascade {
    await sut.deleteAndReload(item)
} completeWith: {
    .success(())
} cascade: {
    .init([.success(updatedList)])
} expectationAfterCompletion: { _ in
    #expect(sut.items == updatedList)
}
```

**After:**
```swift
try await spy.scenario { step in
    await step.trigger { await sut.deleteAndReload(item) }
    await step.complete(with: ())
    await step.cascade(.success(updatedList))
    #expect(sut.items == updatedList)
}
```

### Cascading with Skip (Error Path)

**Before:**
```swift
try await spy.asyncWithCascade {
    await sut.deleteAndReload(item)
} completeWith: {
    .failure(DeleteError.denied)
} cascade: {
    .init([.skip])
} expectationAfterCompletion: { _ in
    #expect(sut.error is DeleteError)
}
```

**After:**
```swift
try await spy.scenario { step in
    await step.trigger { await sut.deleteAndReload(item) }
    await step.fail(with: DeleteError.denied)
    await step.cascade(.skip)
    #expect(sut.error is DeleteError)
}
```

Use `.skip` when the cascading call never fires (e.g., because the primary operation failed).

### Multiple Triggers

The scenario API naturally supports multiple triggers in a single scenario:

```swift
try await spy.scenario { step in
    await step.trigger { await processor1.process() }
    await step.trigger { await processor2.process() }
    await step.complete(with: result1, at: 0)
    await step.complete(with: result2, at: 1)
}
```

## Quick Reference Table

| Old API | New API |
|---------|---------|
| `spy.async { process } completeWith: { .success(val) }` | `spy.scenario { step in step.trigger { process }; await step.complete(with: val) }` |
| `spy.synchronous { process } completeWith: { .success(val) }` | `spy.scenario { step in step.trigger(sync: { process }); await step.complete(with: val) }` |
| `expectationBeforeCompletion: { ... }` | Inline `#expect(...)` after `trigger`, before `complete` |
| `expectationAfterCompletion: { ... }` | Inline `#expect(...)` after `complete` |
| `completeWith: { .failure(err) }` | `await step.fail(with: err)` |
| `processAdvance: { task in task.cancel() }` | `let task = await step.trigger { ... }; task.cancel()` |
| `spy.asyncWithCascade { ... } cascade: { .init([...]) }` | `await step.cascade(.success(val))` after `complete` |
| `CascadePolicy([.skip])` | `await step.cascade(.skip)` |
| `async(yieldCount: 3) { ... }` | `spy.scenario(yieldCount: 3) { step in ... }` |
| `async(at: 1) { ... }` | `await step.complete(with: val, at: 1)` |
