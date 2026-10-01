//
//  Page.swift
//  Hayase
//
//  Mirrors: src/routes/app/anime/[id]/+page.svelte and src/lib/components/ui/cards/recommendation.svelte
//

import UIKit

// MARK: - HTabBar

final class HTabBar: UIView {
    var onChange: ((Int) -> Void)?
    var selectedIndex: Int = 0 { didSet { updateSelection() } }
    var accentColor: UIColor = UIColor(white: 0.98, alpha: 1) { didSet { updateSelection() } }

    /// Interface tabs are always horizontal and scroll when they exceed the viewport.
    var isVertical: Bool = true {
        didSet {
            guard oldValue != isVertical else { return }
            applyOrientation()
        }
    }

    private let stack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    private var buttons: [UIButton] = []

    /// Height constraint for horizontal mode (h-9 = 36pt), deactivated in vertical mode.
    private var horizontalHeightConstraint: NSLayoutConstraint?
    /// Stack height == self height minus p-1 insets; only active in horizontal mode.
    private var stackHeightConstraint: NSLayoutConstraint?

    init(titles: [String]) {
        super.init(frame: .zero)
        // bg-muted = #27272a (neutral-800)
        backgroundColor = UIColor.HayaseTheme.secondary
        layer.cornerRadius = 8   // rounded-lg
        clipsToBounds = true

        addSubview(stack)

        // Stack pinned with p-1 (4pt) insets on all sides
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),       // p-1
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        for (i, title) in titles.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            // text-sm = 14px, font-medium (inactive default)
            btn.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
            // px-8 (32pt) py-1 (4pt) — matches web trigger overrides
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 32, bottom: 4, right: 32)
            btn.layer.cornerRadius = 6   // rounded-md
            btn.tag = i
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(btn)
            buttons.append(btn)
        }
        updateSelection()
        isVertical = false
        applyOrientation()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Calculates intrinsic content size based on orientation.
    /// Vertical: width = widest button + 8pt insets, height = sum of button heights + spacing + 8pt
    /// Horizontal: width = sum of button widths + spacing + 8pt, height = noIntrinsicMetric (set by constraint)
    override var intrinsicContentSize: CGSize {
        let totalButtonWidth = buttons.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width }
        let totalSpacing = CGFloat(max(buttons.count - 1, 0)) * stack.spacing
        return CGSize(width: totalButtonWidth + totalSpacing + 8, height: 36)
    }

    @objc private func tabTapped(_ sender: UIButton) {
        guard sender.tag != selectedIndex else { return }
        // transition-all: 150ms
        UIView.transition(with: self, duration: 0.15, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.selectedIndex = sender.tag
        }
        onChange?(sender.tag)
    }

    private func updateSelection() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        accentColor.getRed(&r, green: &g, blue: &b, alpha: nil)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let contrastColor: UIColor = luminance > 0.5 ? UIColor(white: 0.04, alpha: 1) : .white
        for (i, btn) in buttons.enumerated() {
            if i == selectedIndex {
                btn.backgroundColor = accentColor
                btn.setTitleColor(contrastColor, for: .normal)
                // data-[state=active]:font-bold
                btn.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
                // data-[state=active]:shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)
                btn.layer.masksToBounds = false
                btn.layer.shadowColor = UIColor.black.cgColor
                btn.layer.shadowOpacity = 0.1
                btn.layer.shadowOffset = CGSize(width: 0, height: 1)
                btn.layer.shadowRadius = 1.5
            } else {
                btn.backgroundColor = .clear
                btn.layer.shadowOpacity = 0
                btn.setTitleColor(UIColor.HayaseTheme.mutedForeground, for: .normal)
                // font-medium (inactive)
                btn.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
            }
        }
    }

    /// Configures stack axis, spacing, and constraints for vertical/horizontal mode.
    private func applyOrientation() {
        stack.axis = .horizontal
        stack.spacing = 0
        stackHeightConstraint?.isActive = false
        if horizontalHeightConstraint == nil {
            horizontalHeightConstraint = heightAnchor.constraint(equalToConstant: 36)
        }
        horizontalHeightConstraint?.isActive = true
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

// MARK: - UITableViewDataSource

extension AnimeDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .header:    return 1
        case .threads where embeddedThreadID != nil:
            return 1
        case _ where embeddedThreadID != nil:
            return 0
        case .episodes:
            if activeSection != .episodes { return 0 }
            let cols = usesSingleEpisodeGridTrack ? 1 : episodeColumnCount
            return (paginatedEpisodes.count + cols - 1) / cols
        case .episodePagination:
            return (activeSection == .episodes && !episodes.isEmpty) ? 1 : 0
        case .relations:
            guard activeSection == .relations else { return 0 }
            return hasRelationsContent ? 1 : 0
        case .threads:
            if activeSection != .threads { return 0 }
            if threadsLoading || threads.isEmpty { return 1 }
            let cols = threadGridColumnCount
            return (threads.count + cols - 1) / cols
        case .themes:
            if activeSection != .themes { return 0 }
            return themesLoading ? 1 : max(themes.count, 1)
        case .recommendations:
            if activeSection != .recommendations { return 0 }
            return recommendations.isEmpty ? 1 : 1
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .header:
            if embeddedThreadID != nil {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.backgroundColor = .clear
                cell.contentView.backgroundColor = .clear
                cell.selectionStyle = .none
                cell.clipsToBounds = false
                cell.contentView.clipsToBounds = false
                headerView.removeFromSuperview()
                tabBarContainer.removeFromSuperview()
                headerView.clipsToBounds = false
                headerView.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(headerView)
                NSLayoutConstraint.activate([
                    headerView.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    headerView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    headerView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    headerView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                ])
                headerView.updateLabelWidths(forContainerWidth: tableView.frame.width)
                return cell
            }

            let cell = tableView.dequeueReusableCell(withIdentifier: "HeaderCell", for: indexPath)
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.selectionStyle = .none
            cell.clipsToBounds = false
            cell.contentView.clipsToBounds = false
            if headerView.superview !== cell.contentView {
                headerView.clipsToBounds = false
                headerView.translatesAutoresizingMaskIntoConstraints = false
                tabBarContainer.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(headerView)
                cell.contentView.addSubview(tabBarContainer)
                NSLayoutConstraint.activate([
                    headerView.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    headerView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    headerView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    tabBarContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
                    tabBarContainer.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    tabBarContainer.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    tabBarContainer.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                ])
                applyTabBarLayoutForSizeClass()
            }
            headerView.updateLabelWidths(forContainerWidth: tableView.frame.width)
            return cell

        case .episodes:
            return makeEpisodeCell(for: indexPath)

        case .episodePagination:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PaginationCell", for: indexPath)
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.selectionStyle = .none
            if paginationBar.superview !== cell.contentView {
                paginationBar.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(paginationBar)
                NSLayoutConstraint.activate([
                    paginationBar.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    paginationBar.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    paginationBar.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    paginationBar.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                ])
            }
            paginationBar.configure(currentPage: currentEpisodePage, totalCount: episodes.count, perPage: episodesPerPage)
            paginationBar.applyPaddingForSizeClass(isRegular: traitCollection.horizontalSizeClass == .regular)
            return cell

        case .relations:
            return makeRelationsCell(for: indexPath)

        case .threads:
            return makeThreadCell(for: indexPath)

        case .themes:
            return makeThemeCell(for: indexPath)

        case .recommendations:
            return makeRecommendationCell(for: indexPath)

        case .none:
            return UITableViewCell()
        }
    }
}

