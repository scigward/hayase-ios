// ExtensionsViewController.swift
// Ports extensions.svelte + ExtensionSettings.svelte from scigward/interface exactly.
//
// Two-tab layout (mirrors <Tabs.Root> Extensions | Repositories):
//   [Extensions tab] — list of installed extensions
//     Each card: icon (40×40 rounded), status dot + name (bold) + id (small muted),
//     badges row (version / type / accuracy [ratio?] / media / language emoji),
//     right: gear button (opens settings dialog) + enable/disable switch
//   [Repositories tab] — URL import + grouped list of sources
//     Import row: URL textfield + Import button
//     Source list: GitHub/npm/Globe icon + hostname + count badge

import UIKit

final class ExtensionsViewController: UIViewController {

    // MARK: - State

    private var selectedTab: Int = 0  // 0=Extensions, 1=Repositories

    private var sortedConfigs: [(id: String, config: ExtensionConfig)] {
        ExtensionService.shared.configs
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    // Repositories: group by config.update URL
    private var repositories: [(url: String, configs: [ExtensionConfig])] {
        var groups: [String: [ExtensionConfig]] = [:]
        for config in ExtensionService.shared.configs.values {
            let key = config.update ?? "unknown"
            groups[key, default: []].append(config)
        }
        return groups.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // MARK: - UI

    private var segmentedControl: UISegmentedControl!
    private var tableView: UITableView!
    private var importBar: UIView!
    private var importBarHeightConstraint: NSLayoutConstraint!
    private var importField: UITextField!
    private var importButton: UIButton!
    private var importSpinner: UIActivityIndicatorView!
    private var emptyLabel: UILabel!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Extensions"
        view.backgroundColor = UIColor(white: 0.04, alpha: 1)
        navigationItem.largeTitleDisplayMode = .never

        setupSegmentedControl()
        setupImportBar()
        setupTableView()
        setupEmptyLabel()
        updateTabUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    // MARK: - Setup

    private func setupSegmentedControl() {
        segmentedControl = UISegmentedControl(items: ["Extensions", "Repositories"])
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.selectedSegmentTintColor = UIColor(white: 0.25, alpha: 1)
        segmentedControl.backgroundColor = UIColor(white: 0.1, alpha: 1)
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13, weight: .bold)], for: .selected)
        segmentedControl.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    private func setupImportBar() {
        importBar = UIView()
        importBar.translatesAutoresizingMaskIntoConstraints = false
        importBar.isHidden = true
        view.addSubview(importBar)

        importField = UITextField()
        importField.placeholder = "https://example.com/manifest.json"
        importField.attributedPlaceholder = NSAttributedString(
            string: importField.placeholder ?? "",
            attributes: [.foregroundColor: UIColor(white: 0.4, alpha: 1)])
        importField.backgroundColor = UIColor(white: 0.1, alpha: 1)
        importField.textColor = .white
        importField.tintColor = .white
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
        importButton.setTitle("Import Extensions", for: .normal)
        importButton.setTitleColor(UIColor(white: 0.05, alpha: 1), for: .normal)
        importButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        importButton.backgroundColor = UIColor(red: 0.239, green: 0.706, blue: 0.949, alpha: 1)
        importButton.layer.cornerRadius = 8
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        importButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        importButton.translatesAutoresizingMaskIntoConstraints = false

        importSpinner = UIActivityIndicatorView(style: .medium)
        importSpinner.color = UIColor(white: 0.05, alpha: 1)
        importSpinner.hidesWhenStopped = true
        importSpinner.translatesAutoresizingMaskIntoConstraints = false

        [importField, importButton, importSpinner].forEach { importBar.addSubview($0) }

        importBarHeightConstraint = importBar.heightAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            importBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            importBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            importBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            importBarHeightConstraint,

            importField.leadingAnchor.constraint(equalTo: importBar.leadingAnchor),
            importField.centerYAnchor.constraint(equalTo: importBar.centerYAnchor),
            importField.heightAnchor.constraint(equalToConstant: 40),
            importField.trailingAnchor.constraint(equalTo: importButton.leadingAnchor, constant: -10),

            importButton.trailingAnchor.constraint(equalTo: importBar.trailingAnchor),
            importButton.centerYAnchor.constraint(equalTo: importBar.centerYAnchor),
            importButton.heightAnchor.constraint(equalToConstant: 40),
            importButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),

