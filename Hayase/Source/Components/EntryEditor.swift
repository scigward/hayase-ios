// Mirrors: lib/components/EntryEditor.svelte. Presentation and controls are shared.

import UIKit

final class EntryEditorViewController: SettingsDialogViewController {
    var mediaID = 0
    var totalEpisodes: Int?
    var currentEntry: AnimeItem.MediaListEntry?
    var animeTitle = ""
    /// `cover(media)` and `banner(media)`, and `media.coverImage?.color`
    var coverURL: String?
    var bannerURL: String?
    var coverColor: String?
    var onSave: (() -> Void)?
    var onDelete: (() -> Void)?
    private let form = EntryEditorFormView()
    private let statuses = ["CURRENT", "PLANNING", "COMPLETED", "PAUSED", "DROPPED", "REPEATING"]
    private let labels = ["Watching", "Plan to Watch", "Completed", "Paused", "Dropped", "Re-Watching"]
    private var selectedStatus = "CURRENT"
    private var selectedScore = 0

    init() { super.init(title: "", maximumWidth: 768, contentInset: 0, heightFraction: 0.8) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        selectedStatus = currentEntry?.status ?? "CURRENT"
        selectedScore = max(0, min(10, currentEntry?.score ?? 0))
        form.setTitle(animeTitle)
        form.coverURL = coverURL
        form.bannerURL = bannerURL
        form.coverColor = coverColor
        form.progress.text = String(currentEntry?.progress ?? 0)
        form.repeats.text = String(currentEntry?.repeatCount ?? 0)
        updateChoices()
        form.status.addTarget(self, action: #selector(chooseStatus), for: .touchUpInside)
        form.score.addTarget(self, action: #selector(chooseScore), for: .touchUpInside)
        form.save.addTarget(self, action: #selector(saveEntry), for: .touchUpInside)
        form.cancel.addTarget(self, action: #selector(close), for: .touchUpInside)
        form.delete.addTarget(self, action: #selector(deleteEntry), for: .touchUpInside)
        content.addArrangedSubview(form)
    }

    private func updateChoices() {
        form.status.configure(text: labels[statuses.firstIndex(of: selectedStatus) ?? 0], placeholder: false)
        form.score.configure(text: String(selectedScore), placeholder: false)
    }

    @objc private func chooseStatus() {
        choose(title: "Status", anchor: form.status, values: statuses, labels: labels, selected: selectedStatus) { [weak self] in
            self?.selectedStatus = $0
            self?.updateChoices()
        }
    }

    @objc private func chooseScore() {
        let values = (0...10).map { String($0) }
        choose(title: "Score", anchor: form.score, values: values, labels: values, selected: String(selectedScore)) { [weak self] in
            self?.selectedScore = Int($0) ?? 0
            self?.updateChoices()
        }
    }

    private func choose(title: String, anchor: UIView, values: [String], labels: [String],
                        selected: String, changed: @escaping (String) -> Void) {
        let picker = CommandPopoverViewController(title: title,
            groups: [CommandGroup(options: zip(values, labels).map { CommandOption(value: $0.0, label: $0.1) })],
            selectedValues: [selected], allowsMultiple: false, sourceView: anchor, showsSearch: false)
        picker.onSelectionChanged = { if let value = $0.first { changed(value) } }
        present(picker, animated: false)
    }

    /// `Number(progress)` of a number input: a field with nothing in it is 0, not what it was before.
    private static func count(_ text: String?) -> Int {
        guard let value = Double((text ?? "").trimmingCharacters(in: .whitespaces)), value.isFinite else { return 0 }
        return max(0, Int(safe: value.rounded(.down)))
    }

    /// `Dialog.Close` wraps all three buttons: the dialog closes at once and the change goes out
    /// on its own, nothing waits for the answer and nothing reports one.
    @objc private func saveEntry() {
        let onSave = self.onSave
        AniListTracking.shared.entryResult(mediaID: mediaID, status: selectedStatus,
            progress: Self.count(form.progress.text),
            score: selectedScore, repeatCount: Self.count(form.repeats.text),
            lists: currentEntry?.customLists) { result in
                DispatchQueue.main.async {
                    if case .success = result { onSave?() }
                }
            }
        close()
    }

    @objc private func deleteEntry() {
        guard let listID = currentEntry?.listID else { close(); return }
        let onDelete = self.onDelete
        AniListTracking.shared.deleteEntryResult(listID: listID, mediaID: mediaID) { result in
            DispatchQueue.main.async {
                if case .success(let deleted) = result, deleted { onDelete?() }
            }
        }
        close()
    }
}

// MARK: - EntryEditorFormView

// Mirrors: lib/components/EntryEditor.svelte (rendering only).

/// `Dialog.Content` of the editor: `<div class='flex flex-col sm:flex-row w-full overflow-y-auto'>` with the
/// image, and the form `flex flex-col w-full h-full`. From `sm` (640) on the image is a 260 by 400 cover on
/// the left and the form fills the rest of its height; below it the image is a 150pt high banner above the
/// form, and the fields and the buttons are stacked.
final class EntryEditorFormView: UIView, SettingsResponsiveView, UITextFieldDelegate {
    /// `<Select.Trigger>` of the status and of the score.
    let status = SelectTriggerView()
    let score = SelectTriggerView()
    /// `<Input type='number' inputmode='numeric'>`
    let progress = EntryEditorFormView.numberField(label: "Progress")
    let repeats = EntryEditorFormView.numberField(label: "Rewatched Times")
    /// `Button`, `Button variant='secondary'` and `Button variant='destructive'`
    let save = EntryEditorFormView.button("Save Changes")
    let cancel = EntryEditorFormView.button("Cancel")
    let delete = EntryEditorFormView.button("Delete")
    /// `cover(media)` from `sm` on, `banner(media)` below it.
    var coverURL: String?
    var bannerURL: String?
    /// `style:background={media.coverImage?.color ?? '#000'}`, what shows until the image is there.
    var coverColor: String? {
        didSet { imageBox.backgroundColor = Self.color(coverColor) }
    }

    private let heading = SettingsTypography.label("", size: 20, lineHeight: 24, weight: .semibold)
    private let imageBox = UIView()
    private let image = UIImageView()
    private let form = UIView()
    private let grid = UIStackView()
    private let buttons = UIStackView()
    private var rows: [UIStackView] = []

    /// Where the pieces are below `sm` and from it on.
    private var compactConstraints: [NSLayoutConstraint] = []
    private var wideConstraints: [NSLayoutConstraint] = []
    private var wide: Bool?
    private var imageTask: URLSessionDataTask?
    private var imageURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageBox.backgroundColor = Self.color(nil)
        imageBox.clipsToBounds = true
        imageBox.translatesAutoresizingMaskIntoConstraints = false
        image.contentMode = .scaleAspectFill   // object-cover
        image.clipsToBounds = true
        image.translatesAutoresizingMaskIntoConstraints = false
        imageBox.addSubview(image)

        form.translatesAutoresizingMaskIntoConstraints = false
        heading.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        form.addSubview(heading)
        form.addSubview(grid)
        form.addSubview(buttons)
        addSubview(imageBox)
        addSubview(form)

        // `px-5 py-3 grid grid-cols-1 sm:grid-cols-2 gap-5`, each field `mt-1 flex flex-col` with a
        // `mb-2` label
        let fields: [(String, UIView)] = [("Status", status), ("Score", score), ("Progress", progress), ("Rewatched Times", repeats)]
        let groups = fields.map { name, control -> UIStackView in
            let label = SettingsTypography.label(name, size: 14, lineHeight: 20, weight: .bold,
                                                 color: UIColor.HayaseTheme.mutedForeground)
            let group = UIStackView(arrangedSubviews: [label, control])
            group.axis = .vertical
            group.spacing = 8
            group.isLayoutMarginsRelativeArrangement = true
            group.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)
            return group
        }
        for index in stride(from: 0, to: groups.count, by: 2) {
            let row = UIStackView(arrangedSubviews: [groups[index], groups[index + 1]])
            row.spacing = 20
            rows.append(row)
        }
        grid.axis = .vertical
        grid.spacing = 20
        rows.forEach { grid.addArrangedSubview($0) }

        // the status and the score are `Select`s with their own border, the inputs have theirs
        cancel.applySecondaryVariant()
        save.applyPrimaryVariant()
        delete.applyDestructiveVariant()
        buttons.spacing = 12   // gap-3
        buttons.isLayoutMarginsRelativeArrangement = true
        progress.delegate = self
        repeats.delegate = self

        // what is the same in both layouts
        NSLayoutConstraint.activate([
            imageBox.topAnchor.constraint(equalTo: topAnchor),
            imageBox.leadingAnchor.constraint(equalTo: leadingAnchor),
            form.trailingAnchor.constraint(equalTo: trailingAnchor),
            form.bottomAnchor.constraint(equalTo: bottomAnchor),

            image.topAnchor.constraint(equalTo: imageBox.topAnchor),
            image.leadingAnchor.constraint(equalTo: imageBox.leadingAnchor),
            image.trailingAnchor.constraint(equalTo: imageBox.trailingAnchor),
            image.bottomAnchor.constraint(equalTo: imageBox.bottomAnchor),

            // `pt-4 px-5` of the title
            heading.topAnchor.constraint(equalTo: form.topAnchor, constant: 16),
            heading.leadingAnchor.constraint(equalTo: form.leadingAnchor, constant: 20),
            heading.trailingAnchor.constraint(equalTo: form.trailingAnchor, constant: -20),

            // `px-5 py-3` of the fields
            grid.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: form.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: form.trailingAnchor, constant: -20),

            // `mt-auto` of the buttons: they are at the bottom of the form, below the fields at least
            buttons.leadingAnchor.constraint(equalTo: form.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: form.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: form.bottomAnchor),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: grid.bottomAnchor, constant: 12),
        ])
        // ...and right under them when the form is not taller than its content
        let snug = buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 12)
        snug.priority = .defaultLow
        snug.isActive = true

        // `h-[150px]` image above the form
        compactConstraints = [
            imageBox.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageBox.heightAnchor.constraint(equalToConstant: 150),
            form.topAnchor.constraint(equalTo: imageBox.bottomAnchor),
            form.leadingAnchor.constraint(equalTo: leadingAnchor),
        ]
        // `sm:w-[260px] sm:h-[400px]` image, and a form that is at least as tall as it
        wideConstraints = [
            imageBox.widthAnchor.constraint(equalToConstant: 260),
            imageBox.heightAnchor.constraint(equalToConstant: 400),
            form.topAnchor.constraint(equalTo: topAnchor),
            form.leadingAnchor.constraint(equalTo: imageBox.trailingAnchor),
            form.heightAnchor.constraint(greaterThanOrEqualToConstant: 400),
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { imageTask?.cancel() }

    /// `<h3 class='text-xl leading-6 font-semibold'>`
    func setTitle(_ text: String) {
        let font = UIFont.nunito(ofSize: 20, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        // CSS lets glyphs overflow a short line box, UILabel clips them: the font's own height is the least
        let lineHeight = max(24, ceil(font.lineHeight))
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byTruncatingTail
        heading.attributedText = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: UIColor.HayaseTheme.foreground, .paragraphStyle: paragraph,
        ])
    }

    func updateLayout(viewportWidth: CGFloat) {
        let nextWide = viewportWidth >= 640   // `sm`
        // a title of two lines is as wide as the dialog, which is the window below `sm`, less its 1pt border
        // and its `px-5`: the dialog is sized from the height of the label before it is laid out
        heading.preferredMaxLayoutWidth = nextWide ? 0 : max(0, viewportWidth - 42)
        guard nextWide != wide else { return }
        wide = nextWide

        NSLayoutConstraint.deactivate(nextWide ? compactConstraints : wideConstraints)
        NSLayoutConstraint.activate(nextWide ? wideConstraints : compactConstraints)

        heading.numberOfLines = nextWide ? 1 : 2   // sm:line-clamp-1 line-clamp-2
        rows.forEach {
            $0.axis = nextWide ? .horizontal : .vertical
            $0.distribution = nextWide ? .fillEqually : .fill
        }

        // `flex flex-col sm:flex-row-reverse` of the buttons, which come as Save, Cancel, Delete: stacked
        // they are in that order and as wide as the form, reversed they are on the right, Delete first
        buttons.arrangedSubviews.forEach { buttons.removeArrangedSubview($0); $0.removeFromSuperview() }
        buttons.axis = nextWide ? .horizontal : .vertical
        buttons.distribution = .fill
        buttons.layoutMargins = UIEdgeInsets(top: 12, left: nextWide ? 24 : 16, bottom: 12, right: nextWide ? 24 : 16)
        if nextWide {
            let spacer = UIView()
            spacer.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
            spacer.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
            buttons.addArrangedSubview(spacer)
        }
        (nextWide ? [delete, cancel, save] : [save, cancel, delete]).forEach { buttons.addArrangedSubview($0) }

        loadImage(nextWide ? coverURL : bannerURL)
    }

    // MARK: Fields

    /// `Input`: `h-9 w-full rounded-md border border-input bg-muted px-3 py-1 text-sm shadow-sm`; the
    /// number keyboard is `inputmode='numeric'`.
    private static func numberField(label: String) -> Input {
        let field = Input(placeholder: "")
        field.keyboardType = .numberPad
        field.returnKeyType = .done
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        // px-3 inside the 1pt border
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 13, height: 36))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 13, height: 36))
        field.rightViewMode = .always
        field.accessibilityLabel = label
        field.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return field
    }

    /// `Button` of the editor: `h-9 px-4 py-2 rounded-md text-sm font-medium`, as wide as its text unless
    /// the buttons are stacked.
    private static func button(_ title: String) -> SelectButton {
        let button = SelectButton()
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    /// A number input takes the digits; what is pasted into it is not a number if it is anything else.
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        string.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: Image

    /// `media.coverImage?.color ?? '#000'`
    private static func color(_ hex: String?) -> UIColor {
        guard var hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), hex.hasPrefix("#") else { return .black }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return .black }
        return UIColor(red: CGFloat((value >> 16) & 0xff) / 255,
                       green: CGFloat((value >> 8) & 0xff) / 255,
                       blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    private func loadImage(_ source: String?) {
        imageTask?.cancel()
        imageURL = source
        image.image = nil
        guard let source, let url = URL(string: source) else { return }
        if let cached = SharedImageCache.shared.object(forKey: source as NSString) { image.image = cached; return }
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let artwork = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(artwork, forKey: source as NSString)
            DispatchQueue.main.async {
                guard self?.imageURL == source else { return }
                self?.image.image = artwork
            }
        }
        imageTask?.resume()
    }
}
