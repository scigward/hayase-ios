//
//  SearchComboBoxViewController.swift
//  Hayase
//
//  Route adapter for HayaseCommandPopoverViewController.
//

import UIKit

final class SearchComboBoxViewController: HayaseCommandPopoverViewController {
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
                                      options: [SearchFilterOption]) -> [HayaseCommandGroup] {
        if type == .genres {
            let genres = options
                .filter { $0.group == .genre }
                .map { HayaseCommandOption(value: $0.value, label: $0.label) }
            let tags = options
                .filter { $0.group == .tag }
                .map { HayaseCommandOption(value: $0.value, label: $0.label) }
            return [
                HayaseCommandGroup(title: "Genres", options: genres),
                HayaseCommandGroup(title: "Tags", options: tags),
            ].filter { !$0.options.isEmpty }
        }

        return [HayaseCommandGroup(options: options.map {
            HayaseCommandOption(value: $0.value, label: $0.label)
        })]
    }
}
