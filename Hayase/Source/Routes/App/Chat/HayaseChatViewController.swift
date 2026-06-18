//
//  HayaseChatViewController.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/app/chat/+page.svelte
//

import UIKit

// MARK: - HayaseChatViewController

final class HayaseChatViewController: UIViewController {
    private let agreedKey = "hayase_chat_prevAgreed"
    private let stack = UIStackView()

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        configureTabBarItem()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTabBarItem()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.HayaseTheme.background
        setup()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func configureTabBarItem() {
        tabBarItem = UITabBarItem(
            title: "Chat",
            image: UIImage.hayaseIcon("messages-square"),
            selectedImage: UIImage.hayaseIcon("messages-square"))
    }

    private func setup() {
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 0
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
        ])
    }

    private func render() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if UserDefaults.standard.bool(forKey: agreedKey) {
            renderChatUnavailable()
        } else {
            renderWarning()
        }
    }

    private func renderWarning() {
        let warning = UIImageView(image: UIImage.hayaseIcon("triangle-alert"))
        warning.translatesAutoresizingMaskIntoConstraints = false
        warning.tintColor = UIColor(red: 245/255, green: 158/255, blue: 11/255, alpha: 1)
        warning.contentMode = .scaleAspectFit
        stack.addArrangedSubview(warning)
        NSLayoutConstraint.activate([
            warning.widthAnchor.constraint(equalToConstant: 192),
            warning.heightAnchor.constraint(equalToConstant: 192),
        ])

        let title = UILabel()
        title.text = "Content Warning"
        title.font = .nunito(ofSize: 30, weight: .bold)
        title.textColor = UIColor.HayaseTheme.foreground
        title.textAlignment = .center
        stack.addArrangedSubview(title)

        addText("This chat is completely unmoderated and may contain content that is not suitable for all audiences.",
                top: 20)
        addText("Be wary of impersonation.\nStaff will NEVER show up on this chat.",
                top: 8)

        let buttons = UIStackView()
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.axis = .horizontal
        buttons.spacing = 12
        buttons.alignment = .center
        buttons.distribution = .fillEqually
        stack.setCustomSpacing(28, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(buttons)

        let nope = makeButton(title: "Nope", background: UIColor.HayaseTheme.accent, foreground: UIColor.HayaseTheme.foreground)
        nope.addTarget(self, action: #selector(nopeTapped), for: .touchUpInside)
        let cont = makeButton(title: "Continue", background: UIColor(red: 0.49, green: 0.11, blue: 0.11, alpha: 1),
                              foreground: UIColor.HayaseTheme.foreground)
        cont.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        buttons.addArrangedSubview(nope)
        buttons.addArrangedSubview(cont)
        NSLayoutConstraint.activate([
            buttons.widthAnchor.constraint(equalToConstant: 220),
            buttons.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func renderChatUnavailable() {
        let icon = UIImageView(image: UIImage.hayaseIcon("messages-square"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor.HayaseTheme.mutedForeground
        icon.contentMode = .scaleAspectFit
        stack.addArrangedSubview(icon)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),
        ])
        addText("Chat", top: 16, size: 30, weight: .bold, color: UIColor.HayaseTheme.foreground)
        addText("The native IRC surface is not available in this build yet.", top: 12)
    }

    private func addText(_ text: String,
                         top: CGFloat,
                         size: CGFloat = 16,
                         weight: UIFont.Weight = .regular,
                         color: UIColor = UIColor.HayaseTheme.mutedForeground) {
        let label = UILabel()
        label.text = text
        label.font = .nunito(ofSize: size, weight: weight)
        label.textColor = color
        label.textAlignment = .center
        label.numberOfLines = 0
        if let previous = stack.arrangedSubviews.last {
            stack.setCustomSpacing(top, after: previous)
        }
        stack.addArrangedSubview(label)
    }

    private func makeButton(title: String, background: UIColor, foreground: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 16, weight: .bold)
        button.tintColor = foreground
        button.backgroundColor = background
        button.layer.cornerRadius = 6
        return button
    }

    @objc private func nopeTapped() {
        tabBarController?.selectedIndex = HayaseSidebarRoute.home.tabIndex ?? 0
    }

    @objc private func continueTapped() {
        UserDefaults.standard.set(true, forKey: agreedKey)
        render()
    }
}
