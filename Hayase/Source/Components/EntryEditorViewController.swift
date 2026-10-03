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
