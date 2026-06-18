import UIKit

/// Entry editor modal matching Hayase interface's EntryEditor.svelte exactly.
///
/// Web layout:
/// - Dialog.Content: centered overlay, max-w-3xl (768px), max-h-[80%], p-0, bg-background, border, sm:rounded-lg
/// - Inner: flex-col sm:flex-row (vertical on phone, horizontal on tablet)
/// - Image: phone = banner w-full h-[150px], tablet = cover sm:w-[260px] sm:h-[400px]
/// - Form: title, 2-col (sm) / 1-col grid of fields, buttons (flex-col sm:flex-row-reverse)
final class EntryEditorViewController: UIViewController, UIViewControllerTransitioningDelegate {

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

    /// Whether to use wide (tablet) layout: side-by-side image + form.
    private var isWide: Bool { traitCollection.horizontalSizeClass == .regular }

    // MARK: - Theme colors (interface Default / Blackout)
    // --background: hsl(0 0% 0%)
    private static let bgBackground  = UIColor.HayaseTheme.background
    // --border / --input: HSL(240, 3.7%, 15.9%)
    private static let borderInput   = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
    // --muted-foreground: hsl(0 0% 50%)
    private static let mutedFG       = UIColor.HayaseTheme.mutedForeground
    // --primary: HSL(0, 0%, 98%)
    private static let primary       = UIColor(white: 0.98, alpha: 1)
    // --primary-foreground: HSL(240, 5.9%, 10%)
    private static let primaryFG     = UIColor(red: 0.094, green: 0.094, blue: 0.110, alpha: 1)
    // --secondary: same as borderInput
    private static let secondary     = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
    // --destructive: HSL(0, 62.8%, 30.6%)
    private static let destructive   = UIColor(red: 0.498, green: 0.114, blue: 0.114, alpha: 1)

    // MARK: - UI

    /// Close button matching dialog-content.svelte: absolute right-4 top-4 rounded-sm, Cross2 size-4.
    private let closeButton: UIButton = {
        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        b.setImage(UIImage.hayaseIcon("x")?.withConfiguration(cfg), for: .normal)
        b.tintColor = UIColor(white: 0.64, alpha: 1) // muted-foreground
        b.layer.cornerRadius = 2 // rounded-sm
        return b
    }()

    private let scrollView = UIScrollView()
    /// Main container: horizontal on iPad, vertical on iPhone (web flex-col sm:flex-row).
    private let mainContainer = UIView()

