//
//  ScheduleViewController.swift
//  Hayase
//
//  Mirrors: interface routes/app/schedule/+page.svelte.
//  • Title "Airing Calendar" + subtitle text
//  • 7-column monthly calendar grid (Mon–Sun header) in a bordered, rounded box
//  • Prev / Next month chevron navigation and the "My list" switch
//  • Today cell: day number in an rgb(61,180,242) circle
//  • Days outside the month shown: 30% opacity
//  • One query per quarter, with the seasons around it; nothing shown but day numbers while it
//    loads, an error block when it fails
//  • Wide screens list a day's episodes (cover tooltip over each, the rest under "+ n more...");
//    narrow ones show a count that opens a drawer
//

import UIKit

// MARK: - ScheduleAiringEpisode (lightweight model)

struct ScheduleAiringEpisode {
    let airingAt: Date
    let episode: Int
    let mediaID: Int
    let titlePreferred: String?
    let coverURL: String?
    let coverColor: String?
    let entry: AnimeItem.MediaListEntry?
}

// MARK: - CalendarDayCell

private final class CalendarDayCell: UICollectionViewCell {
    static let reuseID = "CalDayCell"

    // Today highlight: rgb(61,180,242) rounded circle
    private static let todayColor = UIColor(red: 0.239, green: 0.706, blue: 0.949, alpha: 1)

    /// `opacity-30` on days outside the month dims what is in the cell, not its borders.
    private let content = UIView()
    private let rightBorder = CALayer()
    private let bottomBorder = CALayer()
    private let numberContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 12
        return v
    }()
    private let numberLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12, weight: .bold)
        l.textAlignment = .center
        l.textColor = UIColor.HayaseTheme.foreground
        return l
    }()
    private let epStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 6
        sv.alignment = .fill
        return sv
    }()
    private var showsRightBorder = false
    private var showsBottomBorder = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        rightBorder.backgroundColor = UIColor.HayaseTheme.border.cgColor
        bottomBorder.backgroundColor = UIColor.HayaseTheme.border.cgColor
        contentView.layer.addSublayer(rightBorder)
        contentView.layer.addSublayer(bottomBorder)

        content.translatesAutoresizingMaskIntoConstraints = false
        numberContainer.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        epStack.translatesAutoresizingMaskIntoConstraints = false

        numberContainer.addSubview(numberLabel)
        content.addSubview(numberContainer)
        content.addSubview(epStack)
        contentView.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: contentView.topAnchor),
            content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            numberContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),   // mx-3
            numberContainer.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),           // py-3
            numberContainer.widthAnchor.constraint(equalToConstant: 24),
            numberContainer.heightAnchor.constraint(equalToConstant: 24),

            numberLabel.centerXAnchor.constraint(equalTo: numberContainer.centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: numberContainer.centerYAnchor),

            epStack.topAnchor.constraint(greaterThanOrEqualTo: numberContainer.bottomAnchor, constant: 6),   // mt-1.5
            epStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            epStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            epStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // border-r and border-b of the grid's cells: 1px, inside the cell's box
        rightBorder.frame = CGRect(x: contentView.bounds.maxX - 1, y: 0, width: 1, height: contentView.bounds.height)
        bottomBorder.frame = CGRect(x: 0, y: contentView.bounds.maxY - 1, width: contentView.bounds.width, height: 1)
        rightBorder.isHidden = !showsRightBorder
        bottomBorder.isHidden = !showsBottomBorder
        CATransaction.commit()
    }

    struct Layout {
        var day: Int
        var isToday: Bool
        var isCurrentMonth: Bool
        var showsRightBorder: Bool
        var showsBottomBorder: Bool
        /// `lg`: the cell lists the day's episodes itself, instead of counting them.
        var expanded: Bool
        var extraLarge: Bool
    }

    func configure(_ layout: Layout, episodes: [ScheduleAiringEpisode],
                   onSelect: @escaping (Int) -> Void) {
        numberLabel.text = "\(layout.day)"
        content.alpha = layout.isCurrentMonth ? 1 : 0.3
        numberContainer.backgroundColor = layout.isToday ? CalendarDayCell.todayColor : .clear
        showsRightBorder = layout.showsRightBorder
        showsBottomBorder = layout.showsBottomBorder
        setNeedsLayout()

        epStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !episodes.isEmpty else { return }

        if !layout.expanded {
            // `{episodes.length} ep{s}`, in a button, so centred
            let count = UILabel()
            count.font = .nunito(ofSize: 12)
            count.textColor = UIColor.HayaseTheme.foreground
            count.textAlignment = .center
            count.text = "\(episodes.count) ep\(episodes.count > 1 ? "s" : "")"
            count.lineBreakMode = .byTruncatingTail
            epStack.addArrangedSubview(count)
            return
        }

        let shown = episodes.count > 6 ? Array(episodes.prefix(5)) : episodes
        for episode in shown {
            let row = ScheduleEpisodeRow(episode: episode, style: .calendar, extraLarge: layout.extraLarge)
            row.onSelect = { onSelect(episode.mediaID) }
            epStack.addArrangedSubview(row)
        }
        if episodes.count > 6 {
            epStack.addArrangedSubview(MoreEpisodesLabel(episodes: Array(episodes.dropFirst(5)),
                                                         extraLarge: layout.extraLarge, onSelect: onSelect))
        }
    }
}

