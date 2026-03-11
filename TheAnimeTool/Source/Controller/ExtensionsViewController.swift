// ExtensionsViewController.swift
// Settings page for managing Hayase-compatible torrent/nzb/url extensions.
// Mirrors src/lib/components/ui/extensions/extensions.svelte and ExtensionSettings.svelte
// from scigward/interface.
//
// Two sections:
//   [0] Installed Extensions — list of ExtensionConfig entries with status dot, version/
//       type/accuracy/media badges, enable/disable switch, settings action.
//   [1] Add Extension — URL text field + Import button (mirrors Repositories tab).

import UIKit

final class ExtensionsViewController: UIViewController {

    // MARK: - UI

    private var tableView: UITableView!
    private var importField: UITextField!
    private var importButton: UIButton!
    private var importSpinner: UIActivityIndicatorView!
    private var noExtLabel: UILabel!

    // Sorted list of (id, config) for stable table order
    private var sortedConfigs: [(id: String, config: ExtensionConfig)] {
        ExtensionService.shared.configs
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Extensions"
        view.backgroundColor = .black
        navigationItem.largeTitleDisplayMode = .never

        setupImportBar()
        setupTableView()
        setupNoExtLabel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    // MARK: - Setup

    private func setupImportBar() {
        let container = UIView()
        container.backgroundColor = UIColor(white: 0.08, alpha: 1)
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        importField = UITextField()
        importField.placeholder = "https://example.com/manifest.json"
        importField.backgroundColor = UIColor(white: 0.13, alpha: 1)
        importField.textColor = .white
        importField.tintColor = UIColor(red: 0.239, green: 0.706, blue: 0.949, alpha: 1)
        importField.font = .systemFont(ofSize: 13)
        importField.autocorrectionType = .no
        importField.autocapitalizationType = .none
        importField.keyboardType = .URL
        importField.returnKeyType = .go
        importField.delegate = self
        importField.layer.cornerRadius = 8
        importField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        importField.leftViewMode = .always
        importField.translatesAutoresizingMaskIntoConstraints = false

        importButton = UIButton(type: .system)
        importButton.setTitle("Import", for: .normal)
        importButton.setTitleColor(.black, for: .normal)
        importButton.backgroundColor = UIColor(red: 0.239, green: 0.706, blue: 0.949, alpha: 1)
        importButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        importButton.layer.cornerRadius = 8
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        importButton.translatesAutoresizingMaskIntoConstraints = false

        importSpinner = UIActivityIndicatorView(style: .medium)
        importSpinner.color = .black
        importSpinner.hidesWhenStopped = true
        importSpinner.translatesAutoresizingMaskIntoConstraints = false

        [importField, importButton, importSpinner].forEach { container.addSubview($0) }

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.heightAnchor.constraint(equalToConstant: 60),

            importField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            importField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            importField.heightAnchor.constraint(equalToConstant: 36),

            importButton.leadingAnchor.constraint(equalTo: importField.trailingAnchor, constant: 10),
            importButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            importButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            importButton.widthAnchor.constraint(equalToConstant: 72),
            importButton.heightAnchor.constraint(equalToConstant: 36),

            importSpinner.centerXAnchor.constraint(equalTo: importButton.centerXAnchor),
            importSpinner.centerYAnchor.constraint(equalTo: importButton.centerYAnchor),
        ])

