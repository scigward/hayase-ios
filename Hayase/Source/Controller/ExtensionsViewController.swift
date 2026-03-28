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
        view.backgroundColor = .black
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
        // Hayase Tabs.List: bg-muted rounded-lg; active = bg-primary (white) text-background (dark); inactive = text-muted-foreground (gray)
        // --muted = #27272a, --primary = #fafafa, --primary-foreground = #18181b, --muted-foreground = #a1a1aa
        segmentedControl = UISegmentedControl(items: ["Extensions", "Repositories"])
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.selectedSegmentTintColor = UIColor(red: 250/255, green: 250/255, blue: 250/255, alpha: 1) // primary #fafafa
        segmentedControl.backgroundColor = UIColor(red: 39/255, green: 39/255, blue: 42/255, alpha: 1)            // muted #27272a
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor(red: 161/255, green: 161/255, blue: 170/255, alpha: 1)], for: .normal) // muted-foreground #a1a1aa
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor(red: 24/255, green: 24/255, blue: 27/255, alpha: 1), .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected) // primary-foreground #18181b
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

        // Input: bg-neutral-950 border-none (Hayase)
        importField = UITextField()
        importField.placeholder = "https://example.com/manifest.json"
        importField.attributedPlaceholder = NSAttributedString(
            string: importField.placeholder ?? "",
            attributes: [.foregroundColor: UIColor(white: 0.4, alpha: 1)])
        importField.backgroundColor = UIColor(white: 0.039, alpha: 1)  // bg-neutral-950
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

        // Button: default variant = bg-primary text-primary-foreground, size=default = h-9(36pt) px-4(16pt) py-2(8pt)
        // primary = #fafafa (white), primary-foreground = #18181b (dark)
        importButton = UIButton(type: .system)
        importButton.setImage(
            UIImage(systemName: "plus",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)),
            for: .normal)
        importButton.setTitle("Import Extensions", for: .normal)
        importButton.setTitleColor(UIColor(red: 24/255, green: 24/255, blue: 27/255, alpha: 1), for: .normal)
        importButton.tintColor = UIColor(red: 24/255, green: 24/255, blue: 27/255, alpha: 1)
        importButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        importButton.backgroundColor = UIColor(red: 250/255, green: 250/255, blue: 250/255, alpha: 1)  // primary #fafafa
        importButton.layer.cornerRadius = 8
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        // px-4=16pt, py-2=8pt. Icon mr-2 gap via imageEdgeInsets.
        importButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        importButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
        importButton.translatesAutoresizingMaskIntoConstraints = false

        importSpinner = UIActivityIndicatorView(style: .medium)
        importSpinner.color = UIColor(red: 24/255, green: 24/255, blue: 27/255, alpha: 1)  // primary-foreground
        importSpinner.hidesWhenStopped = true
        importSpinner.translatesAutoresizingMaskIntoConstraints = false

        [importField, importButton, importSpinner].forEach { importBar.addSubview($0) }

        // Hayase mobile: flex-col — input on top, button full-width below (gap-3 = 12pt)
        let importBarCollapsedHeight: CGFloat = 0
        importBarHeightConstraint = importBar.heightAnchor.constraint(equalToConstant: importBarCollapsedHeight)
        NSLayoutConstraint.activate([
            importBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            importBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            importBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            importBarHeightConstraint,

            importField.topAnchor.constraint(equalTo: importBar.topAnchor),
            importField.leadingAnchor.constraint(equalTo: importBar.leadingAnchor),
            importField.trailingAnchor.constraint(equalTo: importBar.trailingAnchor),
            importField.heightAnchor.constraint(equalToConstant: 40),

            importButton.topAnchor.constraint(equalTo: importField.bottomAnchor, constant: 10),
            importButton.leadingAnchor.constraint(equalTo: importBar.leadingAnchor),
            importButton.trailingAnchor.constraint(equalTo: importBar.trailingAnchor),
            importButton.heightAnchor.constraint(equalToConstant: 36),  // h-9 = 36pt
            importButton.bottomAnchor.constraint(equalTo: importBar.bottomAnchor),

            importSpinner.centerXAnchor.constraint(equalTo: importButton.centerXAnchor),
            importSpinner.centerYAnchor.constraint(equalTo: importButton.centerYAnchor),
        ])
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
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
            tableView.topAnchor.constraint(equalTo: importBar.bottomAnchor, constant: 4),
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
        // 40pt input + 10pt gap + 36pt button = 86pt (h-9 button, gap-3 between input and button)
        importBarHeightConstraint.constant = isRepositories ? 86 : 0
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
        importButton.setImage(nil, for: .normal)
        importSpinner.startAnimating()
        importButton.isEnabled = false

        Task { @MainActor in
            defer {
                self.importSpinner.stopAnimating()
                self.importButton.setTitle("Import Extensions", for: .normal)
                self.importButton.setImage(
                    UIImage(systemName: "plus",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)),
                    for: .normal)
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

    // icon: size-10 rounded-md bg-neutral-900
    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.layer.cornerRadius = 8
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 23/255, alpha: 1)  // bg-neutral-900 #171717
        iv.widthAnchor.constraint(equalToConstant: 40).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return iv
    }()

    // Status dot — PENDING(gray)/COMPLETED(green)/DROPPED(red) from Hayase StatusDot.svelte
    private let statusDot: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 4
        v.widthAnchor.constraint(equalToConstant: 8).isActive = true
        v.heightAnchor.constraint(equalToConstant: 8).isActive = true
        return v
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

    // Badges: wrapping flow view (Hayase: flex-wrap gap-2)
    private let badgesView = BadgeFlowView()

    // Right: Bolt (settings) or Trash (delete) + switch (Hayase ExtensionSettings.svelte)
    private let optionsButton: UIButton = {
        let b = UIButton(type: .system)
        b.tintColor = UIColor(white: 0.6, alpha: 1)
        return b
    }()

    private let toggleSwitch: UISwitch = {
        let s = UISwitch()
        // Hayase switch.svelte: data-[state=checked]:bg-primary (#fafafa), thumb = bg-background (#09090b)
        s.onTintColor = UIColor(red: 250/255, green: 250/255, blue: 250/255, alpha: 1)  // primary #fafafa
        s.thumbTintColor = UIColor(red: 9/255, green: 9/255, blue: 11/255, alpha: 1)    // background #09090b
        s.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        return s
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .black
        selectionStyle = .none

        toggleSwitch.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        optionsButton.addTarget(self, action: #selector(optionsTapped), for: .touchUpInside)

        // Card: bg-neutral-950 on black background — neutral-950 (#0a0a0a) on black (#000)
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.039, alpha: 1)  // bg-neutral-950
        card.layer.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        // name row: statusDot + nameLabel (inline, matching Hayase StatusDot before name)
        let nameRow = UIStackView(arrangedSubviews: [statusDot, nameLabel])
        nameRow.axis = .horizontal; nameRow.spacing = 6; nameRow.alignment = .center

        // nameIdCol: name row + id (flex-col)
        let nameIdCol = UIStackView(arrangedSubviews: [nameRow, idLabel])
        nameIdCol.axis = .vertical; nameIdCol.spacing = 3

        // topRow: icon + nameIdCol (flex-row space-x-3, items-center)
        let topRow = UIStackView(arrangedSubviews: [iconView, nameIdCol])
        topRow.axis = .horizontal; topRow.spacing = 12; topRow.alignment = .center

        // badgesView needs TAMIC = false for use inside UIStackView
        badgesView.translatesAutoresizingMaskIntoConstraints = false

        // leftCol: topRow + wrapping badges (flex-col space-y-3)
        let leftCol = UIStackView(arrangedSubviews: [topRow, badgesView])
        leftCol.axis = .vertical; leftCol.spacing = 12

        // rightCol: flex justify-between flex-col items-end pb-1.5 (Hayase ExtensionSettings)
        // Flexible spacer between bolt/trash and switch replicates justify-between / mt-auto.
        let rightSpacer = UIView()
        rightSpacer.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        rightSpacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
        let rightCol = UIStackView(arrangedSubviews: [optionsButton, rightSpacer, toggleSwitch])
        rightCol.axis = .vertical; rightCol.spacing = 0; rightCol.alignment = .trailing
        // pb-1.5 = 6pt bottom padding on right column (inside the card's bottom padding)
        rightCol.isLayoutMarginsRelativeArrangement = true
        rightCol.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 6, right: 0)

        // outerRow: leftCol fills available width; rightCol stretches to full card height (.fill)
        let outerRow = UIStackView(arrangedSubviews: [leftCol, rightCol])
        outerRow.axis = .horizontal; outerRow.spacing = 12; outerRow.alignment = .fill
        outerRow.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(outerRow)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            outerRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            outerRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            outerRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            outerRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(config: ExtensionConfig, enabled: Bool, hasWorker: Bool) {
        nameLabel.text  = config.name
        idLabel.text    = config.id
        toggleSwitch.isOn = enabled

        // Status dot colors from Hayase StatusDot.svelte:
        // COMPLETED = rgb(123,213,85) green; PENDING = rgb(180,180,180) gray
        statusDot.backgroundColor = hasWorker
            ? UIColor(red: 123/255, green: 213/255, blue: 85/255, alpha: 1)   // COMPLETED
            : UIColor(white: 180/255, alpha: 1)                               // PENDING

        // Options button: Bolt icon when has options (Hayase <Bolt size={18} />), Trash when none
        let hasOpts = !(config.options?.isEmpty ?? true)
        let iconName = hasOpts ? "bolt" : "trash"
        let iconColor: UIColor = hasOpts ? UIColor(white: 0.6, alpha: 1) : .systemRed
        optionsButton.setImage(
            UIImage(systemName: iconName,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)),
            for: .normal)
        optionsButton.tintColor = iconColor

        // Icon image
        iconView.image = nil
        if let url = URL(string: config.icon) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data, let img = UIImage(data: data) {
                    DispatchQueue.main.async { self?.iconView.image = img }
                }
            }.resume()
        }

        // Build badge items (matches Hayase flex-wrap badge row + flags)
        let typeMap = ["torrent": "Torrent", "nzb": "NZB", "url": "URL"]
        var items: [BadgeFlowView.Item] = []
        items.append(.badge(config.version))
        items.append(.badge(typeMap[config.type] ?? config.type.uppercased()))
        items.append(.badge(config.accuracy.capitalized + " Accuracy"))
        if let ratio = config.ratio, ratio != .null {
            items.append(.badge("\(ratio.stringValue) Ratio"))
        }
        items.append(.badge(config.media.capitalized))
        // Language emoji flags (Hayase: font-twemoji text-xl leading-none)
        if let langs = config.languages, !langs.isEmpty {
            let flags = langs.compactMap { codeToEmoji($0) }.joined()
            if !flags.isEmpty { items.append(.flags(flags)) }
        }
        badgesView.setItems(items)
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
        backgroundColor = .black
        selectionStyle = .none
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.039, alpha: 1)
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
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
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

