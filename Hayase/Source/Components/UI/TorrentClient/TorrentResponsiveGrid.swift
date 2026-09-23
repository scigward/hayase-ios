// Mirrors: ui/torrentclient/overview.svelte responsive CSS grids.
import UIKit

final class TorrentResponsiveGrid: UIStackView {
    private let cells: [UIView]
    private let gap: CGFloat
    private var columns = 0

    init(cells: [UIView], gap: CGFloat) {
        self.cells = cells
        self.gap = gap
        super.init(frame: .zero)
        axis = .vertical
        spacing = gap
        setColumns(1)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setColumns(_ count: Int) {
        guard count > 0, count != columns else { return }
        columns = count
        cells.forEach { $0.removeFromSuperview() }
        arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
        for start in stride(from: 0, to: cells.count, by: count) {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = gap
            for index in start..<(start + count) {
                row.addArrangedSubview(index < cells.count ? cells[index] : UIView())
            }
            addArrangedSubview(row)
        }
    }
}
