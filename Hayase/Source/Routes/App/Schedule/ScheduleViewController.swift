//
//  ScheduleViewController.swift
//  Hayase
//
//  Matches Hayase's src/routes/app/schedule/+page.svelte exactly:
//  • Title "Airing Calendar" + subtitle text
//  • 7-column monthly calendar grid (Mon–Sun header)
//  • Prev / Next month chevron navigation
//  • Today cell: day number in rgb(61,180,242) circle (same as Hayase)
//  • Days outside current month: 30% opacity
//  • AniList airingSchedules data per day (episode count + titles)
//  • Tap day → modal list of airing episodes for that day
//

import UIKit

// MARK: - ScheduleAiringEpisode (lightweight model)

struct ScheduleAiringEpisode {
    let airingAt: Date
    let episode: Int
    let mediaID: Int
    let titlePreferred: String?
    let coverURL: String?
    let entry: AnimeItem.MediaListEntry?
}

// MARK: - CalendarDayCell

private final class CalendarDayCell: UICollectionViewCell {
    static let reuseID = "CalDayCell"

    // Today highlight: rgb(61,180,242) rounded circle
    private static let todayColor = UIColor(red: 0.239, green: 0.706, blue: 0.949, alpha: 1)
    private static let borderColor = UIColor(white: 0.15, alpha: 1)

