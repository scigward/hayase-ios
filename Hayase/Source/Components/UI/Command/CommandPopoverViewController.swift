//
//  CommandPopoverViewController.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

import UIKit

class CommandPopoverViewController: UIViewController {
    var onSelectionChanged: ((Set<String>) -> Void)?

    private let accessibilityTitle: String
    private let placeholder: String
    private let groups: [CommandGroup]
    private let allowsMultiple: Bool
    private var selectedValues: Set<String>
    private var filteredGroups: [CommandGroup]
    private weak var sourceView: UIView?

    private let dismissControl = UIControl()
    private let containerView = UIView()
    private let searchField = Input(placeholder: "Any", iconName: "search")
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    init(title: String,
         placeholder: String = "Any",
         groups: [CommandGroup],
         selectedValues: Set<String>,
         allowsMultiple: Bool,
         sourceView: UIView?) {
        self.accessibilityTitle = title
        self.placeholder = placeholder
        self.groups = groups
        self.selectedValues = selectedValues
        self.allowsMultiple = allowsMultiple
        self.filteredGroups = groups
        self.sourceView = sourceView
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutContainer()
    }

    private func setupViews() {
        view.backgroundColor = .clear

        dismissControl.translatesAutoresizingMaskIntoConstraints = false
        dismissControl.backgroundColor = .clear
        dismissControl.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        view.addSubview(dismissControl)
        NSLayoutConstraint.activate([
            dismissControl.topAnchor.constraint(equalTo: view.topAnchor),
            dismissControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dismissControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dismissControl.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        containerView.backgroundColor = UIColor.HayaseTheme.muted
        containerView.layer.cornerRadius = 6
        containerView.layer.masksToBounds = true
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.35
        containerView.layer.shadowRadius = 14
        containerView.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.addSubview(containerView)

        searchField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)])
        searchField.backgroundColor = UIColor.HayaseTheme.muted
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.accessibilityLabel = accessibilityTitle

        let separator = UIView()
        separator.backgroundColor = UIColor.HayaseTheme.border
        separator.translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 32
        tableView.estimatedRowHeight = 32
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(CommandItemCell.self,
                           forCellReuseIdentifier: CommandItemCell.reuseID)

        emptyLabel.text = "No results found."
        emptyLabel.textAlignment = .center
        emptyLabel.font = .nunito(ofSize: 14, weight: .regular)
        emptyLabel.textColor = UIColor.HayaseTheme.mutedForeground
        tableView.backgroundView = emptyLabel
        updateEmptyState()

        containerView.addSubview(searchField)
        containerView.addSubview(separator)
        containerView.addSubview(tableView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: containerView.topAnchor),
            searchField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 36),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            tableView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
    }

    private func layoutContainer() {
        let bounds = view.bounds.inset(by: view.safeAreaInsets)
        let sourceRect = sourceView?.convert(sourceView?.bounds ?? .zero, to: view)
            ?? CGRect(x: bounds.midX - 88, y: bounds.minY + 80, width: 176, height: 36)

        let maxContentHeight = min(CGFloat(320), bounds.height * 0.6)
        let rows = filteredGroups.reduce(0) { $0 + $1.options.count }
        let headings = filteredGroups.filter { $0.title?.isEmpty == false }.count
        let listHeight = min(maxContentHeight, CGFloat(rows) * 32 + CGFloat(headings) * 26)
        let height = min(maxContentHeight + 37, max(96, 37 + listHeight))
        let compact = traitCollection.horizontalSizeClass == .compact || bounds.width < 700
        let width = compact
            ? min(max(sourceRect.width, 176), bounds.width - 24)
            : min(max(sourceRect.width, 176), bounds.width - 24)

        var x = sourceRect.minX
        x = max(bounds.minX + 12, min(x, bounds.maxX - width - 12))

        var y = sourceRect.maxY + 4
        if y + height > bounds.maxY - 12 {
            y = max(bounds.minY + 12, sourceRect.minY - height - 4)
        }
        containerView.frame = CGRect(x: x, y: y, width: width, height: height)
    }

    @objc private func searchChanged() {
        let query = (searchField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if query.isEmpty {
            filteredGroups = groups
        } else {
            filteredGroups = groups.compactMap { group in
                let options = group.options.filter {
                    $0.label.lowercased().contains(query) || $0.value.lowercased().contains(query)
                }
                return options.isEmpty ? nil : CommandGroup(title: group.title, options: options)
            }
        }
        tableView.reloadData()
        updateEmptyState()
        view.setNeedsLayout()
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = filteredGroups.contains { !$0.options.isEmpty }
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
}

extension CommandPopoverViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        filteredGroups.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredGroups[safe: section]?.options.count ?? 0
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = filteredGroups[safe: section]?.title, !title.isEmpty else { return nil }
        let label = UILabel()
        label.text = title
        label.font = .nunito(ofSize: 12, weight: .medium)
        label.textColor = UIColor.HayaseTheme.mutedForeground
        label.backgroundColor = UIColor.HayaseTheme.muted
        label.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 26)
        let wrapper = UIView()
        wrapper.backgroundColor = UIColor.HayaseTheme.muted
        wrapper.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let title = filteredGroups[safe: section]?.title, !title.isEmpty else { return .leastNormalMagnitude }
        return 26
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: CommandItemCell.reuseID,
            for: indexPath) as? CommandItemCell,
              let option = filteredGroups[safe: indexPath.section]?.options[safe: indexPath.row]
        else { return UITableViewCell() }
        cell.configure(option: option,
                       selected: selectedValues.contains(option.value),
                       multiple: allowsMultiple)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let option = filteredGroups[safe: indexPath.section]?.options[safe: indexPath.row] else { return }
        if allowsMultiple {
            if selectedValues.contains(option.value) {
                selectedValues.remove(option.value)
            } else {
                selectedValues.insert(option.value)
            }
            onSelectionChanged?(selectedValues)
            tableView.reloadRows(at: [indexPath], with: .none)
        } else {
            selectedValues = selectedValues.contains(option.value) ? [] : [option.value]
            onSelectionChanged?(selectedValues)
            dismiss(animated: true)
        }
    }
}
