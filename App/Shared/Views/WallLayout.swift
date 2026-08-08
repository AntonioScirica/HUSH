import Foundation

/// Come i progetti si dispongono sulla parete di cassetti.
///
/// Sta qui, e non dentro una vista, perché la parete la disegnano in due: la
/// home e lo sfondo della porta del caveau. Se ognuna calcolasse l'ordine per
/// conto suo, allo sblocco i cassetti salterebbero di posto nel passaggio da
/// una all'altra.
enum WallLayout {
    /// Molto più grande di quel che la camera inquadra: coi margini che
    /// strabordano e la parallasse sembra continuare all'infinito.
    static let cols = 13
    static let rows = 9
    static let visibleCols = 5
    static let visibleRows = 5

    static var count: Int { cols * rows }
    static var centerIndex: Int { (rows / 2) * cols + cols / 2 }

    /// Celle ordinate per distanza dal centro (il centro per primo): è lì che
    /// finiscono i progetti, in ordine di creazione. Ordine fisso, non dipende
    /// da quale cassetto è aperto, così aprirne uno non sposta gli altri.
    static var spiralOrder: [Int] {
        let cRow = rows / 2, cCol = cols / 2
        let rest = (0..<count)
            .filter { $0 != centerIndex }
            .sorted {
                let d0 = pow(Double($0 / cols - cRow), 2) + pow(Double($0 % cols - cCol), 2)
                let d1 = pow(Double($1 / cols - cRow), 2) + pow(Double($1 % cols - cCol), 2)
                return d0 < d1
            }
        return [centerIndex] + rest
    }

    /// Cella → progetto che la occupa, in ordine di creazione.
    static func projectAtCell(_ projects: [VaultFileManager.Project]) -> [Int: VaultFileManager.Project] {
        let order = spiralOrder
        var map: [Int: VaultFileManager.Project] = [:]
        for (i, p) in projects.enumerated() where i < order.count {
            map[order[i]] = p
        }
        return map
    }

    static func cellIndex(of project: VaultFileManager.Project,
                          in projects: [VaultFileManager.Project]) -> Int? {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return nil }
        let order = spiralOrder
        return i < order.count ? order[i] : nil
    }

    static func labels(_ projects: [VaultFileManager.Project]) -> [String?] {
        let map = projectAtCell(projects)
        return (0..<count).map { map[$0]?.name }
    }

    static func icons(_ projects: [VaultFileManager.Project]) -> [String?] {
        let map = projectAtCell(projects)
        return (0..<count).map { map[$0]?.icon }
    }

    static func noteColors(_ projects: [VaultFileManager.Project]) -> [String?] {
        let map = projectAtCell(projects)
        return (0..<count).map { map[$0]?.noteColor }
    }
}
