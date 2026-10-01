//
//  TrailerTooltip.swift
//  Hayase
//
//  Mirrors: interface routes/app/anime/[id]/+layout.svelte's "Also available on YouTube!" tooltip,
//  with lib/modules/anilist/trailer.ts (`minutes`) and lib/components/icons/SquiggleArrow.svelte.
//

import UIKit
import WebKit

// MARK: - trailer.ts

/// `minutes(videoId)`: how long a YouTube video is, read from a hidden embed of it, which tells
/// the page its duration once it is listening. An answer comes back once at most, nothing at all
/// when the embed says nothing within 15s, and later calls for the same video use the first answer.
final class TrailerMinutes: NSObject, WKScriptMessageHandler {
    private static var cache: [String: Int] = [:]

    private let videoID: String
    private var completion: ((Int) -> Void)?
    private var webView: WKWebView?
    private var timeout: DispatchWorkItem?

    /// nil when the answer was already known.
    static func load(videoID: String, completion: @escaping (Int) -> Void) -> TrailerMinutes? {
        if let cached = cache[videoID], cached != 0 {
            completion(cached)
            return nil
        }
        let loader = TrailerMinutes(videoID: videoID, completion: completion)
        loader.start()
        return loader
    }

    private init(videoID: String, completion: @escaping (Int) -> Void) {
        self.videoID = videoID
        self.completion = completion
    }

