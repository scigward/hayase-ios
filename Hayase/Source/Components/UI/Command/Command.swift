//
//  Command.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

import UIKit

class CommandPopoverViewController: UIViewController, KeyboardEventListener {
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
    private var isClosing = false

    /// Without a search the list is `select-content.svelte`: `Select.Content` of the entry editor.
    private var isSelect: Bool { !showsSearch }

    private let dismissControl = UIControl()
    /// `Dialog.Overlay`, behind the card where the width is below `md`.
    private let dialogBackdrop = HayaseStripedBackdropView()
    private let containerView = CommandContainerView()
    private let searchField = Input(placeholder: "Any", iconName: "search")
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    /// `p-1` around each group.
    private static let groupPadding: CGFloat = 4
    /// `px-2 py-1.5 text-xs`: a 16pt line between 6pt paddings.
    private static let headingHeight: CGFloat = 28
    /// Below `md` the combobox is a dialog, not a popover.
    private static let popoverMinimumWidth: CGFloat = 768
    /// The Close group (`p-1` around a 32pt item) and the 1pt separator under it.
    private static let closeRowHeight: CGFloat = 41

    /// What DOM focus is on while the arrow keys move it: the search input, the Close item, or a row.
    private enum KeyboardFocus: Equatable {
        case input
        case close
        case row(IndexPath)
    }