            importSpinner.centerXAnchor.constraint(equalTo: importButton.centerXAnchor),
            importSpinner.centerYAnchor.constraint(equalTo: importButton.centerYAnchor),
        ])
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = UIColor(white: 0.04, alpha: 1)
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.register(ExtensionCell.self, forCellReuseIdentifier: ExtensionCell.reuseID)
        tableView.register(RepoCell.self, forCellReuseIdentifier: RepoCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.keyboardDismissMode = .onDrag
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: importBar.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel = UILabel()
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Tab switching

    @objc private func tabChanged() {
        selectedTab = segmentedControl.selectedSegmentIndex
        updateTabUI()
        reload()
    }

    private func updateTabUI() {
        let isRepositories = selectedTab == 1
        importBar.isHidden = !isRepositories
        importBarHeightConstraint.constant = isRepositories ? 44 : 0
        tableView.reloadData()
    }

    // MARK: - Reload

    private func reload() {
        tableView.reloadData()

        if selectedTab == 0 {
            // Extensions tab empty state (mirrors {:else} in extensions.svelte)
            let isEmpty = sortedConfigs.isEmpty
            emptyLabel.isHidden = !isEmpty
            if isEmpty {
                let title = NSMutableAttributedString()
                title.append(NSAttributedString(string: "Looks like there's nothing here...\n",
                    attributes: [.font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor.white]))
                title.append(NSAttributedString(string: "Import some extensions in the Repositories tab.",
                    attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor(white: 0.45, alpha: 1)]))
                emptyLabel.attributedText = title
            }
        } else {
            // Repositories tab empty state
            let isEmpty = repositories.isEmpty
            emptyLabel.isHidden = !isEmpty
            if isEmpty {
                let title = NSMutableAttributedString()
                title.append(NSAttributedString(string: "Looks like there's nothing here...\n",
                    attributes: [.font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor.white]))
                title.append(NSAttributedString(string: "Import some extensions in the field above.",
                    attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor(white: 0.45, alpha: 1)]))
                emptyLabel.attributedText = title
            }
        }
    }

    // MARK: - Import

    @objc private func importTapped() { triggerImport() }

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
                self.importButton.setTitle("Import Extensions", for: .normal)
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

    // MARK: - Options dialog (mirrors ExtensionSettings.svelte Dialog.Root)

    private func showOptions(for config: ExtensionConfig) {
        let opts = config.options ?? [:]

        if opts.isEmpty {
            // No options — just show delete (mirrors <Button variant='ghost' on:click={deleteExtension}>)
            let alert = UIAlertController(title: config.name, message: "This extension has no configurable options.", preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Delete Extension", style: .destructive) { [weak self] _ in
                self?.deleteExtension(id: config.id)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.popoverPresentationController?.sourceView = view
            present(alert, animated: true)
            return
        }

        // Has options — show options dialog (mirrors Dialog.Root with options list)
        let alert = UIAlertController(title: "\(config.name) Settings", message: nil, preferredStyle: .actionSheet)
        for (key, opt) in opts.sorted(by: { $0.key < $1.key }) {
            let current = ExtensionService.shared.options[config.id]?.options[key]?.stringValue ?? opt.default.stringValue
            alert.addAction(UIAlertAction(title: "\(opt.description): \(current)", style: .default) { [weak self] _ in
                self?.editOption(key: key, def: opt, config: config)
            })
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
            let cur = ExtensionService.shared.options[config.id]?.options[key]
            let newVal: AnyCodableValue = (cur == .bool(true)) ? .bool(false) : .bool(true)
            ExtensionService.shared.setOption(newVal, key: key, for: config.id)
            reload()
        case "select":
            let sheet = UIAlertController(title: def.description, message: nil, preferredStyle: .actionSheet)
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
            let alert = UIAlertController(title: def.description, message: nil, preferredStyle: .alert)
            alert.addTextField { tf in
                tf.placeholder = def.default.stringValue
                tf.text = ExtensionService.shared.options[config.id]?.options[key]?.stringValue
                tf.keyboardType = def.type == "number" ? .numbersAndPunctuation : .default
            }
            alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
                let text = alert.textFields?.first?.text ?? ""
                let val: AnyCodableValue = def.type == "number" ? .number(Double(text) ?? 0) : .string(text)
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
        selectedTab == 0 ? sortedConfigs.count : repositories.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if selectedTab == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: ExtensionCell.reuseID,
                                                       for: indexPath) as! ExtensionCell
            let (id, config) = sortedConfigs[indexPath.row]
            let enabled = ExtensionService.shared.options[id]?.enabled ?? true
            let hasWorker = ExtensionService.shared.workers[id] != nil
            cell.configure(config: config, enabled: enabled, hasWorker: hasWorker)
            cell.onToggle = { [weak self] newValue in
                ExtensionService.shared.setEnabled(newValue, for: id)
                self?.reload()
            }
            cell.onOptions = { [weak self] in self?.showOptions(for: config) }
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: RepoCell.reuseID,
                                                       for: indexPath) as! RepoCell
            let repo = repositories[indexPath.row]
            cell.configure(url: repo.url, count: repo.configs.count)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        guard selectedTab == 0 else { return nil }
        let (id, _) = sortedConfigs[indexPath.row]
        let del = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            done(true); self?.deleteExtension(id: id)
        }
        return UISwipeActionsConfiguration(actions: [del])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - UITextFieldDelegate