    private func start() {
        guard let window = (UIApplication.shared.delegate as? AppDelegate)?.window,
              videoID.range(of: "^[-_0-9A-Za-z]+$", options: .regularExpression) != nil else { return }
        let controller = WKUserContentController()
        controller.add(WeakScriptMessageHandler(delegate: self), name: "trailer")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        view.alpha = 0
        view.isUserInteractionEnabled = false
        window.addSubview(view)
        webView = view
        view.loadHTMLString(html(), baseURL: URL(string: "https://www.youtube-nocookie.com"))

        let work = DispatchWorkItem { [weak self] in self?.cancel() }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    func cancel() {
        timeout?.cancel()
        timeout = nil
        completion = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "trailer")
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    deinit {
        cancel()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "trailer", let duration = message.body as? Double, let completion else { return }
        // cache.set(videoId, Math.ceil(duration / 60)); set(Math.round(duration / 60))
        Self.cache[videoID] = Int((duration / 60).rounded(.up))
        let minutes = Int((duration / 60).rounded())
        cancel()
        completion(minutes)
    }

    private func html() -> String {
        """
        <!doctype html>
        <html><body>
        <iframe id="frame" style="position:absolute;width:0;height:0;border:0"
          src="https://www.youtube-nocookie.com/embed/\(videoID)?enablejsapi=1&autoplay=0&controls=0&disablekb=1"></iframe>
        <script>
          const frame = document.getElementById('frame');
          let loadtimeout;
          function listen() {
            frame.contentWindow && frame.contentWindow.postMessage('{"event":"listening","id":1,"channel":"widget"}', '*');
          }
          frame.addEventListener('load', function () {
            loadtimeout = setInterval(listen, 100);
            listen();
          });
          window.addEventListener('message', function (e) {
            if (e.origin !== 'https://www.youtube-nocookie.com') return;
            clearInterval(loadtimeout);
            try {
              const json = JSON.parse(e.data);
              if (json.event === 'initialDelivery' && json.info && typeof json.info.duration === 'number'
                  && json.info.videoData && json.info.videoData.video_id === '\(videoID)') {
                window.webkit.messageHandlers.trailer.postMessage(json.info.duration);
              }
            } catch (error) {}
          });
        </script>
        </body></html>
        """
    }
}

// MARK: - SquiggleArrow.svelte

/// `<SquiggleArrow class='h-14 w-20'>`: a 246×287 drawing, fitted into 80×56 and centred.
private final class SquiggleArrowView: UIView {
    private static let data = "M156.25 265.656C157.94 265.444 158.573 265.656 159.207 265.444C197.847 242.174 224.029 209.172 233.953 164.747C236.487 153.535 236.065 141.899 233.109 130.476C226.985 105.936 206.504 89.0121 181.377 87.5312C168.286 86.685 155.617 88.1659 144.215 95.3586C143.37 101.493 142.737 107.628 141.47 113.34C139.359 122.648 134.502 130.264 125.845 134.918C119.51 138.515 113.176 138.515 109.798 135.13C105.363 130.687 105.364 124.764 108.108 119.898C111.909 113.129 116.554 106.782 121.411 100.859C124.578 97.051 128.801 93.8777 132.602 90.7045C129.012 66.7994 106.419 56.645 79.3921 66.5878C78.5475 69.9726 77.7029 73.569 76.6472 76.9538C72.4242 89.4352 64.6117 98.9549 51.9427 103.397C47.0863 105.09 41.8075 105.724 37.5845 101.282C34.4173 97.8972 34.4173 91.9738 37.7957 86.0504C43.2856 76.7422 51.5204 70.1842 60.3887 64.4723C63.5559 62.5684 66.7232 60.6644 69.8904 58.972C65.6674 21.9508 32.517 -4.28131 0 10.5272C0.211149 7.77702 -1.29001e-05 5.44997 0.844584 4.18067C1.90033 2.69982 4.22297 1.85363 6.12332 1.43053C24.071 -1.95427 40.7518 0.161227 54.4765 13.2773C64.8228 23.0086 71.7908 34.8554 76.4361 48.3946C77.0695 50.2985 77.703 52.2024 78.5476 54.1064C78.5476 54.3179 78.9698 54.5295 79.8144 55.1641C81.7147 54.9526 84.0374 54.9526 86.36 54.5295C114.654 50.087 129.434 57.7027 142.526 84.1464C145.06 83.3002 148.016 82.454 150.761 81.3963C167.019 75.896 183.278 75.4729 199.747 80.9732C226.563 89.8583 243.877 112.917 245.778 142.111C246.833 157.977 244.089 173.209 238.388 188.017C224.452 223.769 201.648 251.905 167.441 270.31C165.752 271.368 163.852 272.214 162.163 273.272C161.951 273.483 161.74 273.906 161.107 275.176C168.286 276.868 175.043 276.233 181.8 275.81C188.345 275.599 195.102 274.964 202.281 274.541C201.648 280.041 198.691 282.157 195.102 283.426C190.879 284.695 186.656 286.388 182.433 286.599C171.031 287.023 159.418 287.234 147.804 286.599C138.725 285.965 136.191 281.099 140.203 273.695C148.86 258.04 157.728 242.386 166.597 226.731C168.075 224.192 169.975 222.077 172.298 219.115C176.31 223.769 174.62 227.154 173.142 230.327C167.23 241.751 161.951 253.175 156.25 265.656ZM43.919 94.9355C58.4883 93.0315 67.5677 83.7233 68.2012 70.6073C58.4883 76.9538 49.1978 82.6656 43.919 94.9355ZM115.288 127.726C127.745 124.764 133.658 116.302 132.391 103.397C124.367 110.167 117.399 116.514 115.288 127.726Z"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ rect: CGRect) {
        let scale = min(bounds.width / 246, bounds.height / 287)
        let path = UIBezierPath(cgPath: SVGPath.path(Self.data))
        path.apply(CGAffineTransform(translationX: (bounds.width - 246 * scale) / 2,
                                     y: (bounds.height - 287 * scale) / 2).scaledBy(x: scale, y: scale))
        UIColor.white.setFill()
        path.fill()
    }
}

// MARK: - backdrop-fade-[1.5px]

