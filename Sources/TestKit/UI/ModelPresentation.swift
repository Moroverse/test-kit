// ModelPresentation.swift
// Copyright (c) 2026 Moroverse
// Created by Daniel Moro on 2025-04-05 06:52 GMT.

import Foundation

public struct ModelPresentation<Model, Presentation> {
    public var model: Model
    public var presentation: Presentation

    public init(model: Model, presentation: Presentation) {
        self.model = model
        self.presentation = presentation
    }
}
