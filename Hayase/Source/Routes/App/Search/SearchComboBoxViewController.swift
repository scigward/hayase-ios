//
//  SearchComboBoxViewController.swift
//  Hayase
//
//  Route adapter for the shared command popover component.
//

import UIKit

final class SearchComboBoxViewController: CommandPopoverViewController {
    init(filterType: SearchFilterType,
         options: [SearchFilterOption],
         selectedValues: Set<String>,
         sourceView: UIView?) {
        super.init(title: filterType.label,
                   placeholder: filterType.placeholder,
                   groups: Self.commandGroups(for: filterType, options: options),
                   selectedValues: selectedValues,
                   allowsMultiple: filterType.isMultiSelect,
                   sourceView: sourceView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func commandGroups(for type: SearchFilterType,
                                      options: [SearchFilterOption]) -> [CommandGroup] {
        if type == .genres {
            let genres = options
                .filter { $0.group == .genre }
                .map { CommandOption(value: $0.value, label: $0.label) }
            let tags = options
                .filter { $0.group == .tag }
                .map { CommandOption(value: $0.value, label: $0.label) }
            return [
                CommandGroup(title: "Genres", options: genres),
                CommandGroup(title: "Tags", options: tags),
            ].filter { !$0.options.isEmpty }
        }

        return [CommandGroup(options: options.map {
            CommandOption(value: $0.value, label: $0.label)
        })]
    }
}
