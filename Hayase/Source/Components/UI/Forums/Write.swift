//
//  Write.swift
//  Hayase
//
//  Native bottom-sheet writer for AniList forum comments.
//

import UIKit

final class ThreadWriteViewController: UIViewController, UITextViewDelegate {
    private let initialValue: String
    private let placeholder = "Write a comment on AniList \n\nDO NOT ASK FOR HELP HERE!\n\nAsking questions such as \"why isnt X playing\" or \"why cant i find any torrents\" !__WILL GET YOU BANNED__!\n\nTHIS IS A 3RD PARTY FORUM!"
    var onSend: ((String) -> Void)?

    private let textView = UITextView()
    private let placeholderLabel = UILabel()

    init(value: String = "") {
        self.initialValue = value
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        textView.text = initialValue
        placeholderLabel.isHidden = !initialValue.isEmpty
    }

    private func setupView() {
        view.backgroundColor = UIColor.HayaseTheme.background

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        textView.backgroundColor = UIColor(red: 40/255, green: 44/255, blue: 52/255, alpha: 1)
        textView.textColor = UIColor(red: 171/255, green: 178/255, blue: 191/255, alpha: 1)
        textView.font = .nunito(ofSize: 14)
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        textView.layer.cornerRadius = 0
        textView.delegate = self
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.addArrangedSubview(textView)

        placeholderLabel.text = placeholder
        placeholderLabel.font = .nunito(ofSize: 14)
        placeholderLabel.textColor = UIColor(red: 171/255, green: 178/255, blue: 191/255, alpha: 0.65)
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)

        let footer = UIStackView()
        footer.axis = .horizontal
        footer.alignment = .center
        footer.spacing = 8
        footer.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 16, right: 16)
        footer.isLayoutMarginsRelativeArrangement = true
        stack.addArrangedSubview(footer)

        footer.addArrangedSubview(UIView())

        let closeButton = makeTextButton("Close", primary: false)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        footer.addArrangedSubview(closeButton)

        let sendButton = makeTextButton("Send", primary: true)
        sendButton.setTitleColor(UIColor.HayaseTheme.primaryForeground, for: .normal)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        footer.addArrangedSubview(sendButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 224),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 24),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 21),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -21),
        ])

        if let sheet = sheetPresentationController {
            sheet.detents = [.custom { [weak self] context in
                let ratio: CGFloat = self?.traitCollection.horizontalSizeClass == .regular ? 0.5 : 0.9
                return context.maximumDetentValue * ratio
            }]
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = 0
        }
    }

    /// `<Button variant='secondary'>` (Close) and `<Button>` (Send), size default: h-9 px-4 py-2 text-sm font-medium
    private func makeTextButton(_ title: String, primary: Bool) -> SelectButton {
        let button = SelectButton(frame: .zero)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        if primary { button.applyPrimaryVariant() } else { button.applySecondaryVariant() }
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        return button
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func sendTapped() {
        let value = textView.text ?? ""
        dismiss(animated: true) { [onSend] in
            onSend?(value)
        }
    }
}
