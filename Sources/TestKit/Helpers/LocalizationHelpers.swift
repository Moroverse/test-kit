// LocalizationHelpers.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2024-08-09 12:46 GMT.

import Foundation
import Testing

private let missingValue = "!#MISSING_VALUE#!"

/// Returns a localized string for the given key from the specified bundle.
/// - Parameters:
///   - key: The key for a string in the table identified by tableName.
///   - presentationBundle: The bundle containing the localized string.
///   - file: The file name to use in the error message if the key is missing. Defaults to the current file.
///   - line: The line number to use in the error message if the key is missing. Defaults to the current line.
/// - Returns: The localized string for the given key.
public func localized(_ key: String, in presentationBundle: Bundle, sourceLocation: SourceLocation = #_sourceLocation) -> String {
    let value = presentationBundle.localizedString(forKey: key, value: missingValue, table: nil)
    if value == missingValue {
        Issue.record("Missing localized string for key: \(key) in default table", sourceLocation: sourceLocation)
    }
    return value
}

/// Returns a localized string for the given key from the specified bundle and table.
/// - Parameters:
///   - key: The key for a string in the table identified by tableName.
///   - presentationBundle: The bundle containing the localized string.
///   - table: The table containing the localized string.
///   - file: The file name to use in the error message if the key is missing. Defaults to the current file.
///   - line: The line number to use in the error message if the key is missing. Defaults to the current line.
/// - Returns: The localized string for the given key.
public func localized(_ key: String, in presentationBundle: Bundle, table: String, sourceLocation: SourceLocation = #_sourceLocation) -> String {
    let value = presentationBundle.localizedString(forKey: key, value: missingValue, table: table)
    if value == missingValue {
        Issue.record("Missing localized string for key: \(key) in \(table) table", sourceLocation: sourceLocation)
    }
    return value
}

/// Asserts that all localized keys and values exist in the specified bundle and table.
/// - Parameters:
///   - presentationBundle: The bundle containing the localized strings.
///   - table: The table containing the localized strings.
///   - file: The file name to use in the error message if a key is missing. Defaults to the current file.
///   - line: The line number to use in the error message if a key is missing. Defaults to the current line.
public func assertLocalizedKeyAndValuesExist(in presentationBundle: Bundle, _ table: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let localizationBundles = allLocalizationBundles(in: presentationBundle, sourceLocation: sourceLocation)
    let localizedStringKeys = allLocalizedStringKeys(in: localizationBundles, table: table, sourceLocation: sourceLocation)

    for (bundle, localization) in localizationBundles {
        for key in localizedStringKeys {
            let localizedString = bundle.localizedString(forKey: key, value: missingValue, table: table)

            if localizedString == missingValue {
                let language = Locale.current.localizedString(forLanguageCode: localization) ?? ""

                Issue.record("Missing \(language) (\(localization)) localized string for key: '\(key)' in table: '\(table)'", sourceLocation: sourceLocation)
            }
        }
    }
}

private typealias LocalizedBundle = (bundle: Bundle, localization: String)

/// Returns all localization bundles in the specified bundle.
/// - Parameters:
///   - bundle: The bundle containing the localizations.
///   - file: The file name to use in the error message if a bundle is missing. Defaults to the current file.
///   - line: The line number to use in the error message if a bundle is missing. Defaults to the current line.
/// - Returns: An array of tuples containing the localized bundle and its localization.
private func allLocalizationBundles(in bundle: Bundle, sourceLocation: SourceLocation = #_sourceLocation) -> [LocalizedBundle] {
    bundle.localizations.compactMap { localization in
        guard
            let path = bundle.path(forResource: localization, ofType: "lproj"),
            let localizedBundle = Bundle(path: path)
        else {
            Issue.record("Couldn't find bundle for localization: \(localization)", sourceLocation: sourceLocation)
            return nil
        }

        return (localizedBundle, localization)
    }
}

/// Returns all localized string keys in the specified bundles and table.
/// - Parameters:
///   - bundles: The bundles containing the localized strings.
///   - table: The table containing the localized strings.
///   - file: The file name to use in the error message if a key is missing. Defaults to the current file.
///   - line: The line number to use in the error message if a key is missing. Defaults to the current line.
/// - Returns: A set of localized string keys.
private func allLocalizedStringKeys(in bundles: [LocalizedBundle], table: String, sourceLocation: SourceLocation = #_sourceLocation) -> Set<String> {
    bundles.reduce([]) { acc, current in
        guard
            let path = current.bundle.path(forResource: table, ofType: "strings"),
            let strings = NSDictionary(contentsOfFile: path),
            let keys = strings.allKeys as? [String]
        else {
            Issue.record("Couldn't load localized strings for localization: \(current.localization)", sourceLocation: sourceLocation)
            return acc
        }

        return acc.union(Set(keys))
    }
}
