// Mirrors: lib/components/EntryEditor.svelte. Presentation and controls are shared.
import UIKit

final class EntryEditorViewController: SettingsDialogViewController {
    var mediaID = 0
    var totalEpisodes: Int?
    var currentEntry: AnimeItem.MediaListEntry?
    var animeTitle = ""
    var coverURL: String?
    var bannerURL: String?
    var onSave: (() -> Void)?
    var onDelete: (() -> Void)?
    private let form = EntryEditorFormView()
    private let statuses = ["CURRENT", "PLANNING", "COMPLETED", "PAUSED", "DROPPED", "REPEATING"]
    private let labels = ["Watching", "Plan to Watch", "Completed", "Paused", "Dropped", "Re-Watching"]
    private var selectedStatus = "CURRENT"
    private var selectedScore = 0
    private var saving = false

    init() { super.init(title: "", maximumWidth: 768, contentInset: 0, heightFraction: 0.8) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        selectedStatus = currentEntry?.status ?? "CURRENT"
        selectedScore = max(0, min(10, currentEntry?.score ?? 0))
        form.heading.font = .nunito(ofSize: 20, weight: .semibold)
        form.heading.text = animeTitle
        form.coverURL = coverURL
        form.bannerURL = bannerURL
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

    private func choose(title: String, anchor: ComboBox, values: [String], labels: [String],
                        selected: String, changed: @escaping (String) -> Void) {
        let picker = CommandPopoverViewController(title: title,
            groups: [CommandGroup(options: zip(values, labels).map { CommandOption(value: $0.0, label: $0.1) })],
            selectedValues: [selected], allowsMultiple: false, sourceView: anchor, showsSearch: false)
        picker.onSelectionChanged = { if let value = $0.first { changed(value) } }
        present(picker, animated: false)
    }

    private func setSaving(_ value: Bool) {
        saving = value
        [form.save, form.delete].forEach { $0.isEnabled = !value; $0.alpha = value ? 0.5 : 1 }
    }

    @objc private func saveEntry() {
        guard !saving else { return }
        setSaving(true)
        AniListTracking.shared.entryResult(mediaID: mediaID, status: selectedStatus,
            progress: max(0, Int(form.progress.text ?? "") ?? currentEntry?.progress ?? 0),
            score: selectedScore, repeatCount: max(0, Int(form.repeats.text ?? "") ?? currentEntry?.repeatCount ?? 0),
            lists: currentEntry?.customLists) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setSaving(false)
                    switch result {
                    case .success: self.onSave?(); self.close()
                    case .failure(let error): SettingsToast.show(error.description, in: self.view)
                    }
                }
            }
    }

    @objc private func deleteEntry() {
        guard !saving else { return }
        guard let listID = currentEntry?.listID else { close(); return }
        setSaving(true)
        AniListTracking.shared.deleteEntryResult(listID: listID, mediaID: mediaID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setSaving(false)
                switch result {
                case .success(let deleted):
                    if deleted { self.onDelete?(); self.close() }
                    else { SettingsToast.show("The entry could not be deleted.", in: self.view) }
                case .failure(let error): SettingsToast.show(error.description, in: self.view)
                }
            }
        }
    }
}