/// `+ {n} more...`, which lists the rest of the day in a tooltip while the pointer is over it.
private final class MoreEpisodesLabel: UILabel {
    private let episodes: [ScheduleAiringEpisode]
    private let extraLarge: Bool
    private let onSelect: (Int) -> Void

    init(episodes: [ScheduleAiringEpisode], extraLarge: Bool, onSelect: @escaping (Int) -> Void) {
        self.episodes = episodes
        self.extraLarge = extraLarge
        self.onSelect = onSelect
        super.init(frame: .zero)
        font = .nunito(ofSize: 12)
        textColor = UIColor.HayaseTheme.mutedForeground   // text-muted-foreground
        text = "+ \(episodes.count) more..."
        isUserInteractionEnabled = true
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        if recognizer.state == .began {
            ScheduleTooltip.shared.showEpisodes(episodes, extraLarge: extraLarge, from: self, onSelect: onSelect)
        } else if recognizer.state == .ended || recognizer.state == .cancelled {
            ScheduleTooltip.shared.scheduleHide()
        }
    }
}

// MARK: - ScheduleViewController

final class ScheduleViewController: UIViewController {

    // MARK: - State

    private enum QueryState {
        case fetching
        case failed(String)
        case loaded
    }

    private var displayedMonth = Date()   // first moment of the displayed month
    private var airingEpisodes: [ScheduleAiringEpisode] = []
    private var queryState = QueryState.fetching
    private var requestGeneration = 0
    private var requestedQuarter: Date?
    private let myList = HayaseSwitch(hideState: true)
    private var onlyMyList = UserDefaults.standard.object(forKey: "schedule-on-list") as? Bool ?? true
    private var didPrepareInitialCalendar = false
    private var lastViewportWidth: CGFloat = 0
    private var contentInsets: [NSLayoutConstraint] = []
    private var viewportWidth: CGFloat { view.window?.rootViewController?.view.bounds.width ?? view.bounds.width }
    private var dayHeight: CGFloat { viewportWidth >= 1024 ? 192 : 96 }   // h-24 lg:h-48

    // Cached day grid: array of (date, dayNumber, isCurrentMonth) sorted Mon–Sun
    private var calendarDays: [(date: Date, number: Int, isCurrentMonth: Bool)] = []
    /// The day's episodes by start of day, `dayMap` in the page.
    private var episodesByDay: [Date: [ScheduleAiringEpisode]] = [:]

    // MARK: - Colors

