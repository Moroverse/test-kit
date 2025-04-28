// Test+JSON.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2024-08-09 12:46 GMT.

import Foundation
import Testing

public
extension Test {
    /// Creates a JSON data representation from an array of dictionaries.
    ///
    /// - Parameter objects: An array of dictionaries to be converted to JSON data.
    /// - Returns: A `Data` object containing the JSON representation of the input array.
    static func makeJSON(withObjects objects: [[String: Any]]) -> Data {
        // swiftlint:disable:next force_try
        try! JSONSerialization.data(withJSONObject: objects)
    }

    /// Creates a JSON data representation from a dictionary.
    ///
    /// - Parameter object: A dictionary to be converted to JSON data.
    /// - Returns: A `Data` object containing the JSON representation of the input dictionary.
    static func makeJSON(withObject object: [String: Any]) -> Data {
        // swiftlint:disable:next force_try
        try! JSONSerialization.data(withJSONObject: object)
    }

    /// Creates a JSON data representation from an array of strings.
    ///
    /// - Parameter objects: An array of strings to be converted to JSON data.
    /// - Returns: A `Data` object containing the JSON representation of the input array.
    static func makeJSON(withArray objects: [String]) -> Data {
        // swiftlint:disable:next force_try
        try! JSONSerialization.data(withJSONObject: objects)
    }

    /// Asserts that two JSON data objects are equal by comparing their dictionary representations.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side JSON data to compare.
    ///   - rhs: The right-hand side JSON data to compare.
    ///   - sourceLocation: The source location to use in the error message if the assertion fails. Defaults to the current source location.
    /// - Throws: An error if the JSON data cannot be deserialized or if the dictionaries are not equal.
    static func assertEqual(_ lhs: Data, _ rhs: Data, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let lhsDictionary = try #require(
            JSONSerialization.jsonObject(with: lhs, options: []) as? NSDictionary,
            sourceLocation: sourceLocation
        )

        let rhsDictionary = try #require(
            JSONSerialization.jsonObject(with: rhs, options: []) as? NSDictionary,
            sourceLocation: sourceLocation
        )

        #expect(lhsDictionary == rhsDictionary, sourceLocation: sourceLocation)
    }
}
