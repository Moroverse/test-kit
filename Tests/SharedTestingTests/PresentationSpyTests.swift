// PresentationSpyTests.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2025-04-05 06:12 GMT.

//
//  PresentationSpyTests.swift
//  shared-testing
//
//  Created by Daniel Moro on 5.4.25..
#if canImport(UIKit)
    import SharedTesting
    import Testing
    import UIKit

    @MainActor
    @Suite("PresentationSpy Tests", .teardownTracking(), .serialized)
    struct PresentationSpyTests {
        @Test("PresentationSpy tracks view controller presentation")
        func testPresentationSpyTracksPresentation() async throws {
            // Setup
            let spy = PresentationSpy()
            await Test.trackForMemoryLeaks(spy)

            let dummyVC = UIViewController()
            let presenter = UIViewController()
            await Test.trackForMemoryLeaks(dummyVC)
            await Test.trackForMemoryLeaks(presenter)

            // Act
            presenter.present(dummyVC, animated: true)

            // Assert
            #expect(spy.presentations.count == 1)
            #expect(spy.presentations[0].controller === dummyVC)
            #expect(spy.presentations[0].animated == true)
            #expect(spy.presentations[0].state == .presented)
        }

        @Test("PresentationSpy tracks view controller dismissal")
        func testPresentationSpyTracksDismissal() async throws {
            // Setup
            InstantAnimationStub().startIntercepting()
            let spy = PresentationSpy()
            await Test.trackForMemoryLeaks(spy)

            let dummyVC = UIViewController()
            let presenter = UIViewController()
            await Test.trackForMemoryLeaks(dummyVC)
            await Test.trackForMemoryLeaks(presenter)

            // Present first
            presenter.present(dummyVC, animated: true)

            // Act - dismiss
            dummyVC.dismiss(animated: true)

            // Assert
            #expect(spy.presentations.count == 2)
            #expect(spy.presentations[1].state == .dismissed)
            #expect(spy.presentations[1].animated == true)
        }
    }
#endif