/// `backdrop-filter: blur(1.5px)` behind a box whose edges fade out: the mask is the product of
/// two gradients, transparent to opaque over the first 8% and back over the last 8%, on each axis.
private final class FadingBackdropBlurView: UIView {
    private let blurView = UIVisualEffectView(effect: nil)
    private var blurAnimator: UIViewPropertyAnimator?
    private var configuredSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 6   // rounded-md, overflow-hidden
        layer.masksToBounds = true
        addSubview(blurView)
        let mask = CALayer()
        mask.contents = Self.fadeMask
        mask.contentsGravity = .resize
        layer.mask = mask
    }

    required init?(coder: NSCoder) {
        nil
    }

    private static let fadeMask: CGImage? = {
        let size = 64
        func ramp(_ t: Double) -> Double {
            t < 0.08 ? t / 0.08 : (t > 0.92 ? (1 - t) / 0.08 : 1)
        }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let alpha = ramp((Double(x) + 0.5) / Double(size)) * ramp((Double(y) + 0.5) / Double(size))
                bytes[(y * size + x) * 4 + 3] = UInt8((alpha * 255).rounded())
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }()

    deinit { blurAnimator?.stopAnimation(true) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        blurAnimator?.stopAnimation(true)
        blurAnimator = nil
        blurView.effect = nil
        configuredSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        layer.mask?.frame = bounds
        guard window != nil, bounds.width > 0, bounds.height > 0, configuredSize != bounds.size,
              !UIAccessibility.isReduceTransparencyEnabled else { return }
        configuredSize = bounds.size
        blurAnimator?.stopAnimation(true)
        blurView.effect = nil
        // UIKit has no blur radius: a system blur held at a small fraction is the light blur.
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.blurView.effect = UIBlurEffect(style: .regular)
        }
        animator.pausesOnCompletion = true
        animator.startAnimation()
        animator.pauseAnimation()
        animator.fractionComplete = 0.08
        blurAnimator = animator
    }
}

// MARK: - The tooltip

final class TrailerTooltipView: UIView {
    private static let arrowSize = CGSize(width: 80, height: 56)   // w-20 h-14

    private let backdrop = FadingBackdropBlurView()
    private let arrow = SquiggleArrowView()
    private let label = UILabel()
    private var isMedium = true
    private(set) var fittingSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(backdrop)
        addSubview(arrow)
        addSubview(label)

        // font-excalifont text-base text-foreground text-center, a break in the text
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = 24
        paragraph.maximumLineHeight = 24
        label.attributedText = NSAttributedString(string: "Also available\non YouTube!", attributes: [
            .font: UIFont(name: "Excalifont-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.HayaseTheme.foreground,
            .paragraphStyle: paragraph,
        ])
        label.numberOfLines = 0
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// `md`: the arrow before the text and turned 130°; below it, after the text, mirrored and
    /// turned 230°. The text leans the other way in each.
    func configure(medium: Bool) {
        isMedium = medium
        let textSize = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let textWidth = ceil(textSize.width)
        let height = max(Self.arrowSize.height, ceil(textSize.height))
        let textFrame: CGRect
        let arrowFrame: CGRect
        let width: CGFloat
        if medium {
            // md:pe-4 md:ps-0, arrow md:me-2
            width = Self.arrowSize.width + 8 + textWidth + 16
            arrowFrame = CGRect(origin: CGPoint(x: 0, y: (height - Self.arrowSize.height) / 2), size: Self.arrowSize)
            textFrame = CGRect(x: Self.arrowSize.width + 8, y: (height - textSize.height) / 2,
                               width: textWidth, height: ceil(textSize.height))
        } else {
            // ps-4 flex-row-reverse, arrow ms-2
            width = 16 + textWidth + 8 + Self.arrowSize.width
            textFrame = CGRect(x: 16, y: (height - textSize.height) / 2, width: textWidth, height: ceil(textSize.height))
            arrowFrame = CGRect(origin: CGPoint(x: 16 + textWidth + 8, y: (height - Self.arrowSize.height) / 2),
                                size: Self.arrowSize)
        }
        fittingSize = CGSize(width: width, height: height)
        backdrop.frame = CGRect(origin: .zero, size: fittingSize)
        arrow.transform = .identity
        label.transform = .identity
        arrow.frame = arrowFrame
        label.frame = textFrame
        let degrees: CGFloat = medium ? 130 : 230
        // -scale-x-100 below md; the scale applies before the turn
        arrow.transform = CGAffineTransform(rotationAngle: degrees * .pi / 180).scaledBy(x: medium ? 1 : -1, y: 1)
        label.transform = CGAffineTransform(rotationAngle: (medium ? -3 : 3) * .pi / 180)   // md:-rotate-3 rotate-3
        arrow.setNeedsDisplay()
    }
}
