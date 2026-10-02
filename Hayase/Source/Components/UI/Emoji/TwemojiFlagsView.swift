import UIKit

/// The interface uses its Twemoji font for country flags in extension cards and peer rows.
/// Keep the Unicode country code as the model value and change only its presentation.
enum TwemojiFlagArtwork {
    private struct Manifest: Decodable {
        let size: Int
        let columns: Int
        let indices: [String: Int]
    }

    private static let atlas: (CGImage, Manifest)? = {
        guard let imageURL = Bundle.main.url(forResource: "flags", withExtension: "png", subdirectory: "Twemoji"),
              let manifestURL = Bundle.main.url(forResource: "flags", withExtension: "json", subdirectory: "Twemoji"),
              let image = UIImage(contentsOfFile: imageURL.path)?.cgImage,
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.size > 0, manifest.columns > 0 else { return nil }
        return (image, manifest)
    }()
    private static let cache = NSCache<NSString, UIImage>()

    static func emoji(for code: String) -> String? {
        let code = code.uppercased()
        if code == "ALL" { return "🌎" }
        let scalars = Array(code.unicodeScalars)
        guard scalars.count == 2, scalars.allSatisfy({ (65...90).contains($0.value) }) else { return nil }
        return scalars.compactMap { UnicodeScalar(127397 + $0.value) }
            .map { String($0) }.joined()
    }

    static func image(for code: String) -> UIImage? {
        let key = code.uppercased() as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let (source, manifest) = atlas, manifest.columns > 0,
              let index = manifest.indices[key as String] else { return nil }
        let side = manifest.size
        let rect = CGRect(x: (index % manifest.columns) * side,
                          y: (index / manifest.columns) * side,
                          width: side, height: side)
        guard let cropped = source.cropping(to: rect) else { return nil }
        let image = UIImage(cgImage: cropped)
        cache.setObject(image, forKey: key)
        return image
    }
}

final class TwemojiFlagView: UIView {
    static let side: CGFloat = 20

    private let artwork = UIImageView()
    private let fallback = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        artwork.contentMode = .scaleAspectFit
        fallback.font = .systemFont(ofSize: Self.side)
        fallback.textAlignment = .center
        addSubview(artwork)
        addSubview(fallback)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        artwork.contentMode = .scaleAspectFit
        fallback.font = .systemFont(ofSize: Self.side)
        fallback.textAlignment = .center
        addSubview(artwork)
        addSubview(fallback)
        isAccessibilityElement = true
    }

    func configure(code: String?) {
        guard let code, let emoji = TwemojiFlagArtwork.emoji(for: code) else {
            artwork.image = nil
            fallback.text = nil
            accessibilityLabel = nil
            return
        }
        artwork.image = TwemojiFlagArtwork.image(for: code)
        fallback.text = artwork.image == nil ? emoji : nil
        accessibilityLabel = emoji
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.side, height: Self.side)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rect = CGRect(x: (bounds.width - Self.side) / 2,
                          y: (bounds.height - Self.side) / 2,
                          width: Self.side, height: Self.side)
        artwork.frame = rect
        fallback.frame = rect
    }
}

final class TwemojiFlagsView: UIView {
    private var flags: [TwemojiFlagView] = []

    init(codes: [String]) {
        super.init(frame: .zero)
        for code in codes where TwemojiFlagArtwork.emoji(for: code) != nil {
            let flag = TwemojiFlagView()
            flag.configure(code: code)
            flag.isAccessibilityElement = false
            flags.append(flag)
            addSubview(flag)
        }
        isAccessibilityElement = true
        accessibilityLabel = codes.compactMap { TwemojiFlagArtwork.emoji(for: $0) }.joined()
    }

    required init?(coder: NSCoder) { return nil }

    override var intrinsicContentSize: CGSize {
        CGSize(width: CGFloat(flags.count) * TwemojiFlagView.side,
               height: TwemojiFlagView.side)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, flag) in flags.enumerated() {
            flag.frame = CGRect(x: CGFloat(index) * TwemojiFlagView.side, y: 0,
                                width: TwemojiFlagView.side, height: TwemojiFlagView.side)
        }
    }
}