    private var keyboardFocus: KeyboardFocus = .input
    /// `inputType === 'dpad'`: the arrow keys were used, and no touch or pointer since. The list then
    /// starts with a Close item.
    private var isKeyboardNavigating = false {
        didSet {
            guard isKeyboardNavigating != oldValue else { return }
            updateCloseRow()
        }
    }
    private let closeRow = CommandCloseRowView()
    /// The width of an item, which the height of its wrapped text depends on; set when the card is laid out.
    private var itemWidth: CGFloat = 0

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
        // `{#if $inputType === 'dpad'}`: a list that opens while the arrow keys are the input has the Close item
        isKeyboardNavigating = Navigate.inputType == .dpad && !isSelect
        NotificationCenter.default.addObserver(self, selector: #selector(inputTypeChanged),
                                               name: Navigate.inputTypeDidChange, object: nil)
    }

    /// The list is drawn again after the key that made it `dpad` has been handled, as the DOM is
    @objc private func inputTypeChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if Navigate.inputType == .dpad {
                if !self.isSelect { self.isKeyboardNavigating = true }
            } else {
                self.endKeyboardNavigation()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutContainer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()   // so the arrow keys reach the list without the input being focused
        if isSelect {
            highlightSelectedItem()
            animateSelectIn()
        }
    }

    /// The item of a select that is chosen is the one that has the focus when it opens, which draws it
    /// with `data-[highlighted]:bg-accent`; the arrow keys go on from there.
    private func highlightSelectedItem() {
        for (section, group) in filteredGroups.enumerated() {
            guard let row = group.options.firstIndex(where: { selectedValues.contains($0.value) }) else { continue }
            let indexPath = IndexPath(row: row, section: section)
            keyboardFocus = .row(indexPath)
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            tableView.scrollToRow(at: indexPath, at: .none, animated: false)
            return
        }
    }

    /// `inTransition = flyAndScale`: from 8pt above and 95% in 150ms with `cubicOut`.
    private func animateSelectIn() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        containerView.alpha = 0
        containerView.transform = CGAffineTransform(translationX: 0, y: -8).scaledBy(x: 0.95, y: 0.95)
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 1.0 / 3, y: 1),
                                             controlPoint2: CGPoint(x: 2.0 / 3, y: 1))
        let animator = UIViewPropertyAnimator(duration: 0.15, timingParameters: timing)
        animator.addAnimations {
            self.containerView.alpha = 1
            self.containerView.transform = .identity
        }
        animator.startAnimation()
    }

    // MARK: - Keyboard (`navigate` of navigate.ts on the Command root)

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [.keydown(KeyboardEvent.Key.arrowUp, priority: true), .keydown(KeyboardEvent.Key.arrowDown, priority: true),
         .keydown(KeyboardEvent.Key.enter, priority: true), .keydown(KeyboardEvent.Key.escape, priority: true)]
    }

    /// The arrows are `navigate`, which the list is given as `onKeydown` and which cmdk leaves the key to once it
    /// has run; Enter is the item's, and Escape is the dialog's, which is only the closest one that has it.
    func keyDown(_ event: KeyboardEvent) {
        switch event.key {
        case KeyboardEvent.Key.arrowUp, KeyboardEvent.Key.arrowDown:
            if Navigate.accepts(event) != nil {
                moveKeyboardFocus(by: event.key == KeyboardEvent.Key.arrowDown ? 1 : -1)
            }
        case KeyboardEvent.Key.enter:
            activateFocus()
        case KeyboardEvent.Key.escape:
            dismissSelf()
        default:
            return
        }
        event.preventDefault()
        event.stopPropagation()
    }

    /// The elements the arrow keys go through, top to bottom.
    private func keyboardOrder() -> [KeyboardFocus] {
        var order: [KeyboardFocus] = isSelect ? [] : [.input]
        if isKeyboardNavigating { order.append(.close) }
        for (section, group) in filteredGroups.enumerated() {
            for row in group.options.indices {
                order.append(.row(IndexPath(row: row, section: section)))
            }
        }
        return order
    }

    private func moveKeyboardFocus(by delta: Int) {
        let order = keyboardOrder()
        guard !order.isEmpty else { return }
        // a select nothing is chosen in has no focus yet: the arrow goes to its first or last item
        let current = order.firstIndex(of: keyboardFocus) ?? (delta > 0 ? -1 : order.count)
        let target = order[min(max(current + delta, 0), order.count - 1)]
        if !isSelect { isKeyboardNavigating = true }   // the Close item comes in above the list
        focus(target)
    }

    private func focus(_ target: KeyboardFocus) {
        keyboardFocus = target
        closeRow.isKeyFocused = target == .close
        switch target {
        case .input:
            clearRowSelection()
            searchField.becomeFirstResponder()
        case .close:
            clearRowSelection()
            takeKeysFromInput()
        case .row(let indexPath):
            takeKeysFromInput()
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            tableView.scrollToRow(at: indexPath, at: .none, animated: false)
        }
    }

    private func clearRowSelection() {
        if let selected = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selected, animated: false)
        }
    }

    private func takeKeysFromInput() {
        searchField.resignFirstResponder()
        becomeFirstResponder()
    }

    /// Enter on the focused item clicks it; in the input it takes the item cmdk has selected, the first.
    private func activateFocus() {
        switch keyboardFocus {
        case .close:
            closeAndRestoreFocus()
        case .row(let indexPath):
            choose(at: indexPath)
        case .input:
            guard !isSelect, filteredGroups.first?.options.isEmpty == false else { return }
            choose(at: IndexPath(row: 0, section: 0))
        }
    }

    /// A touch or the pointer is `inputType` 'touch' or 'mouse' again.
    private func endKeyboardNavigation() {
        guard isKeyboardNavigating else { return }
        isKeyboardNavigating = false
        keyboardFocus = .input
        closeRow.isKeyFocused = false
        clearRowSelection()
    }

    private func updateCloseRow() {
        if isKeyboardNavigating {
            closeRow.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: Self.closeRowHeight)
            closeRow.onTap = { [weak self] in self?.closeAndRestoreFocus() }
            tableView.tableHeaderView = closeRow
        } else {
            tableView.tableHeaderView = nil
        }
        view.setNeedsLayout()
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

        // a touch or the pointer ends `inputType === 'dpad'`
        containerView.onInteraction = { [weak self] in self?.endKeyboardNavigation() }

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
        tableView.estimatedRowHeight = 0   // an item is as tall as its wrapped text, which `heightForRowAt` measures
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

            // `border` of the select content is outside of its `p-1`
            tableView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: isSelect ? 1 : 0),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: isSelect ? 1 : 0),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: isSelect ? -1 : 0),
            tableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: isSelect ? -1 : 0),
        ])
    }

    /// The card is placed by its bounds and center, which stay right while it is transformed.
    private func place(_ rect: CGRect) {
        containerView.bounds = CGRect(origin: .zero, size: rect.size)
        containerView.center = CGPoint(x: rect.midX, y: rect.midY)
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
        let sourceRect = sourceView?.convert(sourceView?.bounds ?? .zero, to: view)
            ?? CGRect(x: bounds.midX - 88, y: bounds.minY + 80, width: 176, height: 36)
        // top-[10%] w-full max-w-[clamp(0px,95dvw,30rem)] max-h-[80dvh] as a dialog, the trigger's width as a popover
        let width = dialog ? min(view.bounds.width * 0.95, 480) : min(sourceRect.width, bounds.width - 24)
        let rowWidth = width - (isSelect ? 2 : 0) - 2 * Self.groupPadding
        if abs(rowWidth - itemWidth) > 0.5 {
            itemWidth = rowWidth
            tableView.beginUpdates()   // the rows are measured again for the width they have
            tableView.endUpdates()
        }
        let rows = filteredGroups.reduce(0) { $0 + $1.options.count }
        let rowsHeight = filteredGroups.reduce(CGFloat(0)) { sum, group in
            sum + group.options.reduce(CGFloat(0)) { $0 + CommandItemCell.height(for: $1.label, width: rowWidth) }
        }
        let headings = filteredGroups.filter { $0.title?.isEmpty == false }.count
        let naturalList = (rows == 0
            ? CGFloat(68)   // Command.Empty: py-6 around a 20pt line
            : rowsHeight + CGFloat(headings) * Self.headingHeight
                + CGFloat(filteredGroups.count) * Self.groupPadding * 2)
            + (isKeyboardNavigating ? Self.closeRowHeight : 0)

        if dialog {
            let height = min(searchHeight + naturalList, view.bounds.height * 0.8)
            place(CGRect(x: (view.bounds.width - width) / 2,
                         y: view.bounds.height * 0.1,
                         width: width, height: height))
            return
        }

        let height: CGFloat
        if showsSearch {
            // Command.Root max-h-[clamp(0px,20rem,60lvh)] around the input and a list of at most 300pt
            let maxHeight = min(CGFloat(320), view.bounds.height * 0.6)
            height = min(maxHeight, searchHeight + min(300, naturalList))
        } else {
            // select-content.svelte has no height of its own: every item is there, as far as there is
            // room above or below the trigger, and the border is outside of the items
            let natural = naturalList + 2
            let below = bounds.maxY - 12 - (sourceRect.maxY + 4)
            let above = sourceRect.minY - 4 - (bounds.minY + 12)
            height = min(natural, max(32, below >= natural ? below : max(below, above)))
        }

        var x = sourceRect.minX
        x = max(bounds.minX + 12, min(x, bounds.maxX - width - 12))

        var y = sourceRect.maxY + 4
        if y + height > bounds.maxY - 12 {
            y = max(bounds.minY + 12, sourceRect.minY - height - 4)
        }
        place(CGRect(x: x, y: y, width: width, height: height))
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
        keyboardFocus = .input
        closeRow.isKeyFocused = false
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
        guard isSelect else {
            dismiss(animated: true) {
                sourceView?.becomeFirstResponder()
            }
            return
        }

        // `outTransition = scale` from 95% to nothing in 50ms
        guard !isClosing else { return }
        isClosing = true
        guard !UIAccessibility.isReduceMotionEnabled else {
            dismiss(animated: false) { sourceView?.becomeFirstResponder() }
            return
        }
        UIView.animate(withDuration: 0.05, delay: 0, options: .curveLinear, animations: {
            self.containerView.alpha = 0
            self.containerView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }, completion: { [weak self] _ in
            self?.dismiss(animated: false) { sourceView?.becomeFirstResponder() }
        })
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

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard itemWidth > 0, let option = filteredGroups[safe: indexPath.section]?.options[safe: indexPath.row] else { return 32 }
        return CommandItemCell.height(for: option.label, width: itemWidth)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        choose(at: indexPath)
    }

    /// `handleSelect`: a single list takes the item and closes, a multiple one toggles it.
    func choose(at indexPath: IndexPath) {
        guard let option = filteredGroups[safe: indexPath.section]?.options[safe: indexPath.row] else { return }
        if allowsMultiple {
            if selectedValues.contains(option.value) {
                selectedValues.remove(option.value)
            } else {
                selectedValues.insert(option.value)
            }
            onSelectionChanged?(selectedValues)
            tableView.reloadRows(at: [indexPath], with: .none)
            if keyboardFocus == .row(indexPath) {
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
        } else {
            selectedValues = [option.value]
            onSelectionChanged?(selectedValues)
            closeAndRestoreFocus()
        }
    }
}