    private let numberContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 12
        return v
    }()
    private let numberLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12, weight: .bold)
        l.textAlignment = .center
        l.textColor = .white
        return l
    }()
    private let epStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 6
        sv.alignment = .fill
        return sv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = CalendarDayCell.borderColor.cgColor

        numberContainer.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        epStack.translatesAutoresizingMaskIntoConstraints = false

        numberContainer.addSubview(numberLabel)
        contentView.addSubview(numberContainer)
        contentView.addSubview(epStack)

        NSLayoutConstraint.activate([
            numberContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            numberContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            numberContainer.widthAnchor.constraint(equalToConstant: 24),
            numberContainer.heightAnchor.constraint(equalToConstant: 24),

            numberLabel.centerXAnchor.constraint(equalTo: numberContainer.centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: numberContainer.centerYAnchor),

            epStack.topAnchor.constraint(greaterThanOrEqualTo: numberContainer.bottomAnchor, constant: 6),
            epStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            epStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            epStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    func configure(day: Int, isToday: Bool, isCurrentMonth: Bool,
                   episodes: [ScheduleAiringEpisode], expanded: Bool, showsEpisode: Bool, onSelect: @escaping (Int) -> Void) {
        numberLabel.text = "\(day)"
        contentView.alpha = isCurrentMonth ? 1 : 0.3
        numberContainer.backgroundColor = isToday ? CalendarDayCell.todayColor : .clear
        numberLabel.textColor = .white

        // Remove existing ep labels
        epStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if !expanded {
            if !episodes.isEmpty {
                let count = UILabel()
                count.font = .nunito(ofSize: 12)
                count.textColor = UIColor.HayaseTheme.foreground
                count.text = "\(episodes.count) ep\(episodes.count == 1 ? "" : "s")"
                count.adjustsFontSizeToFitWidth = true
                epStack.addArrangedSubview(count)
            }
            return
        }
        let shown = episodes.prefix(episodes.count > 6 ? 5 : 6)
        for episode in shown {
            let row = ScheduleEpisodeRow(episode: episode, showsEpisode: showsEpisode)
            row.onSelect = { onSelect(episode.mediaID) }
            epStack.addArrangedSubview(row)
        }
        if episodes.count > 6 {
            let label = UILabel()
            label.font = .nunito(ofSize: 12)
            label.textColor = UIColor.HayaseTheme.foreground
            label.text = "+ \(episodes.count - 5) more..."
            epStack.addArrangedSubview(label)
        }
    }
}

// MARK: - ScheduleViewController

final class ScheduleViewController: UIViewController {

    // MARK: - State

    private var displayedMonth = Date()   // first moment of the displayed month
    private var airingEpisodes: [ScheduleAiringEpisode] = []
    private var isFetching = false
    private let myList = HayaseSwitch(hideState: true)
    private var onlyMyList = UserDefaults.standard.object(forKey: "schedule-on-list") as? Bool ?? true
    private var didPrepareInitialCalendar = false
    private var lastViewportWidth: CGFloat = 0
    private var contentInsets: [NSLayoutConstraint] = []
    private var viewportWidth: CGFloat { view.window?.rootViewController?.view.bounds.width ?? view.bounds.width }
    private var dayHeight: CGFloat { viewportWidth >= 1024 ? 192 : 96 }

    // Cached day grid: array of (date, dayNumber, isCurrentMonth) sorted Mon–Sun
    private var calendarDays: [(date: Date, number: Int, isCurrentMonth: Bool)] = []

    // MARK: - Colors

    private let bgColor = UIColor.HayaseTheme.background
    private static let todayColor = UIColor(red: 0.239, green: 0.706, blue: 0.949, alpha: 1)

    // ISO 8601 calendar — week starts Monday (matches Hayase Mon-Sun column order)
    private let iso8601Calendar = Calendar(identifier: .iso8601)

    // MARK: - Tab bar init

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        tabBarItem = UITabBarItem(
            title: "Schedule",
            image: UIImage.hayaseIcon("calendar-days"),
            selectedImage: UIImage.hayaseIcon("calendar-days"))
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Schedule",
            image: UIImage.hayaseIcon("calendar-days"),
            selectedImage: UIImage.hayaseIcon("calendar-days"))
    }

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // Header: title + subtitle (matching Hayase's space-y-0.5 block)
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Airing Calendar"
        l.font = .nunito(ofSize: 24, weight: .bold)
        l.textColor = .white
        return l
    }()
    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.text = "View upcoming episodes and their air times for the current season."
        l.font = .nunito(ofSize: 16)
        l.textColor = UIColor(red: 0.631, green: 0.631, blue: 0.671, alpha: 1) // muted-foreground
        l.numberOfLines = 0
        return l
    }()

    // Month navigation row
    private lazy var prevButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage.hayaseIcon("chevron-left"), for: .normal)
        b.tintColor = .white
        b.addTarget(self, action: #selector(prevMonth), for: .touchUpInside)
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return b
    }()
    private let monthLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 20, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        return l
    }()
    private lazy var nextButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage.hayaseIcon("chevron-right"), for: .normal)
        b.tintColor = .white
        b.addTarget(self, action: #selector(nextMonth), for: .touchUpInside)
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return b
    }()

    // Calendar container: header row + grid
    private let calendarContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8
        v.layer.borderWidth = 0.5
        v.layer.borderColor = UIColor(white: 0.15, alpha: 1).cgColor
        v.clipsToBounds = true
        return v
    }()

    // Day-of-week header labels (Mon–Sun, matching Hayase)
    private let dayHeaders = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    // Calendar collection view
    private var calendarCV: UICollectionView!
    private var calendarHeightConstraint: NSLayoutConstraint!

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.hidesWhenStopped = true
        s.color = .white
        return s
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Schedule"
        view.backgroundColor = bgColor
        navigationController?.navigationBar.prefersLargeTitles = false

        setupScrollView()
        buildUI()

        // Start at current month
        displayedMonth = startOfMonth(for: Date())
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard calendarCV.bounds.width > 0 else { return }
        let first = !didPrepareInitialCalendar
        guard first || lastViewportWidth != viewportWidth else { return }
        didPrepareInitialCalendar = true
        lastViewportWidth = viewportWidth
        let padding: CGFloat = viewportWidth >= 768 ? 40 : 12
        for (index, constraint) in contentInsets.enumerated() {
            constraint.constant = index == 4 ? -padding * 2 : (index >= 2 ? -padding : padding)
        }
        reloadCalendar()
        calendarCV.collectionViewLayout.invalidateLayout()
        if first { fetchAiringForMonth(displayedMonth) }
    }

    // MARK: - UI Setup

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 24
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        contentInsets = [
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
        ]
        NSLayoutConstraint.activate(contentInsets)
    }

    private func buildUI() {
        // Title block
        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2
        contentStack.addArrangedSubview(titleStack)

        // Day-of-week header inside calendarContainer
        buildCalendarContainer()
        contentStack.addArrangedSubview(calendarContainer)

        // Spinner (centred in calendarContainer)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func buildCalendarContainer() {
        let outerStack = UIStackView()
        outerStack.axis = .vertical
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        myList.setOn(onlyMyList, animated: false)
        myList.accessibilityLabel = "My list"
        myList.addTarget(self, action: #selector(listFilterChanged), for: .valueChanged)
        let filterLabel = SettingsTypography.label("My list", size: 14, lineHeight: 20,
            color: UIColor.HayaseTheme.mutedForeground)
        let filter = UIStackView(arrangedSubviews: [myList, filterLabel])
        filter.spacing = 8
        filter.alignment = .center
        let month = UIStackView(arrangedSubviews: [monthLabel, filter])
        month.axis = .vertical
        month.spacing = 4
        month.alignment = .center
        let navRow = UIStackView(arrangedSubviews: [prevButton, month, nextButton])
        navRow.alignment = .center
        navRow.distribution = .equalSpacing
        navRow.isLayoutMarginsRelativeArrangement = true
        navRow.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        for button in [prevButton, nextButton] {
            button.layer.cornerRadius = 6
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        }
        outerStack.addArrangedSubview(navRow)
        // Mon Tue Wed Thu Fri Sat Sun header
        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.distribution = .fillEqually
        for name in dayHeaders {
            let l = UILabel()
            l.text = name
            l.font = .nunito(ofSize: 16)
            l.textColor = UIColor(white: 0.65, alpha: 1)
            l.textAlignment = .center
            l.heightAnchor.constraint(equalToConstant: 40).isActive = true
            headerRow.addArrangedSubview(l)
        }
        outerStack.addArrangedSubview(headerRow)

        // Collection view for calendar days
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.scrollDirection = .vertical

        calendarCV = UICollectionView(frame: .zero, collectionViewLayout: layout)
        calendarCV.translatesAutoresizingMaskIntoConstraints = false
        calendarCV.backgroundColor = .clear
        calendarCV.isScrollEnabled = false
        calendarCV.delegate = self
        calendarCV.dataSource = self
        calendarCV.register(CalendarDayCell.self, forCellWithReuseIdentifier: CalendarDayCell.reuseID)

        calendarHeightConstraint = calendarCV.heightAnchor.constraint(equalToConstant: 500)
        calendarHeightConstraint.isActive = true
        outerStack.addArrangedSubview(calendarCV)

        calendarContainer.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: calendarContainer.topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: calendarContainer.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: calendarContainer.trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: calendarContainer.bottomAnchor),
        ])
    }

    // MARK: - Calendar Logic

    private func reloadCalendar() {
        let cal = iso8601Calendar
        let monthStart = startOfMonth(for: displayedMonth)

        // Display month name
        let df = DateFormatter()
        df.dateFormat = "MMMM"
        monthLabel.text = df.string(from: monthStart)

        // Build days grid: first Monday on or before start of month → last Sunday on or after end
        let firstWeekday = cal.component(.weekday, from: monthStart)
        // Calendar weekday ordinals remain Sunday=1, even with an ISO calendar.
        let offsetToMonday = (firstWeekday + 5) % 7
        let gridStart = cal.date(byAdding: .day, value: -offsetToMonday, to: monthStart)!

        let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
        let lastWeekday = cal.component(.weekday, from: monthEnd)
        let offsetToSunday = (8 - lastWeekday) % 7
        let gridEnd = cal.date(byAdding: .day, value: offsetToSunday, to: monthEnd)!

        var days: [(date: Date, number: Int, isCurrentMonth: Bool)] = []
        var current = gridStart
        while current <= gridEnd {
            let number = cal.component(.day, from: current)
            let isCurrentMonth = cal.component(.month, from: current) == cal.component(.month, from: monthStart)
            days.append((date: current, number: number, isCurrentMonth: isCurrentMonth))
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        calendarDays = days

        // Update collection view height: rows × cell height (96pt matches Hayase h-24)
        let rows = days.count / 7
        let cellH = dayHeight
        calendarHeightConstraint.constant = cellH * CGFloat(rows)
        calendarCV.reloadData()
    }

    private func startOfMonth(for date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps)!
    }

    private func episodes(for date: Date) -> [ScheduleAiringEpisode] {
        let cal = Calendar.current
        return airingEpisodes.filter { ep in
            cal.isDate(ep.airingAt, inSameDayAs: date)
        }.sorted { $0.airingAt < $1.airingAt }
    }

    // MARK: - Navigation

    @objc private func listFilterChanged() {
        onlyMyList = myList.isOn
        UserDefaults.standard.set(onlyMyList, forKey: "schedule-on-list")
        fetchedMonths.removeAll()
        airingEpisodes.removeAll()
        calendarCV.reloadData()
        fetchAiringForMonth(displayedMonth)
    }

    @objc private func prevMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth)!
        reloadCalendar()
        fetchAiringForMonth(displayedMonth)
    }

    @objc private func nextMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth)!
        reloadCalendar()
        fetchAiringForMonth(displayedMonth)
    }

    // MARK: - Data fetch

    private var fetchedMonths: Set<String> = []

    private func fetchAiringForMonth(_ month: Date) {
        let key = monthKey(for: month)
        guard !fetchedMonths.contains(key), !isFetching else { return }
        isFetching = true
        let requestedFilter = onlyMyList

        AniListClient.shared.fetchAiringForMonthResult(month, onList: requestedFilter) { [weak self] result in
            guard let self = self else { return }
            self.isFetching = false
            self.spinner.stopAnimating()
            guard requestedFilter == self.onlyMyList else {
                self.fetchAiringForMonth(self.displayedMonth)
                return
            }

            switch result {
            case .success(let entries):
                self.fetchedMonths.insert(key)
                var existing = Set(self.airingEpisodes.map { "\($0.mediaID)-\($0.episode)" })
                for entry in entries {
                    let k = "\(entry.media.id)-\(entry.episode)"
                    if existing.insert(k).inserted {
                        self.airingEpisodes.append(ScheduleAiringEpisode(
                            airingAt: entry.airingAt,
                            episode:  entry.episode,
                            mediaID:  entry.media.id,
                            titlePreferred: entry.media.titleUserPreferred,
                            coverURL: entry.media.coverURL,
                            entry: entry.media.mediaListEntry))
                    }
                }
                self.calendarCV.reloadData()
            case .failure(let error):
                NSLog("[Schedule] AniList schedule failed: %@", error.description)
            }
            if self.monthKey(for: self.displayedMonth) != key {
                self.fetchAiringForMonth(self.displayedMonth)
            }
        }
    }

    private func monthKey(for date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return "\(y)-\(m)"
    }

}

