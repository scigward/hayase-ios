//
//  AnimeCardCollectionView.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/cards/small.svelte (component mount animation),
//           src/lib/components/ui/cards/query.svelte and recommendation.svelte (keyed card identity)
//

import UIKit

/// Gives reusable UIKit cells the same mount semantics as keyed `SmallCard` components.
/// Re-entry starts a fresh component tree; data reloads only mount media IDs that were not
/// already present in the current tree. Scrolling alone never creates a new mount cycle.
final class AnimeCardCollectionView: UICollectionView {
    private static let mountDuration: CFTimeInterval = 0.3  // small.svelte: animation 0.3s

    private var mountedMediaIDsBySection: [Int: Set<Int>] = [:]
    private var globalMountStartedAt: CFTimeInterval?
    private var sectionMountStartedAt: [Int: CFTimeInterval] = [:]
    private var wasAttachedToWindow = false
    private var phaseInspectionScheduled = false

    override func didMoveToWindow() {
        super.didMoveToWindow()

        let isAttached = window != nil
        if isAttached && !wasAttachedToWindow {
            mountedMediaIDsBySection.removeAll()
            sectionMountStartedAt.removeAll()
            globalMountStartedAt = CACurrentMediaTime()
            requestMountForVisibleCardsOnNextRunLoop()
        }
        wasAttachedToWindow = isAttached
    }

    override func reloadData() {
        globalMountStartedAt = CACurrentMediaTime()
        sectionMountStartedAt.removeAll()
        super.reloadData()
        schedulePhaseInspection()
    }

    override func reloadSections(_ sections: IndexSet) {
        let now = CACurrentMediaTime()
        for section in sections {
            sectionMountStartedAt[section] = now
        }
        super.reloadSections(sections)
        schedulePhaseInspection()
    }

    override func reloadItems(at indexPaths: [IndexPath]) {
        let now = CACurrentMediaTime()
        for section in Set(indexPaths.map(\.section)) {
            sectionMountStartedAt[section] = now
        }
        super.reloadItems(at: indexPaths)
        schedulePhaseInspection()
    }

    override func insertItems(at indexPaths: [IndexPath]) {
        let now = CACurrentMediaTime()
        for section in Set(indexPaths.map(\.section)) {
            sectionMountStartedAt[section] = now
        }
        super.insertItems(at: indexPaths)
    }

    override func insertSections(_ sections: IndexSet) {
        let now = CACurrentMediaTime()
        for section in sections {
            sectionMountStartedAt[section] = now
        }
        super.insertSections(sections)
    }

    func requestMountAnimation(for cell: AnimeCollectionViewCell, mediaID: Int) {
        guard window != nil,
              let indexPath = indexPath(for: cell) else { return }

        let section = indexPath.section
        var mounted = mountedMediaIDsBySection[section] ?? []
        guard !mounted.contains(mediaID) else { return }
        mounted.insert(mediaID)
        mountedMediaIDsBySection[section] = mounted

        let startedAt = sectionMountStartedAt[section] ?? globalMountStartedAt
        guard let startedAt,
              CACurrentMediaTime() - startedAt < Self.mountDuration else { return }
        cell.playInterfaceLoadInAnimation(startedAt: startedAt)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        inspectVisibleContentPhases()
    }

    private func schedulePhaseInspection() {
        guard !phaseInspectionScheduled else { return }
        phaseInspectionScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.phaseInspectionScheduled = false
            self.inspectVisibleContentPhases()
        }
    }

    private func inspectVisibleContentPhases() {
        let visibleIndexPaths = indexPathsForVisibleItems
        guard !visibleIndexPaths.isEmpty else { return }

        let visibleSections = Set(visibleIndexPaths.map(\.section))
        for section in visibleSections {
            let cells = visibleIndexPaths
                .filter { $0.section == section }
                .compactMap { cellForItem(at: $0) }
            guard !cells.isEmpty else { continue }

            // Skeleton/error/empty branches destroy SmallCard components on the web.
            // Clear only that section so the same media IDs mount again when cards return.
            if !cells.contains(where: { $0 is AnimeCollectionViewCell }) {
                mountedMediaIDsBySection[section] = nil
            }
        }
    }

    private func requestMountForVisibleCardsOnNextRunLoop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for case let cell as AnimeCollectionViewCell in self.visibleCells {
                cell.requestInterfaceMountAnimation()
            }
        }
    }
}
