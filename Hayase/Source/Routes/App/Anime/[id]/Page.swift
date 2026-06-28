//
//  Page.swift
//  Hayase
//

import UIKit

// MARK: - HTabBar

final class HTabBar: UIView {
    var onChange: ((Int) -> Void)?
    var selectedIndex: Int = 0 { didSet { updateSelection() } }
    var accentColor: UIColor = UIColor(white: 0.98, alpha: 1) { didSet { updateSelection() } }

    /// Switches between vertical (iPhone) and horizontal (iPad) layout.
    /// iPhone: vertical stack, full-width buttons, flex-col gap-1
    /// iPad: horizontal inline, h-9, items-center
    var isVertical: Bool = true {
        didSet {
            guard oldValue != isVertical else { return }
            applyOrientation()
        }
    }

    private let stack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical  // default = vertical (iPhone)
        sv.spacing = 4       // gap-1 = 4pt
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
        backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
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
            btn.clipsToBounds = true
            btn.tag = i
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(btn)
            buttons.append(btn)
        }
        updateSelection()
        applyOrientation()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Calculates intrinsic content size based on orientation.
    /// Vertical: width = widest button + 8pt insets, height = sum of button heights + spacing + 8pt
    /// Horizontal: width = sum of button widths + spacing + 8pt, height = noIntrinsicMetric (set by constraint)
    override var intrinsicContentSize: CGSize {
        if isVertical {
            let maxButtonWidth = buttons.reduce(CGFloat(0)) { max($0, $1.intrinsicContentSize.width) }
            let totalButtonHeight = buttons.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.height }
            let totalSpacing = CGFloat(max(buttons.count - 1, 0)) * stack.spacing
            let width = maxButtonWidth + 8     // 2 × 4pt p-1 insets
            let height = totalButtonHeight + totalSpacing + 8
            return CGSize(width: width, height: height)
        } else {
            let totalButtonWidth = buttons.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width }
            let totalSpacing = CGFloat(max(buttons.count - 1, 0)) * stack.spacing
            let width = totalButtonWidth + totalSpacing + 8
            return CGSize(width: width, height: UIView.noIntrinsicMetric)
        }
    }

    @objc private func tabTapped(_ sender: UIButton) {
        selectedIndex = sender.tag
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
            } else {
                btn.backgroundColor = .clear
                btn.setTitleColor(UIColor(white: 0.649, alpha: 1), for: .normal) // text-muted-foreground
                // font-medium (inactive)
                btn.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
            }
        }
    }

    /// Configures stack axis, spacing, and constraints for vertical/horizontal mode.
    private func applyOrientation() {
        if isVertical {
            // Web: flex-col gap-1 max-w-72 w-full
            stack.axis = .vertical
            stack.spacing = 4  // gap-1 = 4pt
            horizontalHeightConstraint?.isActive = false
            stackHeightConstraint?.isActive = false
        } else {
            // Web: h-9 items-center justify-center, inline-flex
            stack.axis = .horizontal
            stack.spacing = 0  // Horizontal mode: no explicit gap between tabs; p-1 container insets provide visual separation
            // h-9 = 36pt total height (includes p-1 insets)
            if horizontalHeightConstraint == nil {
                horizontalHeightConstraint = heightAnchor.constraint(equalToConstant: 36)
            }
            horizontalHeightConstraint?.isActive = true
        }
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
        case .episodes:
            if activeSection != .episodes { return 0 }
            let cols = episodeColumnCount
            return (paginatedEpisodes.count + cols - 1) / cols
        case .episodePagination:
            return (activeSection == .episodes && !episodes.isEmpty) ? 1 : 0
        case .relations:
            guard activeSection == .relations else { return 0 }
            return hasRelationsContent ? 1 : 0
        case .threads:
            if activeSection != .threads { return 0 }
            if threadsLoading || threads.isEmpty { return 1 }
            let cols = threadColumnCount
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
        let offsetY = scrollView.contentOffset.y
        if offsetY < 0 {
            headerView.applyOverscrollZoom(-offsetY)
            headerView.applyScrollFade(0)
        } else {
            headerView.applyOverscrollZoom(0)
            headerView.applyScrollFade(offsetY)
        }
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
            return relationGraphExpanded ? max(332, tableView.bounds.height * 0.8 + 12) : 300
        default:                  return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        if Section(rawValue: indexPath.section) == .header { return 600 }
        return 100
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .episodes:
            if episodeColumnCount >= 2 { break }
            guard let ep = paginatedEpisodes[safe: indexPath.row] else { return }
            openExtensionSearch(episode: ep.number)
        case .threads:
            if threadColumnCount >= 2 { break }
            guard !threadsLoading, !threads.isEmpty else { return }
            guard let thread = threads[safe: indexPath.row] else { return }
            if let animeID = routeAnimeID {
                Router.shared.navigateToAnimeThread(animeID: animeID, threadID: thread.id, title: thread.title,
                                                   hostTabIndex: tabBarController?.selectedIndex)
            } else {
                let threadVC = ThreadDetailViewController(threadID: thread.id, title: thread.title)
                navigationController?.pushViewController(threadVC, animated: true)
            }
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
        case 100: return relations.count
        case 300: return staff.count
        case 400: return recommendations.count
        default:  return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch collectionView.tag {
        case 100:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: RelationCardCell.reuseID, for: indexPath) as? RelationCardCell
            else { return UICollectionViewCell() }
            guard let relation = relations[safe: indexPath.item] else { return cell }
            cell.configure(with: relation)
            return cell
        case 300:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: StaffCardCell.reuseID, for: indexPath) as? StaffCardCell
            else { return UICollectionViewCell() }
            guard let staffMember = staff[safe: indexPath.item] else { return cell }
            cell.configure(with: staffMember)
            return cell
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
        default:
            return UICollectionViewCell()
        }
    }
}

// MARK: - UICollectionViewDelegate

extension AnimeDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch collectionView.tag {
        case 100:
            guard let relation = relations[safe: indexPath.item] else { return }
            Router.shared.navigateToAnime(relation.media, hostTabIndex: tabBarController?.selectedIndex)
        case 400:
            guard let item = recommendations[safe: indexPath.item] else { return }
            if let cell = collectionView.cellForItem(at: indexPath) as? AnimeCollectionViewCell,
               Hover.shared.handleTouchSelection(source: cell,
                                                 host: self,
                                                 media: item,
                                                 actions: hayasePreviewCardActions()) {
                return
            }
            Router.shared.navigateToAnime(item, hostTabIndex: tabBarController?.selectedIndex)
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
        let label = UILabel()
        label.text = loading ? "Loading…" : text
        label.textColor = UIColor(white: loading ? 0.7 : 0.5, alpha: 1)
        label.font = .nunito(ofSize: 14)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
            label.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 40),
            label.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -40),
        ])
        return cell
    }
}
