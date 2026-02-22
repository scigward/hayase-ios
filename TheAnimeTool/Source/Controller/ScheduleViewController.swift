//
//  ScheduleViewController.swift
//  TheAnimeTool
//
//  Replica of Hayase's src/routes/app/schedule/+page.svelte.
//  Shows anime airing on each day of the current week via AniList airingSchedules.
//  A 7-day chip picker (Sun–Sat) lets the user switch days; today is auto-selected.
//

import UIKit

final class ScheduleViewController: UIViewController {

    // Day names matching Calendar.weekday (1=Sunday … 7=Saturday)
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var selectedWeekday: Int = 0   // 0–6 (Sun–Sat)
    private var items: [AnimeItem] = []
    private var isLoading = false

    // MARK: - UI

    private lazy var dayPickerScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.alwaysBounceHorizontal = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var dayPickerStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private var dayButtons: [UIButton] = []

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        let cols: CGFloat = 3
        let spacing: CGFloat = 1
        let width = (UIScreen.main.bounds.width - spacing * (cols - 1)) / cols
        layout.itemSize = CGSize(width: width, height: width * 1.5)
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = .zero

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .systemBackground
        cv.register(AnimeCollectionViewCell.self,
                     forCellWithReuseIdentifier: AnimeCollectionViewCell.reuseID)
        cv.dataSource = self
        cv.delegate = self
        return cv
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.translatesAutoresizingMaskIntoConstraints = false
        s.hidesWhenStopped = true
        return s
    }()

    private let emptyLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "No anime airing today"
        l.textColor = .secondaryLabel
        l.font = .systemFont(ofSize: 15)
        l.textAlignment = .center
        l.isHidden = true
        return l
    }()

    // MARK: - init (tab bar item set here so it's visible before viewDidLoad)

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Schedule",
            image: UIImage(systemName: "calendar"),
            selectedImage: UIImage(systemName: "calendar.badge.clock"))
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Schedule"
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemBackground

        setupDayPicker()
        setupCollectionView()

        // Select today
        let todayWeekday = Calendar.current.component(.weekday, from: Date()) - 1  // 0=Sun
        selectDay(todayWeekday, animated: false)
    }

    // MARK: - Layout

    private func setupDayPicker() {
        view.addSubview(dayPickerScrollView)
        dayPickerScrollView.addSubview(dayPickerStack)

        NSLayoutConstraint.activate([
            dayPickerScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            dayPickerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dayPickerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dayPickerScrollView.heightAnchor.constraint(equalToConstant: 52),

            dayPickerStack.topAnchor.constraint(equalTo: dayPickerScrollView.topAnchor, constant: 8),
            dayPickerStack.bottomAnchor.constraint(equalTo: dayPickerScrollView.bottomAnchor, constant: -8),
            dayPickerStack.leadingAnchor.constraint(equalTo: dayPickerScrollView.leadingAnchor, constant: 12),
            dayPickerStack.trailingAnchor.constraint(equalTo: dayPickerScrollView.trailingAnchor, constant: -12),
        ])

        for (i, name) in dayNames.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(name, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            btn.layer.cornerRadius = 14
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
            btn.tag = i
            btn.addTarget(self, action: #selector(dayButtonTapped(_:)), for: .touchUpInside)
            dayPickerStack.addArrangedSubview(btn)
            dayButtons.append(btn)
        }
    }

    private func setupCollectionView() {
        view.addSubview(collectionView)
        view.addSubview(spinner)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: dayPickerScrollView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
        ])
    }

    // MARK: - Day selection

    @objc private func dayButtonTapped(_ sender: UIButton) {
        selectDay(sender.tag, animated: true)
    }

    private func selectDay(_ weekday: Int, animated: Bool) {
        selectedWeekday = weekday
        for (i, btn) in dayButtons.enumerated() {
            let isSelected = i == weekday
            UIView.animate(withDuration: animated ? 0.2 : 0) {
                btn.backgroundColor = isSelected ? .label : .secondarySystemBackground
                btn.setTitleColor(isSelected ? .systemBackground : .label, for: .normal)
            }
        }
        emptyLabel.text = "No anime airing on \(dayNames[weekday])"
        fetchAnime(for: weekday)
    }

    // MARK: - Data

    private func fetchAnime(for weekday: Int) {
        guard !isLoading else { return }
        isLoading = true
        spinner.startAnimating()
        emptyLabel.isHidden = true
        items = []
        collectionView.reloadData()

        AnimeService.sharedAnimeService.fetchAiringForWeekday(weekday) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            self.spinner.stopAnimating()
            self.items = result
            self.collectionView.reloadData()
            self.emptyLabel.isHidden = !result.isEmpty
        }
    }
}

// MARK: - UICollectionViewDataSource

extension ScheduleViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: AnimeCollectionViewCell.reuseID,
            for: indexPath) as? AnimeCollectionViewCell else {
            return UICollectionViewCell()
        }
        cell.configure(with: items[indexPath.item])
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension ScheduleViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let detailVC = storyboard?.instantiateViewController(
            withIdentifier: "AnimeDetailVC") as? AnimeDetailViewController else { return }
        detailVC.animeItem = items[indexPath.item]
        navigationController?.pushViewController(detailVC, animated: true)
    }
}