// MARK: - BadgeFlowView
// Implements Hayase's `flex-wrap gap-2` badge row.
// Contains regular pill badges (bg-neutral-900, rounded, font-bold) and optional emoji flags.

final class BadgeFlowView: UIView {

    enum Item {
        /// Standard badge: rounded bg-neutral-900 pill with bold text, px-3 py-0.5
        case badge(String)
        /// Language emoji flags: text-xl, no background
        case flags(String)
    }

    // UILabel subclass that adds px-3 (12pt) horizontal and py-0.5 (2pt) vertical padding,
    // matching Hayase's `rounded px-3 py-0.5 font-bold bg-neutral-900 leading-snug text-sm` badge style.
    private final class PaddedBadgeLabel: UILabel {
        let hPad: CGFloat = 12  // px-3
        let vPad: CGFloat = 2   // py-0.5

        override var intrinsicContentSize: CGSize {
            let base = super.intrinsicContentSize
            return CGSize(width: base.width + hPad * 2, height: base.height + vPad * 2)
        }

        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.insetBy(dx: hPad, dy: vPad))
        }
    }

    private var labels: [UILabel] = []
    private let hSpacing: CGFloat = 8   // gap-2 = 8pt
    private let vSpacing: CGFloat = 4

    func setItems(_ items: [Item]) {
        labels.forEach { $0.removeFromSuperview() }
        labels = items.map { item in
            switch item {
            case .badge(let text):
                let l = PaddedBadgeLabel()
                l.text = text
                l.font = .systemFont(ofSize: 13, weight: .bold)         // text-sm font-bold
                l.textColor = UIColor(white: 212/255, alpha: 1)         // text-neutral-300 #d4d4d4
                l.backgroundColor = UIColor(white: 23/255, alpha: 1)   // bg-neutral-900 #171717
                l.layer.cornerRadius = 4                                // rounded = 4pt
                l.clipsToBounds = true
                addSubview(l)
                return l
            case .flags(let text):
                let l = UILabel()
                l.text = text
                l.font = .systemFont(ofSize: 20)  // text-xl = 20pt
                l.textColor = .white
                addSubview(l)
                return l
            }
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func flowHeight(for width: CGFloat) -> CGFloat {
        guard !labels.isEmpty, width > 0 else { return 0 }
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for l in labels {
            let sz = l.intrinsicContentSize
            if x > 0, x + sz.width > width {
                x = 0; y += rowH + vSpacing; rowH = 0
            }
            x += sz.width + hSpacing
            rowH = max(rowH, sz.height)
        }
        return y + rowH
    }

    // Called by UITableView.automaticDimension to determine cell height.
    // targetSize.width is the constrained width; return height that fits.
    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority h: UILayoutPriority,
        verticalFittingPriority v: UILayoutPriority
    ) -> CGSize {
        let w = targetSize.width > 0 ? targetSize.width : bounds.width
        return CGSize(width: w, height: max(1, flowHeight(for: w)))
    }

    override var intrinsicContentSize: CGSize {
        let w = bounds.width > 0 ? bounds.width : (superview?.bounds.width ?? UIScreen.main.bounds.width - 120)
        return CGSize(width: UIView.noIntrinsicMetric, height: flowHeight(for: w))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !labels.isEmpty else { return }
        let width = bounds.width
        guard width > 0 else { return }
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for l in labels {
            let sz = l.intrinsicContentSize
            if x > 0, x + sz.width > width {
                x = 0; y += rowH + vSpacing; rowH = 0
            }
            l.frame = CGRect(x: x, y: y, width: sz.width, height: sz.height)
            x += sz.width + hSpacing
            rowH = max(rowH, sz.height)
        }
    }
}
