// seekbar.svelte's pointer preview: text fallback, then a 160px thumbnail.
import UIKit

final class PlayerSeekPreviewView: UIView {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let timeLabel = UILabel()
    private let titleBackground = UIView()
    private let timeBackground = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor.HayaseTheme.foreground
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor.HayaseTheme.primary.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 7.5
        layer.shadowOffset = CGSize(width: 0, height: 10)
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        for (label, panel) in [(titleLabel, titleBackground), (timeLabel, timeBackground)] {
            label.font = .nunito(ofSize: 14, weight: .regular)
            label.textColor = UIColor.HayaseTheme.background
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
            panel.layer.cornerRadius = 8
            panel.addSubview(label)
            addSubview(panel)
        }
        titleBackground.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        timeBackground.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(title: String, time: String, image: UIImage?) {
        titleLabel.text = title
        timeLabel.text = time
        imageView.image = image
        titleBackground.isHidden = title.isEmpty
        imageView.isHidden = image == nil
        titleBackground.backgroundColor = image == nil ? .clear : UIColor.HayaseTheme.primary
        timeBackground.backgroundColor = titleBackground.backgroundColor
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
    override var intrinsicContentSize: CGSize {
        if let image = imageView.image, image.size.width > 0 {
            return CGSize(width: 162, height: max(40, 160 * image.size.height / image.size.width) + 2)
        }
        return CGSize(width: max(min(96, titleLabel.intrinsicContentSize.width), timeLabel.intrinsicContentSize.width) + 26,
                      height: titleBackground.isHidden ? 32 : 50)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds.insetBy(dx: 1, dy: 1)
        let hasImage = imageView.image != nil
        let titleWidth = min(96, titleLabel.intrinsicContentSize.width)
        let timeWidth = timeLabel.intrinsicContentSize.width
        titleBackground.frame = CGRect(x: (bounds.width - titleWidth - (hasImage ? 16 : 0)) / 2,
                                       y: hasImage ? 1 : 9, width: titleWidth + (hasImage ? 16 : 0), height: hasImage ? 22 : 14)
        timeBackground.frame = CGRect(x: (bounds.width - timeWidth - (hasImage ? 16 : 0)) / 2,
                                      y: hasImage ? bounds.height - 23 : bounds.height - 23,
                                      width: timeWidth + (hasImage ? 16 : 0), height: hasImage ? 22 : 14)
        titleLabel.frame = titleBackground.bounds.insetBy(dx: hasImage ? 8 : 0, dy: hasImage ? 4 : 0)
        timeLabel.frame = timeBackground.bounds.insetBy(dx: hasImage ? 8 : 0, dy: hasImage ? 4 : 0)
    }
}
