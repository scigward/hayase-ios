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

private struct ScheduleAiringEpisode {
    let airingAt: Date
    let episode: Int
    let mediaID: Int
    let titlePreferred: String?
    let coverURL: String?
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
        l.font = .systemFont(ofSize: 12, weight: .bold)
        l.textAlignment = .center
        l.textColor = .white
        return l
    }()
    private let epStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 2
        sv.alignment = .leading
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
            numberContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            numberContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            numberContainer.widthAnchor.constraint(equalToConstant: 24),
            numberContainer.heightAnchor.constraint(equalToConstant: 24),

            numberLabel.centerXAnchor.constraint(equalTo: numberContainer.centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: numberContainer.centerYAnchor),

            epStack.topAnchor.constraint(equalTo: numberContainer.bottomAnchor, constant: 4),
            epStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            epStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            epStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -2),
        ])
    }

    func configure(day: Int, isToday: Bool, isCurrentMonth: Bool,
                   episodes: [ScheduleAiringEpisode]) {
        numberLabel.text = "\(day)"
        contentView.alpha = isCurrentMonth ? 1 : 0.3
        numberContainer.backgroundColor = isToday ? CalendarDayCell.todayColor : .clear
        numberLabel.textColor = .white

        // Remove existing ep labels
        epStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Show up to 3 episode titles (matching Hayase: show up to 5 on large, all on drawer mobile)
        let shown = episodes.prefix(3)
        for ep in shown {
            let l = UILabel()
            l.font = .systemFont(ofSize: 9)
            l.textColor = UIColor(white: 0.65, alpha: 1)
            l.text = ep.titlePreferred ?? "Episode \(ep.episode)"
            l.numberOfLines = 1
            l.lineBreakMode = .byTruncatingTail
            epStack.addArrangedSubview(l)
        }
        if episodes.count > 3 {
            let l = UILabel()
            l.font = .systemFont(ofSize: 9)
            l.textColor = UIColor(white: 0.45, alpha: 1)
            l.text = "+ \(episodes.count - 3) more"
            epStack.addArrangedSubview(l)
        }
    }
}

// MARK: - ScheduleViewController

final class ScheduleViewController: UIViewController {

    // MARK: - State

    private var displayedMonth = Date()   // first moment of the displayed month
    private var airingEpisodes: [ScheduleAiringEpisode] = []
    private var isFetching = false

    // Cached day grid: array of (date, dayNumber, isCurrentMonth) sorted Mon–Sun
    private var calendarDays: [(date: Date, number: Int, isCurrentMonth: Bool)] = []

    // MARK: - Colors

    private let bgColor = UIColor(red: 0.039, green: 0.039, blue: 0.059, alpha: 1)
    private static let todayColor = UIColor(red: 0.239, green: 0.706, blue: 0.949, alpha: 1)

    // ISO 8601 calendar — week starts Monday (matches Hayase Mon-Sun column order)
    private let iso8601Calendar = Calendar(identifier: .iso8601)

    // MARK: - Tab bar init

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        tabBarItem = UITabBarItem(
            title: "Schedule",
            image: UIImage(systemName: "calendar"),
            selectedImage: UIImage(systemName: "calendar.badge.clock"))
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Schedule",
            image: UIImage(systemName: "calendar"),
            selectedImage: UIImage(systemName: "calendar.badge.clock"))
    }

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // Header: title + subtitle (matching Hayase's space-y-0.5 block)
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Airing Calendar"
        l.font = .systemFont(ofSize: 22, weight: .bold)
        l.textColor = .white
        return l
    }()
    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.text = "View upcoming episodes and their air times for the current season."
        l.font = .systemFont(ofSize: 14)
        l.textColor = UIColor(red: 0.631, green: 0.631, blue: 0.671, alpha: 1) // muted-foreground
        l.numberOfLines = 0
        return l
    }()

    // Month navigation row
    private lazy var prevButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        b.tintColor = .white
        b.addTarget(self, action: #selector(prevMonth), for: .touchUpInside)
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return b
    }()
    private let monthLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        return l
    }()
    private lazy var nextButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.right"), for: .normal)
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
        reloadCalendar()
        fetchAiringForMonth(displayedMonth)
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
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
        ])
    }

    private func buildUI() {
        // Title block
        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 4
        contentStack.addArrangedSubview(titleStack)

        // Month nav row
        let navRow = UIStackView(arrangedSubviews: [prevButton, monthLabel, nextButton])
        navRow.axis = .horizontal
        navRow.alignment = .center
        navRow.distribution = .equalSpacing
        contentStack.addArrangedSubview(navRow)

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

        // Mon Tue Wed Thu Fri Sat Sun header
        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.distribution = .fillEqually
        for name in dayHeaders {
            let l = UILabel()
            l.text = name
            l.font = .systemFont(ofSize: 11, weight: .medium)
            l.textColor = UIColor(white: 0.65, alpha: 1)
            l.textAlignment = .center
            l.heightAnchor.constraint(equalToConstant: 28).isActive = true
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
        df.dateFormat = "MMMM yyyy"
        monthLabel.text = df.string(from: monthStart)

        // Build days grid: first Monday on or before start of month → last Sunday on or after end
        let firstWeekday = cal.component(.weekday, from: monthStart)
        // iso8601 weekday: 1=Mon, 7=Sun
        let offsetToMonday = (firstWeekday - 1 + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -offsetToMonday, to: monthStart)!

        let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
        let lastWeekday = cal.component(.weekday, from: monthEnd)
        let offsetToSunday = (7 - lastWeekday + 7) % 7
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
        let cellH: CGFloat = 96
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
        spinner.startAnimating()

        AnimeService.sharedAnimeService.fetchAiringForMonth(month) { [weak self] entries in
            guard let self = self else { return }
            self.isFetching = false
            self.spinner.stopAnimating()
            self.fetchedMonths.insert(key)
            var existing = Set(self.airingEpisodes.map { "\($0.mediaID)-\($0.episode)" })
            for entry in entries {
                let k = "\(entry.media.id)-\(entry.episode)"
                if existing.insert(k).inserted {
                    self.airingEpisodes.append(ScheduleAiringEpisode(
                        airingAt: entry.airingAt,
                        episode:  entry.episode,
                        mediaID:  entry.media.id,
                        titlePreferred: entry.media.titleEnglish ?? entry.media.titleRomaji,
                        coverURL: entry.media.coverURL))
                }
            }
            self.calendarCV.reloadData()
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
            withReuseIdentifier: CalendarDayCell.reuseID, for: indexPath) as! CalendarDayCell
        let day = calendarDays[indexPath.item]
        let isToday = Calendar.current.isDateInToday(day.date)
        let eps = episodes(for: day.date)
        cell.configure(day: day.number, isToday: isToday,
                       isCurrentMonth: day.isCurrentMonth, episodes: eps)
        return cell
    }

    func collectionView(_ cv: UICollectionView, layout cvLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let w = cv.bounds.width / 7
        return CGSize(width: floor(w), height: 96)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let day = calendarDays[indexPath.item]
        let eps = episodes(for: day.date)
        guard !eps.isEmpty else { return }

        let df = DateFormatter(); df.dateFormat = "MMMM d"
        let alert = UIAlertController(title: df.string(from: day.date),
                                      message: nil, preferredStyle: .actionSheet)
        for ep in eps.prefix(8) {
            let title = "\(ep.titlePreferred ?? "Unknown") — Ep \(ep.episode)"
            alert.addAction(UIAlertAction(title: title, style: .default))
        }
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = cv.cellForItem(at: indexPath) ?? view
        }
        present(alert, animated: true)
    }
}

