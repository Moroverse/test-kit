// ModelPresentation.swift
// Copyright (c) 2025 Moroverse
// Created by Daniel Moro on 2023-09-01 10:27 GMT.

import Foundation

public struct ModelPresentation<Model, Presentation> {
    public var model: Model
    public var presentation: Presentation

    public init(model: Model, presentation: Presentation) {
        self.model = model
        self.presentation = presentation
    }
}
