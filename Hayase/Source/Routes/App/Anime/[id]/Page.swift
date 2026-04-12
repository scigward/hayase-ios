//
//  Page.swift
//  Hayase
//

import UIKit

// MARK: - HTabBar

final class HTabBar: UIView {

    var onChange: ((Int) -> Void)?
    var accentColor: UIColor = .white {
        didSet { updateSelection() }
    }
    var isVertical = false {
        didSet { stack.axis = isVertical ? .vertical : .horizontal }
    }

    private var buttons: [UIButton] = []
    private var selectedIndex = 0
    private let stack = UIStackView()

    init(titles: [String]) {
        super.init(frame: .zero)
        stack.axis = .horizontal
        stack.spacing = 0
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        layer.cornerRadius = 6
        clipsToBounds = true
        backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        heightAnchor.constraint(equalToConstant: 36).isActive = true

        for (i, title) in titles.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .nunito(ofSize: 13, weight: .bold)
            btn.tag = i
            btn.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(btn)
            buttons.append(btn)
        }
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped(_ sender: UIButton) {
        selectedIndex = sender.tag
        updateSelection()
        onChange?(selectedIndex)
    }

    private func updateSelection() {
        for (i, btn) in buttons.enumerated() {
            let isSelected = i == selectedIndex
            btn.backgroundColor = isSelected ? accentColor : .clear
            btn.setTitleColor(
                isSelected ? ExtensionSearchViewController.luminanceContrastColor(for: accentColor) : .white,
                for: .normal)
            btn.titleLabel?.font = .nunito(ofSize: 13, weight: isSelected ? .heavy : .bold)
        }
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
            return (activeSection == .episodes && totalEpisodePages > 1) ? 1 : 0
        case .relations: return (activeSection == .relations && !relations.isEmpty) ? 1 : 0
        case .threads:
            if activeSection != .threads { return 0 }
            if threadsLoading || threads.isEmpty { return 1 }
            let cols = threadColumnCount
            return (threads.count + cols - 1) / cols
        case .themes:
            if activeSection != .themes { return 0 }
            return themesLoading ? 1 : max(themes.count, 1)
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
        } else {
            headerView.applyOverscrollZoom(0)
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
        case .relations:          return 160
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
            let ep = paginatedEpisodes[indexPath.row]
            openExtensionSearch(episode: ep.number)
        case .threads:
            if threadColumnCount >= 2 { break }
            guard !threadsLoading, !threads.isEmpty else { return }
            let thread = threads[indexPath.row]
            let threadVC = ThreadDetailViewController(threadID: thread.id, title: thread.title)
            navigationController?.pushViewController(threadVC, animated: true)
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
            cell.configure(with: relations[indexPath.item])
            return cell
        case 300:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: StaffCardCell.reuseID, for: indexPath) as? StaffCardCell
            else { return UICollectionViewCell() }
            cell.configure(with: staff[indexPath.item])
            return cell
        default:
            return UICollectionViewCell()
        }
    }
}

// MARK: - UICollectionViewDelegate

extension AnimeDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard collectionView.tag == 100 else { return }
        let relation = relations[indexPath.item]
        guard let detailVC = storyboard?.instantiateViewController(
            withIdentifier: "AnimeDetailVC") as? AnimeDetailViewController else { return }
        detailVC.animeItem = relation.media
        navigationController?.pushViewController(detailVC, animated: true)
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
