//
//  CoverDialog.swift
//  Hayase
//
//  Mirrors: interface routes/app/anime/[id]/+layout.svelte's cover `Dialog.Content`
//  (`flex justify-center p-0 overflow-clip`) around
//  `<Load src={cover(media)} color={media.coverImage?.color} class='size-full object-cover'>`.
//

import UIKit

/// The cover at the size of the dialog: it is `w-full max-w-lg` (the width of the window up to 512), has a 1pt
/// border and, from `sm` on, rounded corners, and is as tall as the picture is for that width. The dialog, its
/// overlay, its close button and how they come and go are `SettingsDialogViewController`'s, which is
/// `dialog-content.svelte` and `dialog-overlay.svelte`.
///
/// Unlike the interface, which has no `max-h` and so lets a cover that is taller than the window run off its
/// edges, the dialog is no taller than the window and the cover scrolls in it.
final class CoverDialogViewController: SettingsDialogViewController {
    /// `Load`'s `div`: `style:background={color ?? '#1890ff'}`
    private let host = UIView()
    /// `Load`'s `img`: it fades in on the color of the `div`
    private let imageView = UIImageView()
    private var heightConstraint: NSLayoutConstraint?
    private var image: UIImage?
    private let urlString: String?
    private let coverColor: String?
    private let imageTitle: String
    private var task: URLSessionDataTask?
    private var requestedAt = CACurrentMediaTime()

    init(urlString: String?, image: UIImage?, color: String?, title: String) {
        self.urlString = urlString
        self.image = image
        self.coverColor = color
        self.imageTitle = title
        // no padding, and no limit of the height but the window
        super.init(title: "", maximumWidth: 512, contentInset: 0, heightFraction: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()

        host.backgroundColor = AnimeInfoHeaderView.coverBackground(coverColor)
        host.clipsToBounds = true   // overflow-clip
        host.translatesAutoresizingMaskIntoConstraints = false

        imageView.contentMode = .scaleAspectFill   // object-cover
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = imageTitle   // alt={title(media)}
        imageView.accessibilityTraits = .image
        host.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: host.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        fitHeight(to: image)
        content.addArrangedSubview(host)
    }

    /// `size-full` of an `img` without a height: the picture's own proportions at the width of the dialog, and
    /// no height at all until there is a picture.
    private func fitHeight(to image: UIImage?) {
        heightConstraint?.isActive = false
        if let image, image.size.width > 0, image.size.height > 0 {
            heightConstraint = host.heightAnchor.constraint(equalTo: host.widthAnchor,
                                                            multiplier: image.size.height / image.size.width)
        } else {
            heightConstraint = host.heightAnchor.constraint(equalToConstant: 0)
        }
        heightConstraint?.isActive = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // the `img` is made with the dialog, and fades in with it
        if let image {
            LoadIn.show(image, in: imageView, blurred: true)
        } else {
            load()
        }
    }

    private func load() {
        guard let urlString, let url = URL(string: urlString) else { return }

        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            show(cached, blurred: true)
            return
        }

        requestedAt = CACurrentMediaTime()
        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async {
                guard let self else { return }
                self.show(image, blurred: CACurrentMediaTime() - self.requestedAt < LoadIn.blurWindow)
            }
        }
        task?.resume()
    }

    private func show(_ picture: UIImage, blurred: Bool) {
        image = picture
        fitHeight(to: picture)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        LoadIn.show(picture, in: imageView, blurred: blurred)
    }
}