    // Image section
    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .black // web: style:background={media.coverImage?.color ?? '#000'}
        return iv
    }()

    // Form section
    private let formContainer = UIView()

    // Title
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 20, weight: .semibold)
        l.textColor = .white
        return l
    }()

    // Status (Select.Trigger style: h-9 rounded-md border border-input bg-transparent px-3 text-sm)
    private let statusButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Watching", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = .clear
        b.layer.cornerRadius = 6
        b.layer.borderWidth = 1
        b.layer.borderColor = EntryEditorViewController.borderInput.cgColor
        b.contentHorizontalAlignment = .leading
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        b.titleLabel?.font = .nunito(ofSize: 14)
        return b
    }()

    // Score
    private let scoreButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("0", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = .clear
        b.layer.cornerRadius = 6
        b.layer.borderWidth = 1
        b.layer.borderColor = EntryEditorViewController.borderInput.cgColor
        b.contentHorizontalAlignment = .leading
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        b.titleLabel?.font = .nunito(ofSize: 14)
        return b
    }()

    // Progress (Input style: h-9 rounded-md border border-input bg-transparent px-3 text-sm)
    private let progressField: UITextField = {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textColor = .white
        tf.backgroundColor = .clear
        tf.layer.cornerRadius = 6
        tf.layer.borderWidth = 1
        tf.layer.borderColor = EntryEditorViewController.borderInput.cgColor
        tf.font = .nunito(ofSize: 14)
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        tf.leftViewMode = .always
        tf.attributedPlaceholder = NSAttributedString(string: "0", attributes: [.foregroundColor: EntryEditorViewController.mutedFG])
        return tf
    }()

    // Repeat
    private let repeatField: UITextField = {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textColor = .white
        tf.backgroundColor = .clear
        tf.layer.cornerRadius = 6
        tf.layer.borderWidth = 1
        tf.layer.borderColor = EntryEditorViewController.borderInput.cgColor
        tf.font = .nunito(ofSize: 14)
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        tf.leftViewMode = .always
        tf.attributedPlaceholder = NSAttributedString(string: "0", attributes: [.foregroundColor: EntryEditorViewController.mutedFG])
        return tf
    }()

    // Buttons (shadcn variants: default = bg-primary text-primary-foreground,
    //          secondary = bg-secondary text-secondary-foreground,
    //          destructive = bg-destructive text-destructive-foreground)
    // All: h-9 rounded-md text-sm font-medium
    private let saveButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Save Changes", for: .normal)
        b.setTitleColor(EntryEditorViewController.primaryFG, for: .normal)
        b.backgroundColor = EntryEditorViewController.primary
        b.layer.cornerRadius = 6
        b.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        return b
    }()

    private let cancelButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Cancel", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = EntryEditorViewController.secondary
        b.layer.cornerRadius = 6
        b.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        return b
    }()

    private let deleteButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Delete", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = EntryEditorViewController.destructive
        b.layer.cornerRadius = 6
        b.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        return b
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // bg-background
        view.backgroundColor = Self.bgBackground

        // Rounded corners only on iPad (web sm:rounded-lg — applied at ≥640px only)
        if isWide {
            view.layer.cornerRadius = 8
            view.clipsToBounds = true
        }

        // Border (border border-border)
        view.layer.borderWidth = 1
        view.layer.borderColor = Self.borderInput.cgColor

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

        loadImage()
    }

    // MARK: - Image loading

    private func loadImage() {
        // sm (iPad): show cover image; phone: show banner (fall back to cover)
        let urlStr: String?
        if isWide {
            urlStr = coverURL ?? bannerURL
        } else {
            urlStr = bannerURL ?? coverURL
        }
        guard let urlStr, let url = URL(string: urlStr) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.imageView.image = img }
        }.resume()
    }

    // MARK: - Setup

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(mainContainer)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.addSubview(imageView)

        formContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.addSubview(formContainer)

        // Title (pt-4 px-5)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = isWide ? 1 : 2
        formContainer.addSubview(titleLabel)

        // Fields (px-5 py-3 grid grid-cols-1 sm:grid-cols-2 gap-5)
        let statusLabel = makeFieldLabel("Status")
        let scoreLabel = makeFieldLabel("Score")
        let progressLabel = makeFieldLabel("Progress")
        let repeatLabel = makeFieldLabel("Rewatched Times")

        let fieldViews: [UIView] = [statusLabel, statusButton, scoreLabel, scoreButton,
                                    progressLabel, progressField, repeatLabel, repeatField]
        fieldViews.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            formContainer.addSubview($0)
        }

        // Buttons container
        // Phone: flex-col px-4 py-3 gap-3
        // iPad: flex-row-reverse px-6 py-3 gap-3
        let buttonsStack = UIStackView()
        buttonsStack.spacing = 12
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false

        if isWide {
            // sm:flex-row-reverse → horizontal, but items are in DOM order: Save, Cancel, Delete
            // flex-row-reverse means visual order: Delete (left), Cancel (middle), Save (right)
            buttonsStack.axis = .horizontal
            buttonsStack.distribution = .fillEqually
            // Add in reverse visual order (leftmost first): Delete, Cancel, Save
            buttonsStack.addArrangedSubview(deleteButton)
            buttonsStack.addArrangedSubview(cancelButton)
            buttonsStack.addArrangedSubview(saveButton)
        } else {
            // Phone: flex-col — DOM order: Save, Cancel, Delete (top to bottom)
            buttonsStack.axis = .vertical
            buttonsStack.addArrangedSubview(saveButton)
            buttonsStack.addArrangedSubview(cancelButton)
            buttonsStack.addArrangedSubview(deleteButton)
        }
        formContainer.addSubview(buttonsStack)

        // Actions
        statusButton.addTarget(self, action: #selector(statusTapped), for: .touchUpInside)
        scoreButton.addTarget(self, action: #selector(scoreTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        // Hide delete if no existing entry
        deleteButton.isHidden = currentEntry == nil

        // Close button (dialog-content.svelte: absolute right-4 top-4, Cross2 size-4)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
        view.bringSubviewToFront(closeButton)

        // Actions
        [saveButton, cancelButton, deleteButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        // Layout constraints
        let btnPad: CGFloat = isWide ? 24 : 16  // sm:px-6 vs px-4

        if isWide {
            setupWideLayout(statusLabel: statusLabel, scoreLabel: scoreLabel,
                            progressLabel: progressLabel, repeatLabel: repeatLabel,
                            buttonsStack: buttonsStack, btnPad: btnPad)
        } else {
            setupCompactLayout(statusLabel: statusLabel, scoreLabel: scoreLabel,
                               progressLabel: progressLabel, repeatLabel: repeatLabel,
                               buttonsStack: buttonsStack, btnPad: btnPad)
        }
    }

    // MARK: - Wide (iPad) layout: sm:flex-row (image left, form right)

    private func setupWideLayout(statusLabel: UILabel, scoreLabel: UILabel,
                                 progressLabel: UILabel, repeatLabel: UILabel,
                                 buttonsStack: UIStackView, btnPad: CGFloat) {
        // Image: sm:w-[260px] sm:h-[400px], rounded-l-lg
        imageView.layer.cornerRadius = 8
        imageView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            mainContainer.topAnchor.constraint(equalTo: scrollView.topAnchor),
            mainContainer.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            mainContainer.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            mainContainer.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            mainContainer.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Image: left side, 260pt wide, full height
            imageView.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            imageView.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 260),
            imageView.heightAnchor.constraint(equalToConstant: 400),

            // Form: right side
            formContainer.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            formContainer.leadingAnchor.constraint(equalTo: imageView.trailingAnchor),
            formContainer.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            formContainer.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),

            // Title: pt-4 px-5
            titleLabel.topAnchor.constraint(equalTo: formContainer.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -20),
        ])

        // 2-col grid (sm:grid-cols-2 gap-5)
        setupTwoColumnFields(statusLabel: statusLabel, scoreLabel: scoreLabel,
                             progressLabel: progressLabel, repeatLabel: repeatLabel)

        // Buttons at bottom
        NSLayoutConstraint.activate([
            buttonsStack.topAnchor.constraint(greaterThanOrEqualTo: repeatField.bottomAnchor, constant: 20),
            buttonsStack.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: btnPad),
            buttonsStack.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -btnPad),
            buttonsStack.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor, constant: -12),
            saveButton.heightAnchor.constraint(equalToConstant: 36),
            cancelButton.heightAnchor.constraint(equalToConstant: 36),
            deleteButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    // MARK: - Compact (iPhone) layout: flex-col (image top, form below)

    private func setupCompactLayout(statusLabel: UILabel, scoreLabel: UILabel,
                                    progressLabel: UILabel, repeatLabel: UILabel,
                                    buttonsStack: UIStackView, btnPad: CGFloat) {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            mainContainer.topAnchor.constraint(equalTo: scrollView.topAnchor),
            mainContainer.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            mainContainer.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            mainContainer.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            mainContainer.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Image: top, full width, 150pt
            imageView.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 150),

            // Form: below image
            formContainer.topAnchor.constraint(equalTo: imageView.bottomAnchor),
            formContainer.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            formContainer.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            formContainer.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),

            // Title: pt-4 px-5
            titleLabel.topAnchor.constraint(equalTo: formContainer.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -20),
        ])

        // 1-col grid (grid-cols-1 gap-5)
        setupOneColumnFields(statusLabel: statusLabel, scoreLabel: scoreLabel,
                             progressLabel: progressLabel, repeatLabel: repeatLabel)

        // Buttons
        NSLayoutConstraint.activate([
            buttonsStack.topAnchor.constraint(equalTo: repeatField.bottomAnchor, constant: 20),
            buttonsStack.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: btnPad),
            buttonsStack.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -btnPad),
            buttonsStack.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor, constant: -12),
            saveButton.heightAnchor.constraint(equalToConstant: 36),
            cancelButton.heightAnchor.constraint(equalToConstant: 36),
            deleteButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    // MARK: - Two-column field grid (iPad: sm:grid-cols-2 gap-5)

    private func setupTwoColumnFields(statusLabel: UILabel, scoreLabel: UILabel,
                                      progressLabel: UILabel, repeatLabel: UILabel) {
        // Each field: mt-1 (4pt) + label (font-bold text-sm mb-2 = 8pt gap) + control (h-9 = 36pt)
        // gap-5 (20pt) between columns and rows
        NSLayoutConstraint.activate([
            // Row 1: Status (left col) + Score (right col)
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),

            statusButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            statusButton.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),
            statusButton.heightAnchor.constraint(equalToConstant: 36),

            scoreLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scoreLabel.leadingAnchor.constraint(equalTo: formContainer.centerXAnchor, constant: 10),

            scoreButton.topAnchor.constraint(equalTo: scoreLabel.bottomAnchor, constant: 8),
            scoreButton.leadingAnchor.constraint(equalTo: formContainer.centerXAnchor, constant: 10),
            scoreButton.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -20),
            scoreButton.heightAnchor.constraint(equalToConstant: 36),

            // Status button fills left column
            statusButton.trailingAnchor.constraint(equalTo: formContainer.centerXAnchor, constant: -10),

            // Row 2: Progress (left col) + Repeat (right col)
            progressLabel.topAnchor.constraint(equalTo: statusButton.bottomAnchor, constant: 20),
            progressLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),

            progressField.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 8),
            progressField.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),
            progressField.trailingAnchor.constraint(equalTo: formContainer.centerXAnchor, constant: -10),
            progressField.heightAnchor.constraint(equalToConstant: 36),

            repeatLabel.topAnchor.constraint(equalTo: scoreButton.bottomAnchor, constant: 20),
            repeatLabel.leadingAnchor.constraint(equalTo: formContainer.centerXAnchor, constant: 10),

            repeatField.topAnchor.constraint(equalTo: repeatLabel.bottomAnchor, constant: 8),
            repeatField.leadingAnchor.constraint(equalTo: formContainer.centerXAnchor, constant: 10),
            repeatField.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -20),
            repeatField.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    // MARK: - One-column field grid (iPhone: grid-cols-1 gap-5)

    private func setupOneColumnFields(statusLabel: UILabel, scoreLabel: UILabel,
                                      progressLabel: UILabel, repeatLabel: UILabel) {
        NSLayoutConstraint.activate([
            // Status
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),

            statusButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            statusButton.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),
            statusButton.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -20),
            statusButton.heightAnchor.constraint(equalToConstant: 36),

            // Score
            scoreLabel.topAnchor.constraint(equalTo: statusButton.bottomAnchor, constant: 20),
            scoreLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),

            scoreButton.topAnchor.constraint(equalTo: scoreLabel.bottomAnchor, constant: 8),
            scoreButton.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),
            scoreButton.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -20),
            scoreButton.heightAnchor.constraint(equalToConstant: 36),

            // Progress
            progressLabel.topAnchor.constraint(equalTo: scoreButton.bottomAnchor, constant: 20),
            progressLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),

            progressField.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 8),
            progressField.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),
            progressField.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -20),
            progressField.heightAnchor.constraint(equalToConstant: 36),

            // Repeat
            repeatLabel.topAnchor.constraint(equalTo: progressField.bottomAnchor, constant: 20),
            repeatLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),

            repeatField.topAnchor.constraint(equalTo: repeatLabel.bottomAnchor, constant: 8),
            repeatField.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 20),
            repeatField.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -20),
            repeatField.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    private func makeFieldLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        // font-bold text-muted-foreground text-sm mb-2
        l.font = .nunito(ofSize: 14, weight: .bold)
        l.textColor = Self.mutedFG
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
        AniListTracking.shared.deleteEntry(listID: listID, mediaID: mediaID) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onDelete?()
                self?.dismiss(animated: true)
            }
        }
    }

    // MARK: - UIViewControllerTransitioningDelegate

    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        CenteredDialogPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

