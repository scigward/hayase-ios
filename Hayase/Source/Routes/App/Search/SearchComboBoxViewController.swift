//
//  SearchComboBoxViewController.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

final class SearchComboBoxViewController: UIViewController {
    var onSelectionChanged: ((Set<String>) -> Void)?

    private let filterType: SearchFilterType
    private let options: [SearchFilterOption]
    private let allowsMultiple: Bool
    private var selectedValues: Set<String>
    private var filteredOptions: [SearchFilterOption]
    private weak var sourceView: UIView?

    private let dimView = UIView()
    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let searchField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let doneButton = UIButton(type: .system)

    init(filterType: SearchFilterType,
         options: [SearchFilterOption],
         selectedValues: Set<String>,
         sourceView: UIView?) {
        self.filterType = filterType
        self.options = options
        self.allowsMultiple = filterType.isMultiSelect
        self.selectedValues = selectedValues
        self.filteredOptions = options
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

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        dimView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimView)
        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissSelf)))

        containerView.backgroundColor = UIColor.HayaseTheme.muted
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        containerView.clipsToBounds = true
        view.addSubview(containerView)

        titleLabel.text = filterType.label
        titleLabel.font = .nunito(ofSize: 14, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.backgroundColor = UIColor.HayaseTheme.background
        searchField.layer.cornerRadius = 6
        searchField.layer.borderWidth = 1
        searchField.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        searchField.textColor = UIColor.HayaseTheme.foreground
        searchField.font = .nunito(ofSize: 14)
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Search",
            attributes: [.foregroundColor: UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.65)])
        searchField.leftView = iconContainer()
        searchField.leftViewMode = .always
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)

        doneButton.setTitle(allowsMultiple ? "Done" : nil, for: .normal)
        doneButton.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
        doneButton.setTitleColor(UIColor.HayaseTheme.foreground, for: .normal)
        doneButton.isHidden = !allowsMultiple
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 38
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(OptionCell.self, forCellReuseIdentifier: OptionCell.reuseID)

        [titleLabel, searchField, doneButton, tableView].forEach {
            containerView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),

            doneButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -8),

            searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            searchField.heightAnchor.constraint(equalToConstant: 34),

            tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -6),
        ])
    }

    private func layoutContainer() {
        let bounds = view.bounds.inset(by: view.safeAreaInsets)
        let compact = traitCollection.horizontalSizeClass == .compact || bounds.width < 700
        let width = compact ? min(bounds.width - 24, 420) : 320
        let maxHeight = compact ? min(bounds.height - 40, 520) : min(bounds.height - 24, 420)
        let desiredHeight = min(maxHeight, CGFloat(filteredOptions.count) * 38 + 96)
        let height = max(180, desiredHeight)

        if compact {
            containerView.frame = CGRect(x: bounds.midX - width / 2,
                                         y: bounds.midY - height / 2,
                                         width: width,
                                         height: height)
            return
        }

        let sourceRect = sourceView?.convert(sourceView?.bounds ?? .zero, to: view)
            ?? CGRect(x: bounds.midX - width / 2, y: bounds.minY + 80, width: width, height: 36)
        var x = sourceRect.minX
        x = max(bounds.minX + 12, min(x, bounds.maxX - width - 12))

        var y = sourceRect.maxY + 6
        if y + height > bounds.maxY - 12 {
            y = max(bounds.minY + 12, sourceRect.minY - height - 6)
        }
        containerView.frame = CGRect(x: x, y: y, width: width, height: height)
    }

    private func iconContainer() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 32, height: 34))
        let imageView = UIImageView(image: UIImage.hayaseIcon("search")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)))
        imageView.tintColor = UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.65)
        imageView.contentMode = .center
        imageView.frame = container.bounds
        container.addSubview(imageView)
        return container
    }

    @objc private func searchChanged() {
        let query = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredOptions = options
        } else {
            filteredOptions = options.filter {
                $0.label.lowercased().contains(query) || $0.value.lowercased().contains(query)
            }
        }
        tableView.reloadData()
        view.setNeedsLayout()
    }

    @objc private func doneTapped() {
        onSelectionChanged?(selectedValues)
        dismiss(animated: true)
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    private final class OptionCell: UITableViewCell {
        static let reuseID = "SearchComboBoxOptionCell"

        private let titleLabel = UILabel()
        private let checkView = UIImageView()

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
            selectedBackgroundView = UIView()
            selectedBackgroundView?.backgroundColor = UIColor.HayaseTheme.accent

            titleLabel.font = .nunito(ofSize: 14, weight: .medium)
            titleLabel.textColor = UIColor.HayaseTheme.foreground
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            checkView.image = UIImage.hayaseIcon("check")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
            checkView.tintColor = UIColor.HayaseTheme.foreground
            checkView.contentMode = .scaleAspectFit
            checkView.translatesAutoresizingMaskIntoConstraints = false

            contentView.addSubview(titleLabel)
            contentView.addSubview(checkView)
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkView.leadingAnchor, constant: -10),
                titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

                checkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                checkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                checkView.widthAnchor.constraint(equalToConstant: 16),
                checkView.heightAnchor.constraint(equalToConstant: 16),
            ])
        }

        func configure(option: SearchFilterOption, selected: Bool) {
            titleLabel.text = option.label
            checkView.isHidden = !selected
        }
    }
}

extension SearchComboBoxViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredOptions.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: OptionCell.reuseID,
            for: indexPath) as? OptionCell else { return UITableViewCell() }
        let option = filteredOptions[indexPath.row]
        cell.configure(option: option, selected: selectedValues.contains(option.value))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let option = filteredOptions[indexPath.row]
        if allowsMultiple {
            if selectedValues.contains(option.value) {
                selectedValues.remove(option.value)
            } else {
                selectedValues.insert(option.value)
            }
            tableView.reloadRows(at: [indexPath], with: .none)
        } else {
            if selectedValues.contains(option.value) {
                selectedValues.removeAll()
            } else {
                selectedValues = [option.value]
            }
            onSelectionChanged?(selectedValues)
            dismiss(animated: true)
        }
    }
}
