//
//  HayaseControls.swift
//  Hayase
//
//  Shared UIKit counterparts for interface ui/input, ui/button and ui/combobox.
//

import UIKit

struct HayaseCommandOption: Hashable {
    let value: String
    let label: String

    init(value: String, label: String? = nil) {
        self.value = value
        self.label = label ?? value
    }
}

struct HayaseCommandGroup: Hashable {
    let title: String?
    let options: [HayaseCommandOption]

    init(title: String? = nil, options: [HayaseCommandOption]) {
        self.title = title
        self.options = options
    }
}

final class HayaseIconButton: UIButton {
    private let iconName: String
    private let iconPointSize: CGFloat

    init(iconName: String, pointSize: CGFloat = 16) {
        self.iconName = iconName
        self.iconPointSize = pointSize
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        self.iconName = "circle-question-mark"
        self.iconPointSize = 16
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.HayaseTheme.muted
        layer.cornerRadius = 6
        layer.masksToBounds = true
        tintColor = UIColor.HayaseTheme.foreground
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center
        setImage(UIImage.hayaseIcon(iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)),
            for: .normal)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 36).isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? UIColor.HayaseTheme.accent
                : UIColor.HayaseTheme.muted
        }
    }
}

final class HayaseTextInput: UITextField {
    private let iconName: String?

    init(placeholder: String = "Any", iconName: String? = nil) {
        self.iconName = iconName
        super.init(frame: .zero)
        setup(placeholder: placeholder)
    }

    required init?(coder: NSCoder) {
        self.iconName = nil
        super.init(coder: coder)
        setup(placeholder: "Any")
    }

    private func setup(placeholder: String) {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.HayaseTheme.muted
        layer.cornerRadius = 6
        layer.masksToBounds = true
        borderStyle = .none
        textColor = UIColor.HayaseTheme.foreground
        tintColor = UIColor.HayaseTheme.foreground
        font = .nunito(ofSize: 14, weight: .regular)
        returnKeyType = .search
        autocorrectionType = .no
        autocapitalizationType = .none
        attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)])

        if let iconName {
            let iconContainer = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
            let iconImageView = UIImageView(image: UIImage.hayaseIcon(iconName)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)))
            iconImageView.tintColor = UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)
            iconImageView.contentMode = .center
            iconImageView.frame = iconContainer.bounds
            iconContainer.addSubview(iconImageView)
            leftView = iconContainer
            leftViewMode = .always
        } else {
            leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 36))
            leftViewMode = .always
        }
    }
}

final class HayaseComboBoxControl: UIControl {
    private let valueLabel = UILabel()
    private let caretView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.HayaseTheme.muted
        layer.cornerRadius = 6
        layer.masksToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = .nunito(ofSize: 14, weight: .regular)
        valueLabel.numberOfLines = 1
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        caretView.image = UIImage.hayaseIcon("chevrons-up-down")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        caretView.tintColor = UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.65)
        caretView.contentMode = .scaleAspectFit
        caretView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(valueLabel)
        addSubview(caretView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: caretView.leadingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            caretView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            caretView.centerYAnchor.constraint(equalTo: centerYAnchor),
            caretView.widthAnchor.constraint(equalToConstant: 16),
            caretView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    func configure(text: String, placeholder: Bool) {
        valueLabel.text = text
        valueLabel.textColor = placeholder
            ? UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)
            : UIColor.HayaseTheme.foreground
        accessibilityLabel = text
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? UIColor.HayaseTheme.accent
                : UIColor.HayaseTheme.muted
        }
    }
}

class HayaseCommandPopoverViewController: UIViewController {
    var onSelectionChanged: ((Set<String>) -> Void)?

    private let accessibilityTitle: String
    private let placeholder: String
    private let groups: [HayaseCommandGroup]
    private let allowsMultiple: Bool
    private var selectedValues: Set<String>
    private var filteredGroups: [HayaseCommandGroup]
    private weak var sourceView: UIView?

    private let dismissControl = UIControl()
    private let containerView = UIView()
    private let searchField = HayaseTextInput(placeholder: "Any", iconName: "search")
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    init(title: String,
         placeholder: String = "Any",
         groups: [HayaseCommandGroup],
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
        tableView.register(HayaseCommandOptionCell.self,
                           forCellReuseIdentifier: HayaseCommandOptionCell.reuseID)

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
                return options.isEmpty ? nil : HayaseCommandGroup(title: group.title, options: options)
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

extension HayaseCommandPopoverViewController: UITableViewDataSource, UITableViewDelegate {
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
            withIdentifier: HayaseCommandOptionCell.reuseID,
            for: indexPath) as? HayaseCommandOptionCell,
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

private final class HayaseCommandOptionCell: UITableViewCell {
    static let reuseID = "HayaseCommandOptionCell"

    private let checkContainer = UIView()
    private let checkView = UIImageView()
    private let titleLabel = UILabel()
    private var checkLeadingConstraint: NSLayoutConstraint?
    private var checkTrailingConstraint: NSLayoutConstraint?
    private var titleLeadingToCheckConstraint: NSLayoutConstraint?
    private var titleLeadingToContentConstraint: NSLayoutConstraint?
    private var titleTrailingToCheckConstraint: NSLayoutConstraint?
    private var titleTrailingToContentConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = UIColor.HayaseTheme.accent

        checkContainer.translatesAutoresizingMaskIntoConstraints = false
        checkContainer.layer.cornerRadius = 3
        checkContainer.layer.masksToBounds = true

        checkView.image = UIImage.hayaseIcon("check")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        checkView.contentMode = .scaleAspectFit
        checkView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .nunito(ofSize: 14, weight: .regular)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(checkContainer)
        contentView.addSubview(titleLabel)
        checkContainer.addSubview(checkView)

        checkLeadingConstraint = checkContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8)
        checkTrailingConstraint = checkContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
        titleLeadingToCheckConstraint = titleLabel.leadingAnchor.constraint(equalTo: checkContainer.trailingAnchor, constant: 8)
        titleLeadingToContentConstraint = titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8)
        titleTrailingToCheckConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkContainer.leadingAnchor, constant: -8)
        titleTrailingToContentConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8)

        NSLayoutConstraint.activate([
            checkContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkContainer.widthAnchor.constraint(equalToConstant: 16),
            checkContainer.heightAnchor.constraint(equalToConstant: 16),

            checkView.centerXAnchor.constraint(equalTo: checkContainer.centerXAnchor),
            checkView.centerYAnchor.constraint(equalTo: checkContainer.centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 12),
            checkView.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    func configure(option: HayaseCommandOption, selected: Bool, multiple: Bool) {
        titleLabel.text = option.label
        checkContainer.layer.borderWidth = multiple ? 1 : 0
        checkContainer.layer.borderColor = UIColor.HayaseTheme.primary.cgColor
        checkContainer.backgroundColor = selected ? UIColor.HayaseTheme.primary : .clear
        checkView.tintColor = UIColor.HayaseTheme.primaryForeground
        checkView.isHidden = !selected

        checkLeadingConstraint?.isActive = multiple
        checkTrailingConstraint?.isActive = !multiple
        titleLeadingToCheckConstraint?.isActive = multiple
        titleLeadingToContentConstraint?.isActive = !multiple
        titleTrailingToCheckConstraint?.isActive = !multiple
        titleTrailingToContentConstraint?.isActive = multiple
    }
}
