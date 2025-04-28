// ChangeTracker.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-04-05 06:52 GMT.

import Foundation
import Testing

/// A struct that facilitates tracking changes to a property of an object.
///
/// `ChangeTracker` provides a fluent interface for setting up a sequence of events,
/// expectations, and actions to track changes in a property's value.
///
/// - Note: This struct is designed to be used with the `trackChange` function.
public struct ChangeTracker<SUT, T: Equatable> {
    private let property: KeyPath<SUT, T>
    private let sut: SUT
    private var initialSetup: (() -> Void)?
    private var initialExpectation: (() -> T)?
    private var changeAction: (() -> Void)?
    private var finalExpectation: (() -> T)?
    private let sourceLocation: SourceLocation

    init(
        of property: KeyPath<SUT, T>,
        in sut: SUT,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        self.property = property
        self.sut = sut
        self.sourceLocation = sourceLocation
    }

    /// Sets up the initial state before tracking changes.
    ///
    /// - Parameter setupClosure: A closure to set up the initial state.
    /// - Returns: A new `ChangeTracker` instance with the setup configured.
    public func givenInitialState(_ setupClosure: @escaping () -> Void) -> Self {
        var copy = self
        copy.initialSetup = setupClosure
        return copy
    }

    /// Defines the expected value of the property before the change occurs.
    ///
    /// - Parameter expectation: A closure returning the expected initial value.
    /// - Returns: A new `ChangeTracker` instance with the initial expectation configured.
    public func expectInitialValue(_ expectation: @escaping () -> T) -> Self {
        var copy = self
        copy.initialExpectation = expectation
        return copy
    }

    /// Specifies the action that should cause the property to change.
    ///
    /// - Parameter changeClosure: A closure representing the action that causes the change.
    /// - Returns: A new `ChangeTracker` instance with the change action configured.
    public func whenChanging(_ changeClosure: @escaping () -> Void) -> Self {
        var copy = self
        copy.changeAction = changeClosure
        return copy
    }

    /// Defines the expected value of the property after the change occurs.
    ///
    /// - Parameter expectation: A closure returning the expected final value.
    /// - Returns: A new `ChangeTracker` instance with the final expectation configured.
    public func expectFinalValue(_ expectation: @escaping () -> T) -> Self {
        var copy = self
        copy.finalExpectation = expectation
        return copy
    }

    /// Executes the configured change tracking operation.
    ///
    /// This method performs the setup, checks the initial value,
    /// executes the change action, and checks the final value.
    ///
    public func execute() async {
        if let initialSetup {
            initialSetup()
            await Task.yield()
            await Task.megaYield()
        }

        if let initialExpectation {
            #expect(
                sut[keyPath: property] == initialExpectation(),
                "Initial value did not match expectation",
                sourceLocation: sourceLocation
            )
            await Task.yield()
        }

        if let changeAction {
            changeAction()
            await Task.yield()
        }

        if let finalExpectation {
            #expect(
                sut[keyPath: property] == finalExpectation(),
                "Final value did not match expectation",
                sourceLocation: sourceLocation
            )
        }
    }
}