extension ExtensionsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        triggerImport(); return true
    }
}

// MARK: - ExtensionCell (mirrors each card in extensions.svelte Extensions tab)

final class ExtensionCell: UITableViewCell {
    static let reuseID = "ExtensionCell"

    var onToggle:  ((Bool) -> Void)?
    var onOptions: (() -> Void)?

    // Left: icon
    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.layer.cornerRadius = 8   // 'rounded-md' ≈ 8px
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.13, alpha: 1) // bg-neutral-900
        iv.widthAnchor.constraint(equalToConstant: 40).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return iv
    }()

    // Status dot (mirrors <StatusDot variant='PENDING|COMPLETED|DROPPED' />)
    private let statusDot: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 4
        v.widthAnchor.constraint(equalToConstant: 8).isActive = true
        v.heightAnchor.constraint(equalToConstant: 8).isActive = true
        return v
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .bold) // 'text-md font-bold'
        l.textColor = .white
        return l
    }()

    private let idLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = UIColor(white: 0.45, alpha: 1) // 'text-xs text-muted-foreground'
        return l
    }()

    // Badges row (version / type / accuracy / ratio? / media / emoji flags)
    private let badgesStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        return sv
    }()

    // Language emoji label (shown after badges if config.languages present)
    private let flagsLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18)
        l.textColor = .white
        return l
    }()

    // Right: options gear button + enable/disable switch
    private let optionsButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "gearshape"), for: .normal)
        b.tintColor = UIColor(white: 0.6, alpha: 1)
        return b
    }()

    private let toggleSwitch: UISwitch = {
        let s = UISwitch()
        s.onTintColor = UIColor(red: 0.239, green: 0.706, blue: 0.949, alpha: 1)
        s.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        return s
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor(white: 0.04, alpha: 1)
        selectionStyle = .none

        toggleSwitch.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        optionsButton.addTarget(self, action: #selector(optionsTapped), for: .touchUpInside)

        // Card container (mirrors bg-neutral-950 px-4 py-3 rounded-md)
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.067, alpha: 1)
        card.layer.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        // Name row: statusDot + nameLabel
        let nameRow = UIStackView(arrangedSubviews: [statusDot, nameLabel])
        nameRow.axis = .horizontal; nameRow.spacing = 6; nameRow.alignment = .center

        // Badges + flags row
        let badgeRow = UIStackView(arrangedSubviews: [badgesStack, flagsLabel])
        badgeRow.axis = .horizontal; badgeRow.spacing = 8; badgeRow.alignment = .center

        // Info column (left side of card)
        let infoCol = UIStackView(arrangedSubviews: [nameRow, idLabel, badgeRow])
        infoCol.axis = .vertical; infoCol.spacing = 4

        // Right column (mirrors flex justify-between flex-col items-end)
        let rightCol = UIStackView(arrangedSubviews: [optionsButton, toggleSwitch])
        rightCol.axis = .vertical; rightCol.spacing = 10; rightCol.alignment = .center

        // Main row: icon + infoCol + spacer + rightCol
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let mainRow = UIStackView(arrangedSubviews: [iconView, infoCol, spacer, rightCol])
        mainRow.axis = .horizontal; mainRow.spacing = 12; mainRow.alignment = .top
        mainRow.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(mainRow)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            mainRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            mainRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            mainRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            mainRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(config: ExtensionConfig, enabled: Bool, hasWorker: Bool) {
        nameLabel.text  = config.name
        idLabel.text    = config.id
        toggleSwitch.isOn = enabled

        // Status dot colour (PENDING=yellow, COMPLETED=green, DROPPED=red)
        statusDot.backgroundColor = hasWorker
            ? UIColor(red: 0.325, green: 0.855, blue: 0.200, alpha: 1)  // COMPLETED (green)
            : UIColor(red: 0.900, green: 0.700, blue: 0.100, alpha: 1)  // PENDING (yellow)

        // Options button: show gear if has options, trash if no options
        let hasOpts = !(config.options?.isEmpty ?? true)
        let iconName = hasOpts ? "gearshape" : "trash"
        let iconColor: UIColor = hasOpts ? UIColor(white: 0.6, alpha: 1) : UIColor.systemRed
        optionsButton.setImage(UIImage(systemName: iconName), for: .normal)
        optionsButton.tintColor = iconColor

        // Icon image
        iconView.image = nil
        if let url = URL(string: config.icon) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data, let img = UIImage(data: data) {
                    DispatchQueue.main.async { self.iconView.image = img }
                }
            }.resume()
        }

        // Rebuild badges (mirrors version/type/accuracy/ratio/media badges in Hayase)
        badgesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Version
        addBadge(config.version, bg: UIColor(white: 0.18, alpha: 1))

        // Type (Torrent / NZB / URL)
        let typeMap = ["torrent": "Torrent", "nzb": "NZB", "url": "URL"]
        addBadge(typeMap[config.type] ?? config.type.uppercased(), bg: UIColor(white: 0.18, alpha: 1))

        // Accuracy (e.g. "High Accuracy")
        addBadge(config.accuracy.capitalized + " Accuracy", bg: UIColor(white: 0.18, alpha: 1))

        // Ratio (if present)
        if let ratio = config.ratio, ratio != .null {
            addBadge("\(ratio.stringValue) Ratio", bg: UIColor(white: 0.18, alpha: 1))
        }

        // Media (e.g. "anime", "book")
        addBadge(config.media.capitalized, bg: UIColor(white: 0.18, alpha: 1))

        // Language emoji flags
        if let langs = config.languages, !langs.isEmpty {
            flagsLabel.text = langs.compactMap { codeToEmoji($0) }.joined()
            flagsLabel.isHidden = false
        } else {
            flagsLabel.text = nil
            flagsLabel.isHidden = true
        }
    }

    private func addBadge(_ text: String, bg: UIColor) {
        let l = UILabel()
        l.text = "  \(text)  "
        l.font = .systemFont(ofSize: 10, weight: .bold)
        l.textColor = UIColor(white: 0.85, alpha: 1) // text-neutral-300
        l.backgroundColor = bg
        l.layer.cornerRadius = 4
        l.clipsToBounds = true
        l.setContentHuggingPriority(.required, for: .horizontal)
        badgesStack.addArrangedSubview(l)
    }

    @objc private func toggleChanged() { onToggle?(toggleSwitch.isOn) }
    @objc private func optionsTapped() { onOptions?() }
}