/// The card of the list, which hears every touch and pointer move over it.
private final class CommandContainerView: UIView {
    var onInteraction: (() -> Void)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let event, event.type == .touches || event.type == .hover { onInteraction?() }
        return super.hitTest(point, with: event)
    }
}

/// The Close item `$inputType === 'dpad'` puts at the top of the list, with its separator.
private final class CommandCloseRowView: UIView {
    var onTap: (() -> Void)?
    /// UIView already has a read-only `isFocused`, which is the focus engine's.
    var isKeyFocused = false {
        didSet { highlight.backgroundColor = isKeyFocused ? UIColor.HayaseTheme.accent : .clear }
    }

    private let highlight = UIView()
    private let icon = UIImageView(image: UIImage.hayaseIcon("x", pointSize: 16))
    private let label = UILabel()
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        highlight.layer.cornerRadius = 4   // rounded-sm
        icon.tintColor = UIColor.HayaseTheme.foreground
        icon.contentMode = .scaleAspectFit
        label.text = "Close"
        label.font = .nunito(ofSize: 14, weight: .regular)
        label.textColor = UIColor.HayaseTheme.foreground
        separator.backgroundColor = UIColor.HayaseTheme.border
        [highlight, icon, label, separator].forEach(addSubview)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // p-1 around an item of px-2 py-1.5, `<X class='mr-2 h-4 w-4'/>` then the text
        highlight.frame = CGRect(x: 4, y: 4, width: bounds.width - 8, height: 32)
        icon.frame = CGRect(x: 12, y: 12, width: 16, height: 16)
        label.frame = CGRect(x: 36, y: 4, width: bounds.width - 48, height: 32)
        separator.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }

    @objc private func tapped() {
        onTap?()
    }
}