    private let bgColor = UIColor.HayaseTheme.background

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
        l.textColor = UIColor.HayaseTheme.foreground
        return l
    }()
    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.text = "View upcoming episodes and their air times for the current season."
        l.font = .nunito(ofSize: 16)
        l.textColor = UIColor.HayaseTheme.mutedForeground
        l.numberOfLines = 0
        return l
    }()

    // Month navigation row: `variant='outline' class='bg-transparent animated-icon'`, `size='icon'`
    private lazy var prevButton = makeMonthButton(icon: "chevron-left", shift: -3, action: #selector(prevMonth))
    private let monthLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 20, weight: .bold)   // font-bold text-xl
        l.textColor = UIColor.HayaseTheme.foreground
        l.textAlignment = .center
        return l
    }()
    private lazy var nextButton = makeMonthButton(icon: "chevron-right", shift: 3, action: #selector(nextMonth))

    private func makeMonthButton(icon: String, shift: CGFloat, action: Selector) -> Button {
        let button = Button(iconName: icon, pointSize: 24)   // h-6 w-6
        button.restingBackground = .clear
        button.selectedIconShift = shift
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // Calendar container: header row + grid
    private let calendarContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8   // rounded-lg
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        v.clipsToBounds = true
        return v
    }()

    // Day-of-week header labels (Mon–Sun, matching Hayase)
    private let dayHeaders = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    // Calendar collection view
    private var calendarCV: UICollectionView!
    private var calendarHeightConstraint: NSLayoutConstraint!
    private let errorView = UIView()
    private let errorMessageLabel = UILabel()

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
        NotificationCenter.default.addObserver(self, selector: #selector(refocusSchedule),
                                               name: AniListRefocus.didRefocus, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard calendarCV.bounds.width > 0 else { return }
        let first = !didPrepareInitialCalendar
        guard first || lastViewportWidth != viewportWidth else { return }
        didPrepareInitialCalendar = true
        lastViewportWidth = viewportWidth
        let padding: CGFloat = viewportWidth >= 768 ? 40 : 12   // p-3 md:p-10
        for (index, constraint) in contentInsets.enumerated() {
            constraint.constant = index == 4 ? -padding * 2 : (index >= 2 ? -padding : padding)
        }
        reloadCalendar()
        calendarCV.collectionViewLayout.invalidateLayout()
        if first { fetchSchedule() }
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
        contentStack.spacing = 24   // mb-6
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
        // `w-full max-w-[1800px]`, centred by the page's `items-center`
        let holder = UIView()
        calendarContainer.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(calendarContainer)
        let fill = [
            calendarContainer.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            calendarContainer.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
        ]
        fill.forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate(fill + [
            calendarContainer.topAnchor.constraint(equalTo: holder.topAnchor),
            calendarContainer.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            calendarContainer.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            calendarContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 1800),
        ])
        contentStack.addArrangedSubview(holder)
    }

    private func line() -> UIView {
        let line = UIView()
        line.backgroundColor = UIColor.HayaseTheme.border
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func buildCalendarContainer() {
        let outerStack = UIStackView()
        outerStack.axis = .vertical
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        myList.setOn(onlyMyList, animated: false)
        myList.accessibilityLabel = "My list"
        myList.addTarget(self, action: #selector(listFilterChanged), for: .valueChanged)
        // `Label`: text-sm font-medium leading-none
        let filterLabel = UILabel()
        filterLabel.font = .nunito(ofSize: 14, weight: .medium)
        filterLabel.textColor = UIColor.HayaseTheme.mutedForeground
        filterLabel.text = "My list"
        let filter = UIStackView(arrangedSubviews: [myList, filterLabel])
        filter.spacing = 8   // space-x-2
        filter.alignment = .center
        let month = UIStackView(arrangedSubviews: [monthLabel, filter])
        month.axis = .vertical
        month.spacing = 4   // mt-1
        month.alignment = .center
        let navRow = UIStackView(arrangedSubviews: [prevButton, month, nextButton])
        navRow.alignment = .center
        navRow.distribution = .equalSpacing
        navRow.isLayoutMarginsRelativeArrangement = true
        navRow.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)   // p-4
        outerStack.addArrangedSubview(navRow)
        outerStack.addArrangedSubview(line())

        // Mon Tue Wed Thu Fri Sat Sun header
        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.distribution = .fillEqually
        for name in dayHeaders {
            let l = UILabel()
            l.text = name
            l.font = .nunito(ofSize: 16)
            l.textColor = UIColor.HayaseTheme.foreground
            l.textAlignment = .center
            l.heightAnchor.constraint(equalToConstant: 40).isActive = true   // py-2
            headerRow.addArrangedSubview(l)
        }
        outerStack.addArrangedSubview(headerRow)
        outerStack.addArrangedSubview(line())

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

        // `{:else if $query.error}`: a block as tall as 24rem in place of the days
        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.isHidden = true
        let oops = UILabel()
        oops.text = "Ooops!"
        oops.font = .nunito(ofSize: 36, weight: .bold)   // font-bold text-4xl
        oops.textColor = UIColor.HayaseTheme.foreground
        oops.textAlignment = .center
        let wrong = UILabel()
        wrong.text = "Looks like something went wrong!"
        wrong.font = .nunito(ofSize: 18)   // text-lg
        wrong.textColor = UIColor.HayaseTheme.mutedForeground
        wrong.textAlignment = .center
        wrong.numberOfLines = 0
        errorMessageLabel.font = .nunito(ofSize: 18)
        errorMessageLabel.textColor = UIColor.HayaseTheme.mutedForeground
        errorMessageLabel.textAlignment = .center
        errorMessageLabel.numberOfLines = 0
        let errorStack = UIStackView(arrangedSubviews: [oops, wrong, errorMessageLabel])
        errorStack.axis = .vertical
        errorStack.spacing = 4   // mb-1 after the title
        errorStack.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(errorStack)
        NSLayoutConstraint.activate([
            errorView.heightAnchor.constraint(equalToConstant: 384),   // h-96
            errorStack.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
            errorStack.leadingAnchor.constraint(equalTo: errorView.leadingAnchor, constant: 20),   // p-5
            errorStack.trailingAnchor.constraint(equalTo: errorView.trailingAnchor, constant: -20),
        ])
        outerStack.addArrangedSubview(errorView)

        // The grid's own 1px border takes room.
        calendarContainer.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: calendarContainer.topAnchor, constant: 1),
            outerStack.leadingAnchor.constraint(equalTo: calendarContainer.leadingAnchor, constant: 1),
            outerStack.trailingAnchor.constraint(equalTo: calendarContainer.trailingAnchor, constant: -1),
            outerStack.bottomAnchor.constraint(equalTo: calendarContainer.bottomAnchor, constant: -1),
        ])
    }

    // MARK: - Calendar Logic

    private func reloadCalendar() {
        let cal = iso8601Calendar
        let monthStart = startOfMonth(for: displayedMonth)

        // `now.toLocaleString('en-US', { month: 'long' })`
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
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
        groupEpisodesByDay()

        // Update collection view height: rows × cell height
        let rows = days.count / 7
        calendarHeightConstraint.constant = dayHeight * CGFloat(rows)
        applyQueryState()
        calendarCV.reloadData()
    }

    private func applyQueryState() {
        if case .failed(let message) = queryState {
            errorMessageLabel.text = message
            errorView.isHidden = false
            calendarCV.isHidden = true
        } else {
            errorView.isHidden = true
            calendarCV.isHidden = false
        }
    }

    private func startOfMonth(for date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps)!
    }

    /// `aggregate()`: each episode goes on the day it airs, whatever month that is, and the
    /// day's episodes are in the order they air.
    private func groupEpisodesByDay() {
        let cal = Calendar.current
        var map: [Date: [ScheduleAiringEpisode]] = [:]
        for episode in airingEpisodes {
            map[cal.startOfDay(for: episode.airingAt), default: []].append(episode)
        }
        episodesByDay = map.mapValues { $0.sorted { $0.airingAt < $1.airingAt } }
    }

    private func episodes(for date: Date) -> [ScheduleAiringEpisode] {
        guard case .loaded = queryState else { return [] }
        return episodesByDay[Calendar.current.startOfDay(for: date)] ?? []
    }

    // MARK: - Navigation

    @objc private func listFilterChanged() {
        onlyMyList = myList.isOn
        UserDefaults.standard.set(onlyMyList, forKey: "schedule-on-list")
        fetchSchedule()
    }

    @objc private func prevMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth)!
        reloadCalendar()
        fetchScheduleIfQuarterChanged()
    }

    @objc private func nextMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth)!
        reloadCalendar()
        fetchScheduleIfQuarterChanged()
    }

    // MARK: - Data fetch

    /// `queryDate`: the first day of the quarter the month on show is in.
    private func quarterStart(for date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        let month = ((comps.month ?? 1) - 1) / 3 * 3 + 1
        return cal.date(from: DateComponents(year: comps.year, month: month, day: 1))!
    }

    /// `refocusExchange`: the schedule asks again when the app comes back after a minute away.
    @objc private func refocusSchedule() {
        guard view.window != nil, requestedQuarter != nil else { return }
        fetchSchedule()
    }

    private func fetchScheduleIfQuarterChanged() {
        guard requestedQuarter != quarterStart(for: displayedMonth) else { return }
        fetchSchedule()
    }

    private func fetchSchedule() {
        let quarter = quarterStart(for: displayedMonth)
        requestedQuarter = quarter
        requestGeneration += 1
        let generation = requestGeneration
        // While it loads the grid is only day numbers.
        queryState = .fetching
        airingEpisodes = []
        groupEpisodesByDay()
        applyQueryState()
        calendarCV.reloadData()

        AniListClient.shared.fetchAiringForMonthResult(quarter, onList: onlyMyList) { [weak self] result in
            guard let self, generation == self.requestGeneration else { return }
            switch result {
            case .success(let entries):
                self.airingEpisodes = entries.map {
                    ScheduleAiringEpisode(airingAt: $0.airingAt,
                                          episode: $0.episode,
                                          mediaID: $0.media.id,
                                          titlePreferred: $0.media.titleUserPreferred,
                                          coverURL: $0.media.coverURL,
                                          coverColor: $0.media.coverColor,
                                          entry: $0.media.mediaListEntry)
                }
                self.queryState = .loaded
            case .failure(let error):
                NSLog("[Schedule] AniList schedule failed: %@", error.description)
                self.queryState = .failed(error.description)
            }
            self.groupEpisodesByDay()
            self.applyQueryState()
            self.calendarCV.reloadData()
        }
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
        let rows = calendarDays.count / 7
        // Every cell has a right border but the Sundays', and a bottom one but the last row's.
        let layout = CalendarDayCell.Layout(day: day.number,
                                            isToday: Calendar.current.isDateInToday(day.date),
                                            isCurrentMonth: day.isCurrentMonth,
                                            showsRightBorder: indexPath.item % 7 != 6,
                                            showsBottomBorder: indexPath.item / 7 != rows - 1,
                                            expanded: viewportWidth >= 1024,
                                            extraLarge: viewportWidth >= 1280)
        cell.configure(layout, episodes: episodes(for: day.date)) { [weak self] id in
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
        // Below `lg` the whole day is the drawer's trigger, whether or not anything airs.
        guard viewportWidth < 1024, let day = calendarDays[safe: indexPath.item] else { return }
        let drawer = ScheduleDayViewController(episodes: episodes(for: day.date),
                                               extraLarge: viewportWidth >= 1280) { [weak self] id in
            Router.shared.navigate(.anime(id: id), hostTabIndex: self?.hayaseTabIndex)
        }
        present(drawer, animated: false)
    }
}
