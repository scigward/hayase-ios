//
//  TorrentClientStyle.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

enum TorrentClientStyle {
    static let compactPadding: CGFloat = 12
    static let regularPadding: CGFloat = 40
    static let compactSeparatorSpacing: CGFloat = 12
    static let regularSeparatorSpacing: CGFloat = 24
    static let contentMaxWidth: CGFloat = 1440
    static let clientContentMaxWidth: CGFloat = 1152
    static let sidebarWidth: CGFloat = 240
    static let sidebarGap: CGFloat = 48
    static let tableCornerRadius: CGFloat = 6

    static var background: UIColor { UIColor.HayaseTheme.background }
    static var foreground: UIColor { UIColor.HayaseTheme.foreground }
    static var muted: UIColor { UIColor.HayaseTheme.muted }
    static var mutedForeground: UIColor { UIColor.HayaseTheme.mutedForeground }
    static var border: UIColor { UIColor.HayaseTheme.border }
    static var input: UIColor { UIColor.HayaseTheme.input }
    static var accent: UIColor { UIColor.HayaseTheme.accent }
    static var primary: UIColor { UIColor.HayaseTheme.primary }
    static var primaryForeground: UIColor { UIColor.HayaseTheme.primaryForeground }
    static let green500 = rgb(34, 197, 94)
    static let blue500 = rgb(59, 130, 246)
    static let purple500 = rgb(168, 85, 247)
    static let yellow500 = rgb(234, 179, 8)

    static func isWideClientLayout(width: CGFloat) -> Bool {
        width >= 1024
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    static func configureRootView(_ view: UIView) {
        view.backgroundColor = background
        view.tintColor = foreground
    }

    static func configurePlainContentView(_ view: UIView) {
        view.backgroundColor = .clear
    }

    static func configureSeparator(_ view: UIView) {
        view.backgroundColor = border
    }

    static func configureTableShell(_ view: UIView) {
        view.backgroundColor = background
        view.layer.cornerRadius = tableCornerRadius
        view.layer.borderWidth = 1
        view.layer.borderColor = border.cgColor
        view.clipsToBounds = true
    }

    static func configureTableView(_ tableView: UITableView) {
        tableView.backgroundColor = background
        tableView.separatorColor = border
        tableView.separatorInset = .zero
        tableView.tableFooterView = UIView(frame: .zero)
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
    }

    static func configureTableCell(_ cell: UITableViewCell) {
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.tintColor = foreground
    }

    static func makeSearchField(placeholder: String) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: mutedForeground.withAlphaComponent(0.5)]
        )
        field.font = .nunito(ofSize: 14)
        field.textColor = foreground
        field.tintColor = foreground
        field.borderStyle = .none
        field.backgroundColor = background
        field.layer.cornerRadius = 6
        field.layer.borderWidth = 1
        field.layer.borderColor = input.cgColor
        field.clipsToBounds = true
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .search

        let icon = UIImageView(image: UIImage.hayaseIcon("search"))
        icon.tintColor = mutedForeground
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 8, y: 0, width: 24, height: 20)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 20))
        container.addSubview(icon)
        field.leftView = container
        field.leftViewMode = .always

        return field
    }

    static func configureIconButton(_ button: UIButton, variant: IconButtonVariant) {
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 0
        button.clipsToBounds = true
        button.tintColor = variant.tint
        button.backgroundColor = variant.background
    }

    static func setIconButtonEnabled(_ button: UIButton, enabled: Bool, variant: IconButtonVariant) {
        button.isEnabled = enabled
        button.tintColor = enabled ? variant.tint : mutedForeground.withAlphaComponent(0.5)
        button.backgroundColor = enabled ? variant.background : muted.withAlphaComponent(0.75)
        button.alpha = enabled ? 1 : 0.55
    }

    struct IconButtonVariant {
        let background: UIColor
        let tint: UIColor

        static let secondary = IconButtonVariant(background: muted, tint: foreground)
        static let destructive = IconButtonVariant(background: UIColor.systemRed, tint: UIColor.white)
    }
}