// MARK: - Centered Dialog Presentation Controller
/// Matches web shadcn Dialog: centered overlay, max-w-3xl (768px), max-h-[80%],
/// custom-bg striped dimming, sm:rounded-lg (8pt only on tablet).

final class CenteredDialogPresentationController: UIPresentationController {

    private let dimmingView: UIView = {
        let v = UIView()
        // Matches web custom-bg: repeating-linear-gradient(40deg, #1114 0, #5554 1px, #5554 5px, #1114 6px, #1114 10px)
        // Use dark semi-transparent base to approximate the striped overlay pattern
        v.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        return v
    }()

    /// Blur effect matching web's `backdrop-blur-sm` (blur 4px).
    private let blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .dark)
        let v = UIVisualEffectView(effect: blur)
        v.alpha = 0.3 // subtle to match backdrop-blur-sm
        return v
    }()

    /// Striped gradient layer matching web custom-bg pattern.
    private lazy var stripedLayer: CALayer = {
        let layer = CALayer()
        // Generate the striped pattern as a small tile and use it as a pattern fill
        let size = CGSize(width: 14, height: 14)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        if let ctx = UIGraphicsGetCurrentContext() {
            // Base: transparent (dimmingView provides the dark base)
            ctx.clear(CGRect(origin: .zero, size: size))
            // Draw diagonal stripes matching #5554 (rgba(85,85,85,0.267))
            ctx.setStrokeColor(UIColor(red: 85/255, green: 85/255, blue: 85/255, alpha: 0.267).cgColor)
            ctx.setLineWidth(4)
            // 40° diagonal stripes across the tile
            ctx.move(to: CGPoint(x: -2, y: size.height + 2))
            ctx.addLine(to: CGPoint(x: size.width + 2, y: -2))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: size.width - 16, y: size.height + 2))
            ctx.addLine(to: CGPoint(x: size.width + 2, y: size.height - 12))
            ctx.strokePath()
        }
        let patternImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        if let cgImage = patternImage?.cgImage {
            layer.backgroundColor = UIColor(patternImage: UIImage(cgImage: cgImage)).cgColor
        }
        return layer
    }()

    private var isCalculatingFrame = false

    // MARK: Frame

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView = containerView else { return .zero }
        // Guard against re-entrant calls from layout passes
        if isCalculatingFrame { return presentedView?.frame ?? .zero }
        isCalculatingFrame = true
        defer { isCalculatingFrame = false }

        let bounds = containerView.bounds
        // max-w-3xl = 768px
        let maxWidth: CGFloat = 768
        // On iPhone, leave 16pt margin each side
        let width = min(maxWidth, bounds.width - 32)
        // max-h-[80%]
        let maxHeight = bounds.height * 0.8

        // Size the presented view at the target width and do a layout pass
        // so the scroll view computes its content size from auto-layout constraints.
        // systemLayoutSizeFitting doesn't work with scroll views (they report 0 intrinsic height).
        let pv = presentedViewController.view!
        pv.frame = CGRect(x: 0, y: 0, width: width, height: maxHeight)
        pv.layoutIfNeeded()

        // Read the scroll view's content size for the actual content height
        var contentHeight: CGFloat = 0
        for subview in pv.subviews where subview is UIScrollView {
            contentHeight = (subview as! UIScrollView).contentSize.height
            break
        }

        let height = min(contentHeight > 0 ? contentHeight : maxHeight, maxHeight)
        let x = (bounds.width - width) / 2
        let y = (bounds.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: Transitions

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else { return }
        dimmingView.frame = containerView.bounds
        dimmingView.alpha = 0
        containerView.insertSubview(dimmingView, at: 0)

        // Add backdrop blur matching web's backdrop-blur-sm
        blurView.frame = containerView.bounds
        containerView.insertSubview(blurView, at: 0)
        blurView.alpha = 0

        // Add striped overlay pattern on top of dimming base
        stripedLayer.frame = dimmingView.bounds
        dimmingView.layer.addSublayer(stripedLayer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmingTapped))
        dimmingView.addGestureRecognizer(tap)

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.dimmingView.alpha = 1
            self.blurView.alpha = 0.3
        })
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.dimmingView.alpha = 0
            self.blurView.alpha = 0
        })
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed {
            dimmingView.removeFromSuperview()
            blurView.removeFromSuperview()
        }
    }

    // MARK: Layout

    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        let bounds = containerView?.bounds ?? .zero
        dimmingView.frame = bounds
        blurView.frame = bounds
        stripedLayer.frame = dimmingView.bounds
        presentedView?.frame = frameOfPresentedViewInContainerView
    }

    @objc private func dimmingTapped() {
        presentedViewController.dismiss(animated: true)
    }
}