// MARK: - UITableViewDelegate

extension AnimeDetailViewController: UITableViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        applyAnimeBannerScrollEffects(scrollView: scrollView)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return nil
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return nil
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section) {
        case .relations:
            let viewportHeight = view.window?.bounds.height ?? view.bounds.height
            let graphHeight = relationGraphExpanded ? viewportHeight * 0.8 : 288
            return graphHeight + 12
        default:                  return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        if Section(rawValue: indexPath.section) == .header { return 600 }
        return 100
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if embeddedThreadID != nil { return }
        switch Section(rawValue: indexPath.section) {
        case .episodes:
            // EpisodeCardView owns taps in both layouts. Its non-cancelling
            // recognizer also lets UITableView select the row on compact screens;
            // presenting here too stacks a second independently auto-selecting search.
            break
        case .threads:
            // ThreadCardView owns taps in every layout, as EpisodeCardView does.
            break
        case .themes:
            break
        default: break
        }
    }
}

// MARK: - UICollectionViewDataSource

extension AnimeDetailViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch collectionView.tag {
        case 400: return recommendations.count
        case 401: return RecommendationGridCell.skeletonItemCount
        default:  return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch collectionView.tag {
        case 400:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: AnimeCollectionViewCell.reuseID, for: indexPath) as? AnimeCollectionViewCell
            else { return UICollectionViewCell() }
            guard let item = recommendations[safe: indexPath.item] else { return cell }
            cell.configure(with: item)
            Hover.shared.bind(to: cell,
                              host: self,
                              mediaProvider: { item },
                              actions: hayasePreviewCardActions())
            return cell
        case 401:
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: SkeletonCardCell.reuseID, for: indexPath)
        default:
            return UICollectionViewCell()
        }
    }
}

// MARK: - UICollectionViewDelegate

extension AnimeDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch collectionView.tag {
        case 400:
            guard let item = recommendations[safe: indexPath.item] else { return }
            if let cell = collectionView.cellForItem(at: indexPath) as? AnimeCollectionViewCell,
               Hover.shared.handleTouchSelection(source: cell,
                                                 host: self,
                                                 media: item,
                                                 actions: hayasePreviewCardActions()) {
                return
            }
            Router.shared.navigateToAnime(item, hostTabIndex: hayaseTabIndex)
        default:
            return
        }
    }
}

// MARK: - Empty state helper

extension AnimeDetailViewController {
    func makeEmptyStateCell(text: String, loading: Bool) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        let titleLabel = UILabel()
        titleLabel.text = loading ? "Loading..." : "Ooops!"
        titleLabel.textColor = .white
        titleLabel.font = .nunito(ofSize: 36, weight: .bold)
        titleLabel.textAlignment = .center
        let messageLabel = UILabel()
        messageLabel.text = loading ? "Loading..." : text
        messageLabel.textColor = UIColor.HayaseTheme.mutedForeground
        messageLabel.font = .nunito(ofSize: 18)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        let arrangedSubviews: [UIView] = loading ? [messageLabel] : [titleLabel, messageLabel]
        let stack = UIStackView(arrangedSubviews: arrangedSubviews)
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: cell.contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -20),
            cell.contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])
        return cell
    }
}
