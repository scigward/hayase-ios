//
//  CommandModels.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

import UIKit

struct CommandOption: Hashable {
    let value: String
    let label: String

    init(value: String, label: String? = nil) {
        self.value = value
        self.label = label ?? value
    }
}

struct CommandGroup: Hashable {
    let title: String?
    let options: [CommandOption]

    init(title: String? = nil, options: [CommandOption]) {
        self.title = title
        self.options = options
    }
}
