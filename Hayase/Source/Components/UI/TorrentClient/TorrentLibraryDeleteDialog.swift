// Mirrors: interface/ui/torrentclient/library/table.svelte's delete confirmation.
import UIKit

final class TorrentLibraryDeleteDialog: SettingsDialogViewController {
    private let names: [String]
    private let onDelete: () -> Void
    private let header = UIStackView()
    private let footer = UIStackView()
    private let footerContainer = UIView()
    private let titleLabel = TorrentClientLabel()
    private let descriptionLabel = UILabel()
    private let list = UIScrollView()
    private let rows = UIStackView()
    private var listHeight: NSLayoutConstraint?
    private var footerLeading: NSLayoutConstraint?
    private var confirmed = false

    init(names: [String], onDelete: @escaping () -> Void) {
        self.names = names
        self.onDelete = onDelete
        super.init(title: "", maximumWidth: 1024)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.font = .nunito(ofSize: 18, weight: .semibold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.lineHeight = 18
        titleLabel.letterSpacing = -0.45
        titleLabel.text = "Are you absolutely sure?"
        descriptionLabel.font = .nunito(ofSize: 14)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0
        configureDescription(alignment: .left)
        header.axis = .vertical
        header.spacing = 6
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(descriptionLabel)
        header.addArrangedSubview(list)
        list.translatesAutoresizingMaskIntoConstraints = false
        list.showsHorizontalScrollIndicator = false
        rows.axis = .vertical
        rows.spacing = 8
        rows.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(rows)
        for name in names {
            let row = UIView()
            let label = TorrentClientLabel()
            label.lineHeight = 16
            label.font = .nunito(ofSize: 12)
            label.textColor = UIColor.HayaseTheme.mutedForeground
            label.text = name
            label.lineBreakMode = .byTruncatingTail
            let bullet = TorrentClientLabel()
            bullet.lineHeight = 16
            bullet.font = .nunito(ofSize: 12)
            bullet.textColor = UIColor.HayaseTheme.mutedForeground
            bullet.text = "•"
            [label, bullet].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; row.addSubview($0) }
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 16),
                label.topAnchor.constraint(equalTo: row.topAnchor),
                label.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                bullet.topAnchor.constraint(equalTo: row.topAnchor),
                bullet.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                bullet.trailingAnchor.constraint(equalTo: row.leadingAnchor, constant: -5),
            ])
            rows.addArrangedSubview(row)
        }
        listHeight = list.heightAnchor.constraint(equalToConstant: 32)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: list.contentLayoutGuide.topAnchor, constant: 16),
            rows.leadingAnchor.constraint(equalTo: list.contentLayoutGuide.leadingAnchor, constant: 20),
            rows.trailingAnchor.constraint(equalTo: list.contentLayoutGuide.trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: list.contentLayoutGuide.bottomAnchor, constant: -16),
            rows.widthAnchor.constraint(equalTo: list.frameLayoutGuide.widthAnchor, constant: -20),
            listHeight!,
        ])
        let delete = SelectButton()
        delete.restingBackground = UIColor.HayaseTheme.destructive
        delete.selectedBackground = UIColor.HayaseTheme.destructive.withAlphaComponent(0.9)
        delete.restingTint = UIColor.HayaseTheme.destructiveForeground
        delete.selectedTint = UIColor.HayaseTheme.destructiveForeground
        configure(delete, title: "Delete")
        delete.applyShadowSm()
        delete.addTarget(self, action: #selector(confirm), for: .touchUpInside)
        let cancel = SelectButton()
        cancel.applySecondaryVariant()
        configure(cancel, title: "Cancel")
        cancel.addTarget(self, action: #selector(close), for: .touchUpInside)
        footer.addArrangedSubview(delete)
        footer.addArrangedSubview(cancel)
        content.addArrangedSubview(header)
        footer.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.addSubview(footer)
        footerLeading = footer.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor)
        NSLayoutConstraint.activate([
            footer.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            footer.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor),
            footer.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            footer.leadingAnchor.constraint(greaterThanOrEqualTo: footerContainer.leadingAnchor),
        ])
        content.addArrangedSubview(footerContainer)
    }

    private func configure(_ button: SelectButton, title: String) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureDescription(alignment: NSTextAlignment) {
        let font = UIFont.nunito(ofSize: 14)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 20
        paragraph.maximumLineHeight = 20
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        descriptionLabel.textAlignment = alignment
        descriptionLabel.attributedText = NSAttributedString(
            string: "You are about to permanently delete \(names.count) torrent(s) from your library. This action cannot be undone.",
            attributes: [
                .font: font, .foregroundColor: UIColor.HayaseTheme.mutedForeground,
                .paragraphStyle: paragraph, .baselineOffset: (20 - font.lineHeight) / 2,
            ])
    }

    override func viewDidLayoutSubviews() {
        let viewport = view.window?.rootViewController?.view.bounds.width ?? view.bounds.width
        let compact = viewport < 640
        // Dialog.Header: text-center sm:text-left. Dialog.Footer:
        // flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2.
        titleLabel.textAlignment = compact ? .center : .left
        let descriptionAlignment: NSTextAlignment = compact ? .center : .left
        if descriptionLabel.textAlignment != descriptionAlignment {
            configureDescription(alignment: descriptionAlignment)
        }
        footer.axis = compact ? .vertical : .horizontal
        footer.alignment = compact ? .fill : .trailing
        footerLeading?.isActive = compact
        footer.spacing = compact ? 0 : 8
        if footer.arrangedSubviews.count == 2 {
            let desiredFirst = compact ? "Cancel" : "Delete"
            if (footer.arrangedSubviews.first as? UIButton)?.currentTitle != desiredFirst {
                let first = footer.arrangedSubviews[0]
                footer.removeArrangedSubview(first)
                first.removeFromSuperview()
                footer.addArrangedSubview(first)
            }
        }
        // A horizontal footer should keep its two intrinsic buttons at the
        // right, not distribute their titles across the whole dialog.
        footer.distribution = compact ? .fillEqually : .fill
        if !compact {
            footer.setContentHuggingPriority(.required, for: .horizontal)
        }
        let listContentHeight = 32 + CGFloat(names.count) * 16 + CGFloat(max(0, names.count - 1)) * 8
        listHeight?.constant = min(listContentHeight, view.bounds.height * 0.5)
        let titleWidth = titleLabel.intrinsicContentSize.width
        let descriptionWidth = ((descriptionLabel.text ?? "") as NSString).size(withAttributes: [.font: UIFont.nunito(ofSize: 14)]).width
        let nameWidth = names.map { ($0 as NSString).size(withAttributes: [.font: UIFont.nunito(ofSize: 12)]).width + 20 }.max() ?? 0
        preferredPanelWidth = max(max(titleWidth, descriptionWidth), nameWidth) + 48
        super.viewDidLayoutSubviews()
    }

    @objc private func confirm() {
        guard !confirmed else { return }
        confirmed = true
        onDelete()
        close()
    }
}
