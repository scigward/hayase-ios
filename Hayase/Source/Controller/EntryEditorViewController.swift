import UIKit

/// Entry editor modal matching Hayase interface's EntryEditor.svelte.
/// Layout: banner/cover image at top, anime title, Status dropdown, Score dropdown,
/// Progress input, Rewatched Times input, Save/Cancel/Delete buttons.
final class EntryEditorViewController: UIViewController {

    var mediaID: Int = 0
    var totalEpisodes: Int?
    var currentEntry: AnimeItem.MediaListEntry?
    var animeTitle: String = ""
    var coverURL: String?
    var bannerURL: String?

    var onSave: (() -> Void)?
    var onDelete: (() -> Void)?

    // MARK: - Status constants matching interface EntryEditor.svelte STATUS_LABELS
    private let statusValues  = ["CURRENT", "PLANNING", "COMPLETED", "PAUSED", "DROPPED", "REPEATING"]
    private let statusLabels  = ["Watching", "Plan to Watch", "Completed", "Paused", "Dropped", "Re-Watching"]

    private var selectedStatusIndex: Int = 0
    private var selectedScore: Int = 0
    private var progressValue: Int = 0
    private var repeatValue: Int = 0

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // Banner image (top)
    private let bannerImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.08, alpha: 1)
        return iv
    }()

    // Title
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 20, weight: .semibold)
        l.textColor = .white
        l.numberOfLines = 2
        return l
    }()

    // Status
    private let statusButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Watching", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor(white: 0.12, alpha: 1)
        b.layer.cornerRadius = 8
        b.contentHorizontalAlignment = .leading
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        b.titleLabel?.font = .systemFont(ofSize: 15)
        return b
    }()

    // Score
    private let scoreButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("0", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor(white: 0.12, alpha: 1)
        b.layer.cornerRadius = 8
        b.contentHorizontalAlignment = .leading
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        b.titleLabel?.font = .systemFont(ofSize: 15)
        return b
    }()

    // Progress
    private let progressField: UITextField = {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textColor = .white
        tf.backgroundColor = UIColor(white: 0.12, alpha: 1)
        tf.layer.cornerRadius = 8
        tf.font = .systemFont(ofSize: 15)
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        tf.leftViewMode = .always
        tf.attributedPlaceholder = NSAttributedString(string: "0", attributes: [.foregroundColor: UIColor(white: 0.5, alpha: 1)])
        return tf
    }()

    // Repeat
    private let repeatField: UITextField = {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textColor = .white
        tf.backgroundColor = UIColor(white: 0.12, alpha: 1)
        tf.layer.cornerRadius = 8
        tf.font = .systemFont(ofSize: 15)
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        tf.leftViewMode = .always
        tf.attributedPlaceholder = NSAttributedString(string: "0", attributes: [.foregroundColor: UIColor(white: 0.5, alpha: 1)])
        return tf
    }()

    // Buttons
    private let saveButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Save Changes", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor(white: 0.20, alpha: 1)
        b.layer.cornerRadius = 8
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        return b
    }()

    private let cancelButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Cancel", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 8
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        return b
    }()

    private let deleteButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Delete", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1)
        b.layer.cornerRadius = 8
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        return b
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)

        // Populate from current entry
        if let entry = currentEntry {
            if let idx = statusValues.firstIndex(of: entry.status ?? "CURRENT") {
                selectedStatusIndex = idx
            }
            selectedScore = entry.score
            progressValue = entry.progress
            repeatValue = entry.repeatCount
        }

        setupUI()
        updateStatusButton()
        updateScoreButton()
        progressField.text = progressValue > 0 ? "\(progressValue)" : ""
        repeatField.text = repeatValue > 0 ? "\(repeatValue)" : ""
        titleLabel.text = animeTitle

        // Load banner image
        if let urlStr = bannerURL ?? coverURL, let url = URL(string: urlStr) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async { self?.bannerImageView.image = img }
            }.resume()
        }
    }

    // MARK: - Setup

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        // Banner
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(bannerImageView)

        // Title container (px-5 pt-4)
        let titleContainer = UIView()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addSubview(titleLabel)
        contentStack.addArrangedSubview(titleContainer)

        // Fields container (px-5 py-3 grid-cols-2 gap-5)
        let fieldsContainer = UIView()
        let statusLabel = makeFieldLabel("Status")
        let scoreLabel = makeFieldLabel("Score")
        let progressLabel = makeFieldLabel("Progress")
        let repeatLabel = makeFieldLabel("Rewatched Times")

        [statusLabel, statusButton, scoreLabel, scoreButton,
         progressLabel, progressField, repeatLabel, repeatField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            fieldsContainer.addSubview($0)
        }
        contentStack.addArrangedSubview(fieldsContainer)

        // Buttons container (px-4 py-3 gap-3) — use UIStackView so hidden button
        // collapses automatically without leaving dead space
        let buttonsStack = UIStackView()
        buttonsStack.axis = .vertical
        buttonsStack.spacing = 12
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        [saveButton, cancelButton, deleteButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            buttonsStack.addArrangedSubview($0)
        }
        let buttonsContainer = UIView()
        buttonsContainer.addSubview(buttonsStack)
        contentStack.addArrangedSubview(buttonsContainer)

        // Actions
        statusButton.addTarget(self, action: #selector(statusTapped), for: .touchUpInside)
        scoreButton.addTarget(self, action: #selector(scoreTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        // Hide delete if no existing entry
        deleteButton.isHidden = currentEntry == nil

        // Constraints
        let halfWidth = (UIScreen.main.bounds.width - 20 - 20 - 20) / 2

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Banner: 150pt height
            bannerImageView.heightAnchor.constraint(equalToConstant: 150),

            // Title: px-5 pt-4
            titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor, constant: -20),
            titleLabel.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor),
            titleContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Fields: 2-column grid with gap-5 (20pt)
            statusLabel.topAnchor.constraint(equalTo: fieldsContainer.topAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: fieldsContainer.leadingAnchor, constant: 20),

            statusButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            statusButton.leadingAnchor.constraint(equalTo: fieldsContainer.leadingAnchor, constant: 20),
            statusButton.widthAnchor.constraint(equalToConstant: halfWidth),
            statusButton.heightAnchor.constraint(equalToConstant: 40),

            scoreLabel.topAnchor.constraint(equalTo: fieldsContainer.topAnchor, constant: 12),
            scoreLabel.leadingAnchor.constraint(equalTo: statusButton.trailingAnchor, constant: 20),

            scoreButton.topAnchor.constraint(equalTo: scoreLabel.bottomAnchor, constant: 8),
            scoreButton.leadingAnchor.constraint(equalTo: statusButton.trailingAnchor, constant: 20),
            scoreButton.widthAnchor.constraint(equalToConstant: halfWidth),
            scoreButton.heightAnchor.constraint(equalToConstant: 40),

            progressLabel.topAnchor.constraint(equalTo: statusButton.bottomAnchor, constant: 20),
            progressLabel.leadingAnchor.constraint(equalTo: fieldsContainer.leadingAnchor, constant: 20),

            progressField.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 8),
            progressField.leadingAnchor.constraint(equalTo: fieldsContainer.leadingAnchor, constant: 20),
            progressField.widthAnchor.constraint(equalToConstant: halfWidth),
            progressField.heightAnchor.constraint(equalToConstant: 40),

            repeatLabel.topAnchor.constraint(equalTo: scoreButton.bottomAnchor, constant: 20),
            repeatLabel.leadingAnchor.constraint(equalTo: progressField.trailingAnchor, constant: 20),

            repeatField.topAnchor.constraint(equalTo: repeatLabel.bottomAnchor, constant: 8),
            repeatField.leadingAnchor.constraint(equalTo: progressField.trailingAnchor, constant: 20),
            repeatField.widthAnchor.constraint(equalToConstant: halfWidth),
            repeatField.heightAnchor.constraint(equalToConstant: 40),
            repeatField.bottomAnchor.constraint(equalTo: fieldsContainer.bottomAnchor, constant: -12),

            // Buttons: vertical stack via UIStackView, px-4 py-3
            buttonsStack.topAnchor.constraint(equalTo: buttonsContainer.topAnchor, constant: 12),
            buttonsStack.leadingAnchor.constraint(equalTo: buttonsContainer.leadingAnchor, constant: 16),
            buttonsStack.trailingAnchor.constraint(equalTo: buttonsContainer.trailingAnchor, constant: -16),
            buttonsStack.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor, constant: -16),

            saveButton.heightAnchor.constraint(equalToConstant: 40),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),
            deleteButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func makeFieldLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 14, weight: .bold)
        l.textColor = UIColor(white: 0.649, alpha: 1.0)
        return l
    }

    // MARK: - Button states

    private func updateStatusButton() {
        statusButton.setTitle(statusLabels[selectedStatusIndex], for: .normal)
    }

    private func updateScoreButton() {
        scoreButton.setTitle("\(selectedScore)", for: .normal)
    }

    // MARK: - Actions

    @objc private func statusTapped() {
        let alert = UIAlertController(title: "Status", message: nil, preferredStyle: .actionSheet)
        for (i, label) in statusLabels.enumerated() {
            let title = (i == selectedStatusIndex) ? "✓ \(label)" : label
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.selectedStatusIndex = i
                self?.updateStatusButton()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = statusButton
        present(alert, animated: true)
    }

    @objc private func scoreTapped() {
        let alert = UIAlertController(title: "Score", message: nil, preferredStyle: .actionSheet)
        for score in 0...10 {
            let title = (score == selectedScore) ? "✓ \(score)" : "\(score)"
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.selectedScore = score
                self?.updateScoreButton()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = scoreButton
        present(alert, animated: true)
    }

    @objc private func saveTapped() {
        let status = statusValues[selectedStatusIndex]
        let progress = Int(progressField.text ?? "") ?? progressValue
        let repeatCount = Int(repeatField.text ?? "") ?? repeatValue
        let score = selectedScore

        AniListTracking.shared.entry(mediaID: mediaID,
                                     status: status,
                                     progress: progress,
                                     score: score,
                                     repeatCount: repeatCount) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onSave?()
                self?.dismiss(animated: true)
            }
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func deleteTapped() {
        guard let listID = currentEntry?.listID else {
            dismiss(animated: true)
            return
        }
        AniListTracking.shared.deleteEntry(listID: listID) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onDelete?()
                self?.dismiss(animated: true)
            }
        }
    }
}