        self.view.addConstraint(
            importField.trailingAnchor.constraint(equalTo: importButton.leadingAnchor, constant: -10))
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
        tableView.separatorColor = UIColor(white: 0.13, alpha: 1)
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.register(ExtensionCell.self, forCellReuseIdentifier: ExtensionCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 110
        view.addSubview(tableView)

        let importContainer = view.subviews.first { $0.backgroundColor == UIColor(white: 0.08, alpha: 1) }!

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: importContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupNoExtLabel() {
        noExtLabel = UILabel()
        noExtLabel.text = "No extensions installed.\nPaste a manifest URL above and tap Import."
        noExtLabel.textColor = UIColor(white: 0.4, alpha: 1)
        noExtLabel.font = .systemFont(ofSize: 14)
        noExtLabel.textAlignment = .center
        noExtLabel.numberOfLines = 3
        noExtLabel.translatesAutoresizingMaskIntoConstraints = false
        noExtLabel.isHidden = true
        view.addSubview(noExtLabel)
        NSLayoutConstraint.activate([
            noExtLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            noExtLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 30),
            noExtLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            noExtLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Reload

    private func reload() {
        tableView.reloadData()
        noExtLabel.isHidden = !sortedConfigs.isEmpty
    }

    // MARK: - Import

    @objc private func importTapped() {
        triggerImport()
    }

    private func triggerImport() {
        let url = (importField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        importField.resignFirstResponder()

        importButton.setTitle("", for: .normal)
        importSpinner.startAnimating()
        importButton.isEnabled = false

        Task { @MainActor in
            defer {
                self.importSpinner.stopAnimating()
                self.importButton.setTitle("Import", for: .normal)
                self.importButton.isEnabled = true
            }
            do {
                try await ExtensionService.shared.importExtension(from: url)
                self.importField.text = ""
                self.reload()
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ msg: String) {
        let alert = UIAlertController(title: "Import Error", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Delete

    private func deleteExtension(id: String) {
        Task { @MainActor in
            await ExtensionService.shared.delete(id: id)
            self.reload()
        }
    }

    // MARK: - Options dialog

    private func showOptions(for config: ExtensionConfig) {
        let alert = UIAlertController(title: "\(config.name) Options", message: nil,
                                       preferredStyle: .actionSheet)
        let opts = config.options ?? [:]
        if opts.isEmpty {
            alert.message = "This extension has no configurable options."
        } else {
            for (key, opt) in opts.sorted(by: { $0.key < $1.key }) {
                let current = ExtensionService.shared.options[config.id]?.options[key]?.stringValue
                    ?? opt.default.stringValue
                alert.addAction(UIAlertAction(title: "\(opt.description): \(current)",
                                               style: .default) { [weak self] _ in
                    self?.editOption(key: key, def: opt, config: config)
                })
            }
        }
        alert.addAction(UIAlertAction(title: "Delete Extension", style: .destructive) { [weak self] _ in
            self?.deleteExtension(id: config.id)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }

    private func editOption(key: String, def: ExtensionOptionDef, config: ExtensionConfig) {
        switch def.type {
        case "boolean":
            let current = ExtensionService.shared.options[config.id]?.options[key]
            let newVal: AnyCodableValue = (current == .bool(true)) ? .bool(false) : .bool(true)
            ExtensionService.shared.setOption(newVal, key: key, for: config.id)
            reload()

        case "select":
            let sheet = UIAlertController(title: def.description, message: nil,
                                           preferredStyle: .actionSheet)
            for v in def.values ?? [] {
                sheet.addAction(UIAlertAction(title: v, style: .default) { [weak self] _ in
                    ExtensionService.shared.setOption(.string(v), key: key, for: config.id)
                    self?.reload()
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            sheet.popoverPresentationController?.sourceView = view
            present(sheet, animated: true)

        default:
            let alert = UIAlertController(title: def.description, message: nil,
                                           preferredStyle: .alert)
            alert.addTextField { tf in
                tf.placeholder = def.default.stringValue
                tf.text = ExtensionService.shared.options[config.id]?.options[key]?.stringValue
                tf.keyboardType = def.type == "number" ? .numbersAndPunctuation : .default
            }
            alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
                let text = alert.textFields?.first?.text ?? ""
                let val: AnyCodableValue = def.type == "number"
                    ? .number(Double(text) ?? 0)
                    : .string(text)
                ExtensionService.shared.setOption(val, key: key, for: config.id)
                self?.reload()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        }
    }
}

// MARK: - UITableViewDataSource + Delegate

extension ExtensionsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sortedConfigs.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ExtensionCell.reuseID,
                                                  for: indexPath) as! ExtensionCell
        let (id, config) = sortedConfigs[indexPath.row]
        let enabled = ExtensionService.shared.options[id]?.enabled ?? true
        cell.configure(config: config, enabled: enabled, hasWorker: ExtensionService.shared.workers[id] != nil)
        cell.onToggle = { [weak self] newValue in
            ExtensionService.shared.setEnabled(newValue, for: id)
            self?.reload()
        }
        cell.onOptions = { [weak self] in
            self?.showOptions(for: config)
        }
        return cell
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        let (id, _) = sortedConfigs[indexPath.row]
        let del = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            done(true)
            self?.deleteExtension(id: id)
        }
        return UISwipeActionsConfiguration(actions: [del])
    }
}

// MARK: - UITextFieldDelegate

extension ExtensionsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        triggerImport(); return true
    }
}

// MARK: - ExtensionCell

private final class ExtensionCell: UITableViewCell {
    static let reuseID = "ExtensionCell"

    var onToggle:  ((Bool) -> Void)?
    var onOptions: (() -> Void)?

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.layer.cornerRadius = 8
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.13, alpha: 1)
        iv.widthAnchor.constraint(equalToConstant: 40).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .bold)
        l.textColor = .white
        return l
    }()

    private let idLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = UIColor(white: 0.45, alpha: 1)
        return l
    }()

    private let statusDot: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 4
        v.widthAnchor.constraint(equalToConstant: 8).isActive = true
        v.heightAnchor.constraint(equalToConstant: 8).isActive = true
        return v
    }()

    private let badgesStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
        return sv
    }()

    private let toggleSwitch: UISwitch = {
        let s = UISwitch()
        s.onTintColor = UIColor(red: 0.239, green: 0.706, blue: 0.949, alpha: 1)
        return s
    }()

    private let optionsButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "gearshape"), for: .normal)
        b.tintColor = UIColor(white: 0.6, alpha: 1)
        return b
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .black
        selectionStyle  = .none

        toggleSwitch.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        optionsButton.addTarget(self, action: #selector(optionsTapped), for: .touchUpInside)

        // Top row: statusDot + nameLabel
        let nameRow = UIStackView(arrangedSubviews: [statusDot, nameLabel])
        nameRow.axis = .horizontal; nameRow.spacing = 6; nameRow.alignment = .center

        // Info column: nameRow + idLabel + badges
        let infoCol = UIStackView(arrangedSubviews: [nameRow, idLabel, badgesStack])
        infoCol.axis = .vertical; infoCol.spacing = 3

        // Right column: options + toggle
        let rightCol = UIStackView(arrangedSubviews: [optionsButton, toggleSwitch])
        rightCol.axis = .vertical; rightCol.spacing = 8; rightCol.alignment = .center

        // Main row: icon + infoCol + spacer + rightCol
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let mainRow = UIStackView(arrangedSubviews: [iconView, infoCol, spacer, rightCol])
        mainRow.axis = .horizontal; mainRow.spacing = 12; mainRow.alignment = .top
        mainRow.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainRow)

        NSLayoutConstraint.activate([
            mainRow.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            mainRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(config: ExtensionConfig, enabled: Bool, hasWorker: Bool) {
        nameLabel.text = config.name
        idLabel.text   = config.id
        toggleSwitch.isOn = enabled

        // Status dot: green if worker loaded, yellow if not
        statusDot.backgroundColor = hasWorker
            ? UIColor(red: 0.2, green: 0.75, blue: 0.3, alpha: 1)
            : UIColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1)

        // Icon
        if let url = URL(string: config.icon) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let img = UIImage(data: data) {
                    DispatchQueue.main.async { self.iconView.image = img }
                }
            }.resume()
        }

        // Rebuild badges
        badgesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let badges: [(String, UIColor)] = [
            (config.version, UIColor(white: 0.2, alpha: 1)),
            (config.type.uppercased(), typeColor(config.type)),
            (config.accuracy.capitalized + " Accuracy", UIColor(white: 0.18, alpha: 1)),
            (config.media, UIColor(white: 0.18, alpha: 1)),
        ]
        for (text, bg) in badges { badgesStack.addArrangedSubview(makeBadge(text, bg: bg)) }
    }

    private func makeBadge(_ text: String, bg: UIColor) -> UILabel {
        let l = UILabel()
        l.text = "  \(text)  "
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .white
        l.backgroundColor = bg
        l.layer.cornerRadius = 4
        l.clipsToBounds = true
        return l
    }

    private func typeColor(_ type: String) -> UIColor {
        switch type {
        case "torrent": return UIColor(red: 0.239, green: 0.706, blue: 0.949, alpha: 1) // custom blue
        case "nzb":     return UIColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 1)       // purple
        default:        return UIColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1)       // green
        }
    }

    @objc private func toggleChanged() { onToggle?(toggleSwitch.isOn) }
    @objc private func optionsTapped() { onOptions?() }
}