// MARK: - UICollectionViewDataSource / Delegate

extension ScheduleViewController: UICollectionViewDataSource, UICollectionViewDelegate,
                                   UICollectionViewDelegateFlowLayout {

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        calendarDays.count
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath)
    -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(
            withReuseIdentifier: CalendarDayCell.reuseID, for: indexPath) as? CalendarDayCell ?? {
            let fallback = CalendarDayCell()
            return fallback
        }()
        guard let day = calendarDays[safe: indexPath.item] else { return cell }
        let isToday = Calendar.current.isDateInToday(day.date)
        let eps = episodes(for: day.date)
        cell.configure(day: day.number, isToday: isToday,
                       isCurrentMonth: day.isCurrentMonth, episodes: eps, expanded: viewportWidth >= 1024,
                       showsEpisode: viewportWidth >= 1280) { [weak self] id in
            Router.shared.navigate(.anime(id: id), hostTabIndex: self?.hayaseTabIndex)
        }
        return cell
    }

    func collectionView(_ cv: UICollectionView, layout cvLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = max(floor(cv.bounds.width / 7), 1)
        return CGSize(width: width, height: dayHeight)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let day = calendarDays[safe: indexPath.item] else { return }
        let eps = episodes(for: day.date)
        guard !eps.isEmpty else { return }

        let drawer = ScheduleDayViewController(episodes: eps) { [weak self] id in
            Router.shared.navigate(.anime(id: id), hostTabIndex: self?.hayaseTabIndex)
        }
        present(drawer, animated: false)
    }
}

