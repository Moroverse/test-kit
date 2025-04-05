// InstantAnimationStub.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2023-09-01 10:27 GMT.

import Foundation

#if canImport(UIKit)
    import UIKit

    /// A stub class to instantly execute animations for testing purposes.
    ///
    /// This class intercepts the `UIView.animate(withDuration:animations:completion:)` method
    /// and replaces it with a method that instantly executes the animations and calls the completion handler.
    public class InstantAnimationStub: NSObject {
        @objc private class func instantAnimate(withDuration _: TimeInterval, animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
            animations()
            if let completion {
                completion(true)
            }
        }

        /// Starts intercepting the `UIView.animate(withDuration:animations:completion:)` method.
        ///
        /// This method exchanges the implementation of `UIView.animate(withDuration:animations:completion:)`
        /// with `InstantAnimationStub.instantAnimate(withDuration:animations:completion:)`.
        public func startIntercepting() {
            method_exchangeImplementations(
                class_getClassMethod(UIView.self, #selector(UIView.animate(withDuration:animations:completion:)))!,
                class_getClassMethod(InstantAnimationStub.self, #selector(InstantAnimationStub.instantAnimate(withDuration:animations:completion:)))!
            )
        }

        deinit {
            method_exchangeImplementations(
                class_getClassMethod(InstantAnimationStub.self, #selector(InstantAnimationStub.instantAnimate(withDuration:animations:completion:)))!,
                class_getClassMethod(UIView.self, #selector(UIView.animate(withDuration:animations:completion:)))!
            )
        }
    }

#endif
