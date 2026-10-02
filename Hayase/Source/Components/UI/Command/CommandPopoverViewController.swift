//
//  CommandPopoverViewController.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

import UIKit

class CommandPopoverViewController: UIViewController {
    var onSelectionChanged: ((Set<String>) -> Void)?
    /// cmdk's own filter: an item is shown when its `value` (not its label) scores above 0 against
    /// the search, and the groups with the best matches come first.
    var filtersByCommandScore = false

    private let accessibilityTitle: String
    private let placeholder: String
    private let showsSearch: Bool
    private let groups: [CommandGroup]
    private let allowsMultiple: Bool
    private var selectedValues: Set<String>
    private var filteredGroups: [CommandGroup]
    private weak var sourceView: UIView?

    private let dismissControl = UIControl()
    /// `Dialog.Overlay`, behind the card where the width is below `md`.
    private let dialogBackdrop = HayaseStripedBackdropView()
    private let containerView = UIView()
    private let searchField = Input(placeholder: "Any", iconName: "search")
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    /// `p-1` around each group.
    private static let groupPadding: CGFloat = 4
    /// `px-2 py-1.5 text-xs`: a 16pt line between 6pt paddings.
    private static let headingHeight: CGFloat = 28
    /// Below `md` the combobox is a dialog, not a popover.
    private static let popoverMinimumWidth: CGFloat = 768

    init(title: String,
         placeholder: String = "Any",
         groups: [CommandGroup],
         selectedValues: Set<String>,
         allowsMultiple: Bool,
         sourceView: UIView?, showsSearch: Bool = true) {
        self.accessibilityTitle = title
        self.placeholder = placeholder
        self.showsSearch = showsSearch
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

        dialogBackdrop.translatesAutoresizingMaskIntoConstraints = false
        dialogBackdrop.isHidden = true
        dialogBackdrop.isUserInteractionEnabled = false
        view.addSubview(dialogBackdrop)
        NSLayoutConstraint.activate([
            dialogBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            dialogBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dialogBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dialogBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

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

        containerView.backgroundColor = showsSearch ? UIColor.HayaseTheme.muted : UIColor.HayaseTheme.popover
        containerView.layer.borderWidth = showsSearch ? 0 : 1
        containerView.layer.borderColor = UIColor.HayaseTheme.border.cgColor
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
        // command-input.svelte: MagnifyingGlass `h-4 w-4 opacity-50 absolute left-3`
        searchField.usesRadixMagnifier = true
        searchField.searchIconSize = 16
        searchField.iconLeadingInset = 12
        searchField.highlightsIconOnFocus = false
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.accessibilityLabel = accessibilityTitle
        searchField.isHidden = !showsSearch

        let separator = UIView()
        separator.backgroundColor = UIColor.HayaseTheme.border
        separator.translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        // A plain table pads the top of every section by 22pt, which left a gap above the first entry.
        tableView.sectionHeaderTopPadding = 0
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
            searchField.heightAnchor.constraint(equalToConstant: showsSearch ? 36 : 0),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: showsSearch ? 1 : 0),

            tableView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
    }

    /// Whether the combobox is the centred dialog (`ComboboxShell` below `md`).
    private var usesDialog: Bool {
        showsSearch && view.bounds.width < Self.popoverMinimumWidth
    }

    private func layoutContainer() {
        let dialog = usesDialog
        dialogBackdrop.isHidden = !dialog
        containerView.layer.cornerRadius = dialog ? 8 : 6   // rounded-lg dialog, rounded-md popover
        let bounds = view.bounds.inset(by: view.safeAreaInsets)
        let searchHeight: CGFloat = showsSearch ? 37 : 0
        let rows = filteredGroups.reduce(0) { $0 + $1.options.count }
        let headings = filteredGroups.filter { $0.title?.isEmpty == false }.count
        let naturalList = rows == 0
            ? CGFloat(68)   // Command.Empty: py-6 around a 20pt line
            : CGFloat(rows) * 32 + CGFloat(headings) * Self.headingHeight
                + CGFloat(filteredGroups.count) * Self.groupPadding * 2

        if dialog {
            // top-[10%] w-full max-w-[clamp(0px,95dvw,30rem)] max-h-[80dvh], centred
            let width = min(view.bounds.width * 0.95, 480)
            let height = min(searchHeight + naturalList, view.bounds.height * 0.8)
            containerView.frame = CGRect(x: (view.bounds.width - width) / 2,
                                         y: view.bounds.height * 0.1,
                                         width: width, height: height)
            return
        }

        let sourceRect = sourceView?.convert(sourceView?.bounds ?? .zero, to: view)
            ?? CGRect(x: bounds.midX - 88, y: bounds.minY + 80, width: 176, height: 36)

        let height: CGFloat
        if showsSearch {
            // Command.Root max-h-[clamp(0px,20rem,60lvh)] around the input and a list of at most 300pt
            let maxHeight = min(CGFloat(320), view.bounds.height * 0.6)
            height = min(maxHeight, searchHeight + min(300, naturalList))
        } else {
            let maxContentHeight = min(CGFloat(320), bounds.height * 0.6)
            height = min(maxContentHeight, max(32, naturalList))
        }
        let width = min(sourceRect.width, bounds.width - 24)

        var x = sourceRect.minX
        x = max(bounds.minX + 12, min(x, bounds.maxX - width - 12))

        var y = sourceRect.maxY + 4
        if y + height > bounds.maxY - 12 {
            y = max(bounds.minY + 12, sourceRect.minY - height - 4)
        }
        containerView.frame = CGRect(x: x, y: y, width: width, height: height)
    }

    @objc private func searchChanged() {
        let raw = searchField.text ?? ""
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if filtersByCommandScore {
            filteredGroups = Self.scoredGroups(groups, search: raw)
        } else if query.isEmpty {
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

    /// cmdk-sv: without a search everything shows; with one only the items whose value scores
    /// above 0 do, in their own order, and the groups go by their best item.
    private static func scoredGroups(_ groups: [CommandGroup], search: String) -> [CommandGroup] {
        guard !search.isEmpty else { return groups }
        let scored = groups.enumerated().compactMap { index, group -> (Int, Double, CommandGroup)? in
            let scores = group.options.map { CommandScore.score(value: $0.value, search: search) }
            let options = zip(group.options, scores).filter { $0.1 > 0 }.map { $0.0 }
            guard !options.isEmpty else { return nil }
            return (index, scores.max() ?? 0, CommandGroup(title: group.title, options: options))
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.map { $0.2 }
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = filteredGroups.contains { !$0.options.isEmpty }
    }

    @objc private func dismissSelf() {
        closeAndRestoreFocus()
    }

    private func closeAndRestoreFocus() {
        let sourceView = sourceView
        dismiss(animated: true) {
            sourceView?.becomeFirstResponder()
        }
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
        label.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: Self.headingHeight)
        let wrapper = UIView()
        wrapper.backgroundColor = UIColor.HayaseTheme.muted
        wrapper.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 8 + Self.groupPadding),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -8 - Self.groupPadding),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: Self.groupPadding),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let title = filteredGroups[safe: section]?.title, !title.isEmpty else { return Self.groupPadding }
        return Self.headingHeight + Self.groupPadding
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        Self.groupPadding
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
                       multiple: allowsMultiple, selectStyle: !showsSearch)
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
            selectedValues = [option.value]
            onSelectionChanged?(selectedValues)
            closeAndRestoreFocus()
        }
    }
}
