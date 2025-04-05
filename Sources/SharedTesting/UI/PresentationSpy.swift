// PresentationSpy.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2024-07-25 13:33 GMT.

import Testing
#if canImport(UIKit)
    import UIKit

    /// A spy class to intercept and verify presentation and dismissal of view controllers.
    ///
    /// This class intercepts the `UIViewController.present(_:animated:completion:)` method
    /// and tracks the presentations and dismissals of view controllers for testing purposes.

    @MainActor
    public class PresentationSpy: NSObject {
        /// The state of the view controller, either presented or dismissed.
        public enum State {
            case presented, dismissed
        }

        /// A struct to verify the presentation or dismissal of a view controller.
        public struct Verification: Equatable {
            public var controller: UIViewController
            public var animated: Bool
            public var state: State
        }

        private static var _presentations: [Verification] = []

        /// An array of verifications for the presentations and dismissals of view controllers.
        public var presentations: [Verification] {
            Self._presentations
        }

        @objc private func instantPresent(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
            viewControllerToPresent.loadViewIfNeeded()
            let verification = Verification(controller: viewControllerToPresent, animated: flag, state: .presented)
            Self._presentations.append(verification)
            completion?()
        }

        @objc private func viewControllerWasDismissed(_ notification: Notification) {
            // swiftlint:disable:next force_cast
            let dismissedViewController = notification.object as! UIViewController
            let animated = (notification.userInfo?["animatedKey"] as? NSNumber)?.boolValue ?? false
            let verification = Verification(controller: dismissedViewController, animated: animated, state: .dismissed)
            Self._presentations.append(verification)

            let closureContainer = notification.userInfo?["completionKey"] as? ClosureContainer
            closureContainer?.closure?()
        }

        override public init() {
            super.init()
            Self._presentations.removeAll()
            startIntercepting()
        }

        private func startIntercepting() {
            method_exchangeImplementations(
                class_getInstanceMethod(UIViewController.self, #selector(UIViewController.present(_:animated:completion:)))!,
                class_getInstanceMethod(PresentationSpy.self, #selector(PresentationSpy.instantPresent(_:animated:completion:)))!
            )

            method_exchangeImplementations(
                class_getInstanceMethod(UIViewController.self, #selector(UIViewController.dismiss(animated:completion:)))!,
                class_getInstanceMethod(PresentationSpy.self, #selector(PresentationSpy.dismissViewController(animated:completion:)))!
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(viewControllerWasDismissed(_:)),
                name: Notification.Name("viewControllerDismissed"),
                object: nil
            )
        }

        @objc func dismissViewController(animated flag: Bool, completion: (() -> Void)?) {
            let closureContainer = ClosureContainer(closure: completion)
            NotificationCenter.default.post(
                name: Notification.Name("viewControllerDismissed"),
                object: self,
                userInfo: [
                    "animatedKey": flag,
                    "completionKey": closureContainer
                ]
            )
        }

        deinit {
            method_exchangeImplementations(
                class_getInstanceMethod(PresentationSpy.self, #selector(PresentationSpy.instantPresent(_:animated:completion:)))!,
                class_getInstanceMethod(UIViewController.self, #selector(UIViewController.present(_:animated:completion:)))!
            )
            method_exchangeImplementations(
                class_getInstanceMethod(PresentationSpy.self, #selector(PresentationSpy.dismissViewController(animated:completion:)))!,
                class_getInstanceMethod(UIViewController.self, #selector(UIViewController.dismiss(animated:completion:)))!
            )
            NotificationCenter.default.removeObserver(self)
            Task {
                await MainActor.run {
                    Self._presentations.removeAll()
                }
            }
        }
    }

    private class ClosureContainer: NSObject {
        let closure: (() -> Void)?

        @objc init(closure: (() -> Void)?) {
            self.closure = closure
            super.init()
        }
    }

#endif
