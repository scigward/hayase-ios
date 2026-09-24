// Mirrors: lib/components/EntryEditor.svelte (rendering only).
import UIKit

final class EntryEditorFormView: UIView, SettingsResponsiveView {
    let status = ComboBox()
    let score = ComboBox()
    let progress = EntryEditorFormView.numberField()
    let repeats = EntryEditorFormView.numberField()
    let save = SettingsTypography.button("Save Changes")
    let cancel = SettingsTypography.button("Cancel")
    let delete = SettingsTypography.button("Delete", destructive: true)
    let heading = SettingsTypography.label("", size: 20, lineHeight: 24, weight: .semibold)
    var coverURL: String?
    var bannerURL: String?
    private let image = UIImageView()
    private let root = UIStackView()
    private let form = UIStackView()
    private let buttons = UIStackView()
    private var rows: [UIStackView] = []
    private var imageWidth: NSLayoutConstraint!
    private var imageHeight: NSLayoutConstraint!
    private var formHeight: NSLayoutConstraint!
    private var wide: Bool?
    private var imageTask: URLSessionDataTask?
    private var imageURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.backgroundColor = UIColor.HayaseTheme.background
        image.translatesAutoresizingMaskIntoConstraints = false
        imageWidth = image.widthAnchor.constraint(equalToConstant: 260)
        imageHeight = image.heightAnchor.constraint(equalToConstant: 150)
        imageHeight.isActive = true
        form.axis = .vertical
        formHeight = form.heightAnchor.constraint(equalToConstant: 400)
        let title = padded([heading], insets: UIEdgeInsets(top: 16, left: 20, bottom: 0, right: 20))
        form.addArrangedSubview(title)
        let fields: [(String, UIView)] = [("Status", status), ("Score", score), ("Progress", progress), ("Rewatched Times", repeats)]
        let groups = fields.map { name, control -> UIView in
            let label = SettingsTypography.label(name, size: 14, lineHeight: 20, weight: .bold,
                                                 color: UIColor.HayaseTheme.mutedForeground)
            let group = padded([label, control], insets: UIEdgeInsets(top: 4, left: 0, bottom: 0, right: 0))
            group.spacing = 8
            return group
        }
        for index in stride(from: 0, to: groups.count, by: 2) {
            let row = UIStackView(arrangedSubviews: [groups[index], groups[index + 1]])
            row.spacing = 20
            rows.append(row)
        }
        let grid = padded(rows, insets: UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20))
        grid.spacing = 20
        form.addArrangedSubview(grid)
        form.addArrangedSubview(UIView())
        buttons.spacing = 12
        buttons.isLayoutMarginsRelativeArrangement = true
        form.addArrangedSubview(buttons)
        cancel.backgroundColor = UIColor.HayaseTheme.secondary
        cancel.setTitleColor(UIColor.HayaseTheme.secondaryForeground, for: .normal)
        for control in [status, score] {
            control.restingBackgroundColor = UIColor.HayaseTheme.muted
            control.layer.borderWidth = 1
            control.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        }
        root.addArrangedSubview(image)
        root.addArrangedSubview(form)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor), root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor), root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { imageTask?.cancel() }

    func updateLayout(viewportWidth: CGFloat) {
        let nextWide = viewportWidth >= 640
        guard nextWide != wide else { return }
        wide = nextWide
        root.axis = nextWide ? .horizontal : .vertical
        imageWidth.isActive = nextWide
        imageHeight.constant = nextWide ? 400 : 150
        formHeight.isActive = nextWide
        heading.numberOfLines = nextWide ? 1 : 2
        rows.forEach { $0.axis = nextWide ? .horizontal : .vertical; $0.distribution = nextWide ? .fillEqually : .fill }
        buttons.arrangedSubviews.forEach { buttons.removeArrangedSubview($0); $0.removeFromSuperview() }
        buttons.axis = nextWide ? .horizontal : .vertical
        buttons.layoutMargins = UIEdgeInsets(top: 12, left: nextWide ? 24 : 16, bottom: 12, right: nextWide ? 24 : 16)
        if nextWide { buttons.addArrangedSubview(UIView()) }
        (nextWide ? [delete, cancel, save] : [save, cancel, delete]).forEach { buttons.addArrangedSubview($0) }
        loadImage(nextWide ? coverURL : (bannerURL ?? coverURL))
    }

    private func padded(_ views: [UIView], insets: UIEdgeInsets) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = insets
        return stack
    }

    private static func numberField() -> UITextField {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.font = .nunito(ofSize: 14)
        field.backgroundColor = UIColor.HayaseTheme.muted
        field.textColor = UIColor.HayaseTheme.foreground
        field.layer.cornerRadius = 6
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return field
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