// MARK: - RepoCell (mirrors Repositories tab list item)

final class RepoCell: UITableViewCell {
    static let reuseID = "RepoCell"

    private let sourceIcon: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = UIColor(white: 0.45, alpha: 1)
        iv.widthAnchor.constraint(equalToConstant: 20).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return iv
    }()

    private let urlLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = .white
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }()

    private let countLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = UIColor(white: 0.45, alpha: 1)
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor(white: 0.04, alpha: 1)
        selectionStyle = .none

        let card = UIView()
        card.backgroundColor = UIColor(white: 0.067, alpha: 1)
        card.layer.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        let spacer = UIView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [sourceIcon, urlLabel, spacer, countLabel])
        row.axis = .horizontal; row.spacing = 10; row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(url: String, count: Int) {
        // Determine icon (GitHub / npm / Globe) — mirrors Hayase Repositories tab
        if url.hasPrefix("gh:") || url.contains("github.com") {
            sourceIcon.image = UIImage(systemName: "chevron.left.forwardslash.chevron.right")
        } else if url.hasPrefix("npm:") {
            sourceIcon.image = UIImage(systemName: "shippingbox")
        } else {
            sourceIcon.image = UIImage(systemName: "globe")
        }

        // Display: hostname for http URLs, full for gh:/npm:
        if url.hasPrefix("http"), let parsed = URL(string: url) {
            urlLabel.text = parsed.host ?? url
        } else {
            urlLabel.text = url
        }

        countLabel.text = "\(count) Extension\(count == 1 ? "" : "s")"
    }
}

// MARK: - Country code → emoji flag (mirrors codeToEmoji from $lib/utils)

private func codeToEmoji(_ code: String) -> String? {
    let base: UInt32 = 127397
    var emoji = ""
    for scalar in code.uppercased().unicodeScalars {
        guard let emojiScalar = Unicode.Scalar(base + scalar.value) else { return nil }
        emoji.append(Character(emojiScalar))
    }
    return emoji.isEmpty ? nil : emoji
}
