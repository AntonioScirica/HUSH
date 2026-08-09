import SwiftUI
import SceneKit
import AppKit

/// Parete di cassetti in 3D vero (SceneKit) con look line-art "hidden line":
/// ogni volume è un box color carta (shading piatto, nessuna luce) più la
/// geometria dei suoi 12 spigoli renderizzata come linee nere con depth test
/// — le linee coperte da altri volumi spariscono, come in un disegno CAD.
///
/// Il click sul cassetto centrale NON cambia inquadratura: il cassetto scorre
/// davvero in avanti lungo Z e la camera fa una dolly-in verso di lui nella
/// stessa transazione animata — un unico movimento 3D continuo, reversibile.
struct DrawerWall3D: NSViewRepresentable {
    let cols: Int
    let rows: Int
    /// Quante celle inquadra la camera (il resto della parete straborda dai
    /// bordi: con la parallasse sembra continuare all'infinito).
    let visibleCols: Int
    let visibleRows: Int
    let centerIndex: Int
    /// Etichetta targhetta per ogni cella (nil = cassetto anonimo).
    let labels: [String?]
    /// Icona (SF Symbol) per ogni cella: post-it in alto a destra.
    let icons: [String?]
    /// Colore del post-it (esadecimale) per ogni cella.
    let noteColors: [String?]
    /// Nomi delle cartelle per ogni cella — ogni progetto le sue, un
    /// cassetto nuovo parte vuoto invece di ereditare quelle di un altro.
    let entriesByCell: [[String]]
    /// Cella attualmente aperta (nil = tutte chiuse). Il cassetto si apre
    /// nella SUA posizione in griglia — non si sposta mai al centro.
    @Binding var openCell: Int?
    /// Cartella selezionata (indice nel cassetto, 1 = prima voce). Quando è
    /// settata, la cartella si estrae e si porta al centro dello schermo.
    @Binding var selectedFolder: Int?
    /// Cartella appena creata: si alza nel nastro come se ci fossi arrivato
    /// scrollando, ma senza estrarsi al centro (niente card).
    @Binding var revealFolder: Int?
    /// Altezza del corpo della cartella estratta: la decide chi conosce i
    /// dati da mostrarci dentro (ProjectsHomeView).
    let folderBodyHeight: CGFloat
    /// Rettangolo (coordinate SwiftUI) del corpo della cartella estratta,
    /// proiettato dalla scena: l'overlay dei dati si aggancia qui.
    @Binding var folderRect: CGRect?
    /// Modalità creazione progetto: cella verso cui avvicinarsi.
    @Binding var creatingCell: Int?
    /// Rettangolo proiettato della targhetta della cella in creazione:
    /// lì sopra si scrive il nome del nuovo progetto.
    @Binding var plateRect: CGRect?
    /// Zoom ravvicinato sul post-it (per scegliere icona e colore).
    @Binding var focusNote: Bool
    /// Rettangolo proiettato del post-it, per ancorarci i controlli.
    @Binding var noteRect: CGRect?
    /// Parallasse col mouse. Va spenta dove la parete fa solo da sfondo (la
    /// porta del caveau): la camera resterebbe spostata e allo sblocco, con
    /// la vista nuova che parte da zero, si vedrebbe un salto.
    var parallax = true
    /// Bozza durante creazione/modifica: nome, icona e colore applicati
    /// direttamente sulla scena (niente rebuild, niente overlay volante).
    let draftLabel: String
    let draftIcon: String?
    let draftNoteColor: String?
    /// Click sulla cartella "+" (la prima): crea una nuova password.
    let onTapNewEntry: () -> Void

    // Dimensioni di una cella e della scena
    private static let cellW: CGFloat = 1.8
    private static let cellH: CGFloat = 1.1
    private static let cabinetDepth: CGFloat = 1.5
    private static let pullDistance: CGFloat = 1.35

    // Cartelle: corpo a riposo, linguetta (altezza e sbieco) fissi
    static let folderBaseBodyH: CGFloat = 0.58
    static let folderTabH: CGFloat = 0.12
    static let folderTabSlant: CGFloat = 0.07
    /// Misura minima da estratta: dentro ci sta una scheda, quindi parte
    /// già grande. A riposo nel cassetto resta invece alta `folderBaseBodyH`.
    static let folderExtractedMinH: CGFloat = 0.95
    /// Oltre questa altezza il corpo non cresce più: la scheda dentro scrolla.
    static let folderMaxBodyH: CGFloat = 1.45

    // Palette (NSColor, allineata a Theme)
    private static let paper = NSColor(red: 0.925, green: 0.914, blue: 0.880, alpha: 1)
    private static let ink = NSColor(red: 0.135, green: 0.135, blue: 0.125, alpha: 1)
    /// Contorni line-art: un filo più scuri dell'inchiostro dei testi, così
    /// il tratto stacca meglio sulla carta.
    private static let edgeInk = NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
    /// Telaio fra un cassetto e l'altro: stessa carta, appena più scura.
    static let frame = NSColor(red: 0.885, green: 0.874, blue: 0.840, alpha: 1)
    /// Colore di default del post-it, se non se ne sceglie uno.
    static let yellowNote = NSColor(red: 0.98, green: 0.85, blue: 0.36, alpha: 1)

    func makeNSView(context: Context) -> SCNView {
        let view = ParallaxSCNView()
        view.backgroundColor = Self.paper
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        context.coordinator.parent = self
        context.coordinator.buildScene(in: view)
        view.onMouseMove = { [weak coordinator = context.coordinator] offset, point in
            coordinator?.mouseMoved(offset, at: point)
        }
        view.onScroll = { [weak coordinator = context.coordinator] deltaY in
            coordinator?.scrolled(deltaY)
        }
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        view.addGestureRecognizer(click)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // Contenuto cambiato (progetti/voci) → ricostruisci la scena
        // Le voci NON stanno nella firma: cambiandone una si ricostruiva
        // l'intera parete, centodiciassette celle di geometria, e si vedeva.
        // Le cartelle di un cassetto si rifanno da sole, più sotto.
        let signature = labels.map { $0 ?? "·" }.joined(separator: "|")
            + "§" + icons.map { $0 ?? "·" }.joined(separator: "|")
            + "§" + noteColors.map { $0 ?? "·" }.joined(separator: "|")
        if coordinator.signature != signature {
            coordinator.buildScene(in: view)
        }

        // Cartelle cambiate in una cella (voce aggiunta, vault appena
        // caricato): si rifanno solo quelle, non tutta la parete.
        for (i, voci) in entriesByCell.enumerated() where labels[i] != nil {
            let firma = voci.joined(separator: ",")
            if coordinator.folderSignatures[i] != firma {
                coordinator.rebuildFolders(cell: i, entries: voci)
            }
        }

        // Stato open richiesto dall'esterno (es. bottone "chiudi", search)
        if openCell != coordinator.openCellIdx {
            if let cell = openCell {
                coordinator.openDrawer(cell)
            } else {
                coordinator.closeDrawer()
            }
        }

        // Selezione cartella richiesta dall'esterno (search o click)
        if selectedFolder != coordinator.selectedFolderIdx {
            if let target = selectedFolder {
                coordinator.selectFolder(target)
            } else {
                coordinator.deselectFolder()
            }
        }

        // Cartella appena creata: solo l'alzata nel nastro, niente estrazione
        if let target = revealFolder, target != coordinator.revealedFolderIdx {
            coordinator.riseToFolder(target)
        }

        // Altezza del corpo cambiata a cartella già fuori (es. dati modificati)
        if let idx = coordinator.selectedFolderIdx, coordinator.folderExtracted,
           abs(coordinator.folderBodyH - folderBodyHeight) > 0.001 {
            coordinator.setFolderBodyHeight(idx, h: folderBodyHeight)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.3
            coordinator.folderPivots[idx].position.y = Coordinator.extractedBaseY(bodyH: folderBodyHeight)
            SCNTransaction.commit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [coordinator] in
                coordinator.reportFolderRect(idx)
            }
        }

        // Modalità creazione progetto (avvicinati alla cella / torna indietro)
        if creatingCell != coordinator.creationCellIdx {
            if let cell = creatingCell {
                coordinator.enterCreation(cell)
            } else {
                coordinator.exitCreation()
            }
        }

        // Zoom sul post-it
        if focusNote != coordinator.noteFocused {
            coordinator.setNoteFocus(focusNote)
        }

        // Bozza (nome/icona/colore) applicata in place, senza rifare la scena
        coordinator.updateDraft(label: draftLabel, icon: draftIcon, color: draftNoteColor)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Cartelle di un singolo cassetto, con i materiali per l'hover — una
    /// per cella, così più cassetti possono avere ognuno le proprie.
    struct DrawerFolders {
        var pivots: [SCNNode] = []
        var fillMats: [Int: [SCNMaterial]] = [:]
        var textMats: [Int: [SCNMaterial]] = [:]
        var baseY: CGFloat = 0
        var width: CGFloat = 1.48
        var maxFocus: CGFloat = 0
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var parent: DrawerWall3D?
        weak var view: SCNView?
        var signature = ""
        /// Cella con il cassetto aperto — nil = tutte chiuse.
        var openCellIdx: Int?

        /// Nodo cassetto per ogni cella con un progetto (ognuno apribile).
        var cellDrawerNodes: [Int: SCNNode] = [:]
        /// Cartelle di ogni cassetto, tenute da parte finché non si apre
        /// (quando apre, il loro contenuto viene copiato nei campi "attivi"
        /// folderPivots/folderFillMats/… usati da scroll/hover/selezione).
        var cellFolders: [Int: DrawerFolders] = [:]

        var cameraNode: SCNNode?

        // Pose camera per lo stato chiuso (vista d'insieme, sempre centrata)
        var closedCameraPos = SCNVector3(0, 0.4, 7.2)
        var closedCameraPitch: CGFloat = -0.03
        // Offset della camera aperta RISPETTO al cassetto che si sta aprendo
        // (più in alto e più angolata verso il basso, per guardare dentro) —
        // si somma alla posizione della cella così il cassetto resta al suo posto.
        static let openOffset = SCNVector3(0, 2.6, 3.1)
        var openCameraPitch: CGFloat = -0.72

        // Parallasse dal mouse (coordinate normalizzate -1…1)
        var mouseOffset = CGPoint.zero
        var isAnimatingDrawer = false
        /// Vero mentre la camera torna dalla modifica alla vista d'insieme.
        var isReturningFromCreation = false

        // Scroll = nastro + Rolodex: tutta la fila avanza verso il punto di
        // lettura. La cartella corrente si alza; quelle già passate si
        // impilano strette davanti a lei; quelle dietro le si avvicinano
        // (passo fisso ravvicinato) così le vedi arrivare. Mai fuori dal cassetto.
        var folderPivots: [SCNNode] = []
        var folderBaseY: CGFloat = 0
        var folderFocus: CGFloat = 0
        var maxFolderFocus: CGFloat = 0

        /// Punto di lettura (z della cartella corrente) e passi del nastro.
        static let readZ: CGFloat = -0.35
        static let aheadSpacing: CGFloat = 0.16   // tra le cartelle ancora da sfogliare
        static let passedSpacing: CGFloat = 0.07  // impilate davanti, strette

        static func conveyorZ(index: Int, focus: CGFloat) -> CGFloat {
            // la "+" resta sempre attaccata al fronte del cassetto, non
            // partecipa mai allo scroll: si vede solo la sua linguetta,
            // senza il salto quando si torna indietro sfogliando
            if index == 0 { return readZ + 0.3 }
            let d = CGFloat(index) - focus
            if d >= 0 {
                return readZ - d * aheadSpacing
            } else {
                return readZ + min(0.26, -d * passedSpacing)   // clamp: restano dentro
            }
        }

        var scrollUnderflow: CGFloat = 0

        func scrolled(_ deltaY: CGFloat) {
            // a cassetti chiusi la rotella non sfoglia niente: allontana o
            // avvicina la camera, per arrivare ai cassetti più lontani
            if openCellIdx == nil {
                guard creationCellIdx == nil, !isAnimatingDrawer else { return }
                zoomed(deltaY)
                return
            }
            guard !isAnimatingDrawer, !folderPivots.isEmpty, selectedFolderIdx == nil else { return }
            let proposed = folderFocus - deltaY * 0.006
            if proposed < 0 {
                // già alla prima: continuare a scrollare indietro chiude il cassetto
                scrollUnderflow += -proposed - folderFocus
                folderFocus = 0
                if scrollUnderflow > 0.25 {
                    scrollUnderflow = 0
                    closeDrawer()
                    DispatchQueue.main.async { [weak self] in self?.parent?.openCell = nil }
                    return
                }
            } else {
                scrollUnderflow = 0
                folderFocus = min(maxFolderFocus, proposed)
            }
            applyFolderScroll()
        }

        // MARK: - Creazione progetto: dolly sulla cella libera

        var creationCellIdx: Int?
        var cellNodes: [SCNNode] = []

        func enterCreation(_ idx: Int) {
            guard idx < cellNodes.count, let cameraNode else { return }
            creationCellIdx = idx
            let cell = cellNodes[idx].position
            moveCamera(to: SCNVector3(cell.x, cell.y + 0.1, 2.4), pitch: -0.04)
        }

        func exitCreation() {
            creationCellIdx = nil
            DispatchQueue.main.async { [weak self] in
                if self?.parent?.plateRect != nil { self?.parent?.plateRect = nil }
            }
            applyCameraPose(animated: true)
        }

        /// Sposta la camera con l'animazione di SceneKit (curva ease-in-out,
        /// fluida) e riallinea gli overlay a fine corsa.
        /// Cresce a ogni movimento: le completion di movimenti superati non
        /// devono pubblicare i rettangoli (arriverebbero a camera ancora in
        /// viaggio, con overlay che compaiono in anticipo e nel posto sbagliato).
        var moveToken = 0

        func moveCamera(to pos: SCNVector3, pitch: CGFloat, yaw: CGFloat = 0,
                        duration: CFTimeInterval = 0.55,
                        timing: CAMediaTimingFunctionName = .easeInEaseOut) {
            guard let cameraNode else { return }
            moveToken += 1
            let token = moveToken
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: timing)
            SCNTransaction.completionBlock = { [weak self] in
                guard let self, self.moveToken == token else { return }
                self.syncOverlays()
            }
            cameraNode.position = pos
            cameraNode.eulerAngles.x = pitch
            cameraNode.eulerAngles.y = yaw
            SCNTransaction.commit()
        }

        /// Nodi "bozza" della cella in creazione/modifica: nome sulla targhetta
        /// e post-it. Vengono applicati IN PLACE, senza mai ricostruire la
        /// scena: il rebuild a metà animazione era la causa di tutti gli
        /// scatti (cassetto chiuso di botto, cartelle sparite, zoom sballato).
        var draftLabelNode: SCNNode?
        var draftCaretNode: SCNNode?
        var draftLabelText: String?
        var draftNoteNode: SCNNode?
        var draftNoteKey: String?
        var draftCell: Int?

        func updateDraft(label: String, icon: String?, color: String?) {
            // uscita dalla creazione: via le bozze, riappaiono gli originali
            guard let cell = creationCellIdx,
                  let drawer = cellNodes[safe: cell]?.childNode(withName: "drawer", recursively: false) else {
                if let old = draftCell,
                   let drawer = cellNodes[safe: old]?.childNode(withName: "drawer", recursively: false) {
                    drawer.childNode(withName: "plateLabel", recursively: false)?.isHidden = false
                    drawer.childNode(withName: "postit", recursively: false)?.isHidden = false
                }
                draftLabelNode?.removeFromParentNode(); draftLabelNode = nil; draftLabelText = nil
                draftNoteNode?.removeFromParentNode(); draftNoteNode = nil; draftNoteKey = nil
                draftCaretNode?.removeFromParentNode(); draftCaretNode = nil
                draftCell = nil
                return
            }
            draftCell = cell

            // gli originali restano nascosti finché si lavora sulla bozza
            drawer.childNode(withName: "plateLabel", recursively: false)?.isHidden = true
            drawer.childNode(withName: "postit", recursively: false)?.isHidden = true

            if label != draftLabelText {
                draftLabelText = label
                draftLabelNode?.removeFromParentNode()
                draftLabelNode = nil
                let h = DrawerWall3D.cellH - 0.14
                var caretX: CGFloat = 0   // testo vuoto → cursore al centro della targhetta
                if !label.isEmpty {
                    let node = Self.textNode(label.lowercased(), maxWidth: 0.54, maxHeight: 0.16, maxScale: 0.1)
                    node.position = SCNVector3(node.position.x, h * 0.18 + node.position.y, 0.085)
                    drawer.addChildNode(node)
                    draftLabelNode = node
                    // il nodo torna già centrato: il bordo destro è a metà
                    // larghezza dalla sua origine (position.x è l'offset di centraggio)
                    caretX = -node.position.x
                }

                // cursore lampeggiante, sempre subito dopo l'ultimo carattere
                draftCaretNode?.removeFromParentNode()
                let caretHeight = h * 0.1
                let caret = SCNPlane(width: 0.012, height: caretHeight)
                caret.materials = [Self.flatMaterial(ink)]
                let caretNode = SCNNode(geometry: caret)
                caretNode.position = SCNVector3(caretX + 0.02, h * 0.18, 0.086)
                let blink = CABasicAnimation(keyPath: "opacity")
                blink.fromValue = 1.0
                blink.toValue = 0.0
                blink.duration = 0.55
                blink.autoreverses = true
                blink.repeatCount = .infinity
                caretNode.addAnimation(blink, forKey: "blink")
                drawer.addChildNode(caretNode)
                draftCaretNode = caretNode
            }

            let key = "\(icon ?? "·")|\(color ?? "·")"
            if key != draftNoteKey {
                draftNoteKey = key
                draftNoteNode?.removeFromParentNode()
                draftNoteNode = nil
                if let note = Self.makeNote(icon: icon, color: color, seedText: label) {
                    drawer.addChildNode(note)
                    draftNoteNode = note
                }
            }
        }

        /// Riproietta i rettangoli degli overlay sulla posa corrente.
        func syncOverlays() {
            if let cell = creationCellIdx {
                if noteFocused {
                    reportNoteRect(cell)
                } else {
                    // entrambi sempre visibili in modifica: il quadrato "+"
                    // del post-it sta accanto al campo nome, non solo quando
                    // ci si zooma sopra
                    reportPlateRect(cell)
                    reportNoteRect(cell)
                }
            }
            if let idx = selectedFolderIdx { reportFolderRect(idx) }
        }

        /// Vero se i due rettangoli differiscono abbastanza da giustificare un
        /// aggiornamento di stato SwiftUI.
        static func differs(_ a: CGRect?, _ b: CGRect) -> Bool {
            guard let a else { return true }
            return abs(a.midX - b.midX) > 0.5 || abs(a.midY - b.midY) > 0.5
                || abs(a.width - b.width) > 0.5 || abs(a.height - b.height) > 0.5
        }

        // MARK: - Zoom sul post-it

        var noteFocused = false
        /// Posizione del post-it nello spazio della cella (deve combaciare con
        /// quella usata da makeDrawer).
        static var notePosition: SCNVector3 {
            let w = DrawerWall3D.cellW - 0.14, h = DrawerWall3D.cellH - 0.14
            let side: CGFloat = 0.22
            return SCNVector3(w / 2 - side / 2 - 0.1, h * 0.26, 0.06)
        }

        func setNoteFocus(_ on: Bool) {
            noteFocused = on
            guard let idx = creationCellIdx, idx < cellNodes.count, let cameraNode else { return }
            let cell = cellNodes[idx].position
            let note = Self.notePosition
            if on {
                // niente rect vecchio in giro durante il volo verso il
                // post-it: l'interfaccia (colori, cambia icona…) comparirebbe
                // ancora nella posizione di prima e "salterebbe" a fine zoom
                DispatchQueue.main.async { [weak self] in self?.parent?.noteRect = nil }
                moveCamera(to: SCNVector3(cell.x + note.x, cell.y + note.y, 1.0), pitch: 0)
            } else {
                moveCamera(to: SCNVector3(cell.x, cell.y + 0.1, 2.4), pitch: -0.04)
                DispatchQueue.main.async { [weak self] in self?.parent?.noteRect = nil }
            }
        }

        func reportNoteRect(_ idx: Int) {
            guard let view, idx < cellNodes.count else { return }
            let node = cellNodes[idx]
            let p = Self.notePosition
            let s: CGFloat = 0.11
            let corners = [
                SCNVector3(p.x - s, p.y - s, p.z), SCNVector3(p.x + s, p.y - s, p.z),
                SCNVector3(p.x + s, p.y + s, p.z), SCNVector3(p.x - s, p.y + s, p.z)
            ].map { node.convertPosition($0, to: nil) }
            let projected = corners.map { view.projectPoint($0) }
            let xs = projected.map { CGFloat($0.x) }
            let ys = projected.map { view.bounds.height - CGFloat($0.y) }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return }
            let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            guard Self.differs(parent?.noteRect, rect) else { return }
            DispatchQueue.main.async { [weak self] in self?.parent?.noteRect = rect }
        }

        /// Proietta la targhetta (il "rettangolo alto") della cella in
        /// coordinate SwiftUI, per scriverci sopra il nome.
        func reportPlateRect(_ idx: Int) {
            guard let view, creationCellIdx == idx, idx < cellNodes.count else { return }
            let node = cellNodes[idx]
            let h = DrawerWall3D.cellH - 0.14
            let plateY = h * 0.18
            let corners = [
                SCNVector3(-0.31, plateY - 0.12, 0.075), SCNVector3(0.31, plateY - 0.12, 0.075),
                SCNVector3(0.31, plateY + 0.12, 0.075), SCNVector3(-0.31, plateY + 0.12, 0.075)
            ].map { node.convertPosition($0, to: nil) }
            let projected = corners.map { view.projectPoint($0) }
            let xs = projected.map { CGFloat($0.x) }
            let ys = projected.map { view.bounds.height - CGFloat($0.y) }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return }
            let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            guard Self.differs(parent?.plateRect, rect) else { return }
            DispatchQueue.main.async { [weak self] in self?.parent?.plateRect = rect }
        }

        // MARK: - Selezione ed estrazione cartella

        var selectedFolderIdx: Int?
        var revealedFolderIdx: Int?
        var folderWidth: CGFloat = 1.48
        /// L'estrazione è finita: prima di allora il rettangolo NON va
        /// pubblicato, o la scheda compare mentre la cartella è ancora in
        /// viaggio (ci arrivava via syncOverlays della moveCamera iniziale).
        var folderExtracted = false
        /// Altezza corrente del corpo della cartella estratta (cresce con i
        /// dati dentro).
        var folderBodyH: CGFloat = DrawerWall3D.folderBaseBodyH
        var folderBodyHByIdx: [Int: CGFloat] = [:]
        /// Velo scuro dietro alla cartella estratta.
        var dimNode: SCNNode?

        /// Porta la cartella estratta sopra a tutto: senza questo il fronte
        /// del cassetto (che le sta davanti) le taglia mezza scheda.
        func setFolderOnTop(_ idx: Int, _ on: Bool) {
            guard idx < folderPivots.count else { return }
            let node = folderPivots[idx]
            func apply(_ n: SCNNode, order: Int) {
                n.renderingOrder = on ? order : 0
                n.geometry?.materials.forEach { $0.readsFromDepthBuffer = !on }
            }
            if let body = node.childNode(withName: "folderBody", recursively: false) {
                apply(body, order: 1000)
                body.childNodes.forEach { apply($0, order: 1001) }
            }
            if let text = node.childNode(withName: "tabText", recursively: false) {
                apply(text, order: 1002)
            }
        }

        func setDim(_ on: Bool) {
            guard let dim = dimNode else { return }
            if on { dim.isHidden = false }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = on ? 0.45 : 0.3
            SCNTransaction.completionBlock = { if !on { dim.isHidden = true } }
            dim.opacity = on ? 0.32 : 0
            SCNTransaction.commit()
        }

        /// Sfoglia il nastro fino alla cartella indicata (si alza come le
        /// altre quando ci passi sopra scrollando), ma non la estrae.
        func riseToFolder(_ idx: Int) {
            revealedFolderIdx = idx
            guard idx < folderPivots.count else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.45
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            folderFocus = CGFloat(idx)
            applyFolderScroll()
            SCNTransaction.commit()
        }

        /// Sfoglia fino alla cartella scelta, poi la estrae davvero dal
        /// cassetto: sale e si porta davanti alla camera, ruotata verso di lei
        /// (a distanza giusta: ~metà altezza schermo, non addosso all'obiettivo).
        func selectFolder(_ idx: Int) {
            guard idx > 0, idx < folderPivots.count else { return }
            // se un'altra cartella era estratta, rimettila a posto
            if let old = selectedFolderIdx, old != idx, old < folderPivots.count {
                let n = folderPivots[old]
                n.opacity = 1; n.eulerAngles.x = 0; n.position.x = 0
            }
            selectedFolderIdx = idx
            folderExtracted = false

            // niente hover sulla cartella estratta (resterebbe nera)
            clearHover()

            // camera inchiodata alla posa base: da qui in poi non si muove più
            if let pos = openCameraPos() {
                moveCamera(to: pos, pitch: openCameraPitch)
            }

            let delay = isAnimatingDrawer ? 0.7 : 0.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.selectedFolderIdx == idx else { return }
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.45
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.folderFocus = CGFloat(idx)
                self.applyFolderScroll()
                SCNTransaction.commit()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { [weak self] in
                    guard let self, self.selectedFolderIdx == idx else { return }
                    let node = self.folderPivots[idx]
                    // il corpo cresce mentre esce, così arriva già della
                    // misura giusta per i dati che deve contenere
                    let bodyH = self.parent?.folderBodyHeight ?? DrawerWall3D.folderBaseBodyH
                    // da qui in poi la cartella sta sopra a tutto, col velo dietro
                    self.setFolderOnTop(idx, true)
                    self.setDim(true)
                    // fuori dalla transazione animata: è un cambio istantaneo
                    self.setFolderBodyHeight(idx, h: bodyH)
                    SCNTransaction.begin()
                    SCNTransaction.animationDuration = 0.55
                    SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    // davanti alla camera, centrata sullo schermo (origine del
                    // nodo = base della cartella, quindi mezzo corpo più in basso)
                    node.position = SCNVector3(0, Self.extractedBaseY(bodyH: bodyH), 0.03)
                    node.eulerAngles.x = self.openCameraPitch
                    SCNTransaction.commit()

                    // a fine corsa si centra per davvero e poi si proietta il
                    // rettangolo del corpo per l'overlay SwiftUI
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                        guard let self, self.selectedFolderIdx == idx else { return }
                        self.centerExtractedFolder(idx)
                        self.folderExtracted = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
                            self?.reportFolderRect(idx)
                        }
                    }
                }
            }
        }

        /// Mette la cartella estratta esattamente al centro dello schermo.
        ///
        /// La posizione era un numero trovato a occhio, tarato su una sola
        /// misura di cartella e su una sola forma di finestra: appena il corpo
        /// cresce coi dati, o cambia la posa della camera, il centro non è più
        /// il centro. Qui invece si guarda dove il corpo finisce davvero sullo
        /// schermo e lo si sposta di quel tanto che serve.
        func centerExtractedFolder(_ idx: Int) {
            guard let view, idx < folderPivots.count, view.bounds.height > 0 else { return }
            let node = folderPivots[idx]

            // centro del CORPO, non dell'origine del nodo (che sta alla base)
            let bodyCenterLocal = SCNVector3(0, folderBodyH / 2, 0)
            let worldCenter = node.convertPosition(bodyCenterLocal, to: nil)
            let projected = view.projectPoint(worldCenter)

            // dove vorremmo che fosse: il centro della vista, stessa profondità
            let target = SCNVector3(view.bounds.midX, view.bounds.midY, CGFloat(projected.z))
            let desiredWorld = view.unprojectPoint(target)

            // lo scarto in coordinate del padre, così si somma alla posizione
            let parent = node.parent
            let from = parent?.convertPosition(worldCenter, from: nil) ?? worldCenter
            let to = parent?.convertPosition(desiredWorld, from: nil) ?? desiredWorld

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.22
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            node.position = SCNVector3(node.position.x + (to.x - from.x),
                                       node.position.y + (to.y - from.y),
                                       node.position.z)
            SCNTransaction.commit()
        }

        /// Proietta i 4 angoli del corpo della cartella estratta in coordinate
        /// vista (origine in basso a sinistra) e li converte in coordinate
        /// SwiftUI (origine in alto a sinistra).
        func reportFolderRect(_ idx: Int) {
            guard let view, selectedFolderIdx == idx, folderExtracted, idx < folderPivots.count else { return }
            let node = folderPivots[idx]
            let w = folderWidth, h = folderBodyH
            let corners = [
                SCNVector3(-w / 2, 0, 0), SCNVector3(w / 2, 0, 0),
                SCNVector3(w / 2, h, 0), SCNVector3(-w / 2, h, 0)
            ].map { node.convertPosition($0, to: nil) }
            let projected = corners.map { view.projectPoint($0) }
            let xs = projected.map { CGFloat($0.x) }
            let ys = projected.map { view.bounds.height - CGFloat($0.y) }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return }
            let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            guard Self.differs(parent?.folderRect, rect) else { return }
            DispatchQueue.main.async { [weak self] in self?.parent?.folderRect = rect }
        }

        func deselectFolder() {
            guard let idx = selectedFolderIdx else { return }
            selectedFolderIdx = nil
            folderExtracted = false
            setFolderOnTop(idx, false)
            setDim(false)
            // misura base subito, fuori dall'animazione (vedi setFolderBodyHeight)
            setFolderBodyHeight(idx, h: DrawerWall3D.folderBaseBodyH)
            DispatchQueue.main.async { [weak self] in self?.parent?.folderRect = nil }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if idx < folderPivots.count {
                folderPivots[idx].opacity = 1
                folderPivots[idx].eulerAngles.x = 0
                folderPivots[idx].position.x = 0
            }
            // il nastro torna all'inizio: chiudendo una cartella si vuole
            // rivedere il cassetto intero, non ripartire da dove si era
            // arrivati sfogliando
            folderFocus = 0
            scrollUnderflow = 0
            revealedFolderIdx = nil
            applyFolderScroll()
            SCNTransaction.commit()
        }

        func applyFolderScroll() {
            for (i, pivot) in folderPivots.enumerated() {
                pivot.position.z = Self.conveyorZ(index: i, focus: folderFocus)
                if i == 0 {
                    // sempre alzata quanto basta per leggere il "+", ferma
                    pivot.position.y = folderBaseY + 0.30
                } else {
                    let near = max(0, 1 - abs(folderFocus - CGFloat(i)))   // 1 = cartella corrente
                    pivot.position.y = folderBaseY + near * 0.34
                }
            }
        }

        /// Distanza camera per riempire la finestra (overscan): la parete
        /// straborda sempre dai bordi, mai margini di carta vuota.
        func updateClosedPose() {
            guard let view, view.bounds.height > 0, let parent else { return }
            let wallW = CGFloat(parent.visibleCols) * DrawerWall3D.cellW
            let wallH = CGFloat(parent.visibleRows) * DrawerWall3D.cellH
            let aspect = view.bounds.width / view.bounds.height
            let tanV = tan(CGFloat(40) * .pi / 360)   // fov verticale 40°
            let tanH = tanV * aspect
            let dist = min((wallH / 2) / tanV, (wallW / 2) / tanH) * 0.92 * zoomFactor
            closedCameraPos = SCNVector3(0, 0.4, dist)
        }

        /// Quanto è lontana la camera dalla parete rispetto alla distanza di
        /// riposo. Si regola con la rotella, e si può solo indietreggiare:
        /// la posa di partenza è già la più ravvicinata, avvicinarsi ancora
        /// taglierebbe i cassetti ai bordi invece di mostrarne di più.
        var zoomFactor: CGFloat = 1
        static let minZoom: CGFloat = 1
        static let maxZoom: CGFloat = 1.9

        func zoomed(_ deltaY: CGFloat) {
            let proposed = zoomFactor - deltaY * 0.004
            let clamped = min(Self.maxZoom, max(Self.minZoom, proposed))
            guard abs(clamped - zoomFactor) > 0.0001 else { return }
            zoomFactor = clamped
            updateClosedPose()
            // curva breve: la rotella manda molti eventi di fila, con una
            // lunga ognuno ripartirebbe da fermo e sembrerebbe a scatti
            applyCameraPose(animated: true, duration: 0.12)
        }

        func mouseMoved(_ offset: CGPoint, at point: CGPoint) {
            // sfondo della porta: niente parallasse. La camera resterebbe
            // spostata dal mouse e allo sblocco, con la vista nuova che parte
            // da zero, la parete farebbe un salto.
            guard parent?.parallax ?? true else { return }
            mouseOffset = offset
            // durante l'uscita dalla modifica la camera sta già animando: la
            // parallasse la strattonerebbe a metà corsa
            guard !isAnimatingDrawer, !isReturningFromCreation else { return }
            updateClosedPose()
            applyCameraPose(animated: true)
            if openCellIdx != nil { updateHover(at: point) }
        }

        // MARK: - Hover cartelle (nera con scritta bianca)

        var folderFillMats: [Int: [SCNMaterial]] = [:]
        var folderTextMats: [Int: [SCNMaterial]] = [:]
        var hoveredFolder: Int?

        /// Indice della cartella a cui appartiene il nodo colpito (nil se non
        /// è una cartella): risale la catena dei padri fino al nodo "folder_N".
        static func folderIndex(of node: SCNNode?) -> Int? {
            var n = node
            while let cur = n {
                if let name = cur.name, name.hasPrefix("folder_") {
                    return Int(name.dropFirst(7))
                }
                n = cur.parent
            }
            return nil
        }

        /// Spegne l'evidenziazione della cartella sotto al mouse.
        ///
        /// L'hover riempie la cartella di nero: se il cassetto si chiude
        /// mentre una è evidenziata (per esempio premendo "modifica"), quella
        /// resta nera e riaffiora come un rettangolo scuro sulla parete.
        func clearHover() {
            guard let h = hoveredFolder else { return }
            folderFillMats[h]?.forEach { $0.diffuse.contents = DrawerWall3D.paper }
            folderTextMats[h]?.forEach { $0.diffuse.contents = DrawerWall3D.ink }
            hoveredFolder = nil
        }

        func updateHover(at point: CGPoint) {
            guard let view, selectedFolderIdx == nil else { return }
            let hits = view.hitTest(point, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])
            // come per il click: conta solo ciò che sta davvero davanti
            let found = Self.folderIndex(of: hits.first?.node)
            guard found != hoveredFolder else { return }
            if let old = hoveredFolder {
                folderFillMats[old]?.forEach { $0.diffuse.contents = DrawerWall3D.paper }
                folderTextMats[old]?.forEach { $0.diffuse.contents = DrawerWall3D.ink }
            }
            if let new = found {
                folderFillMats[new]?.forEach { $0.diffuse.contents = DrawerWall3D.ink }
                folderTextMats[new]?.forEach { $0.diffuse.contents = DrawerWall3D.paper }
            }
            hoveredFolder = found
        }

        /// Posa = base dello stato corrente + spostamento parallasse.
        /// Con una cartella estratta la visuale è CONGELATA (overlay agganciato).
        /// Posizione camera per lo stato "aperto": offset fisso sommato alla
        /// posizione della cella aperta — il cassetto resta dov'è, la camera
        /// gli si avvicina lì, non lo riporta mai al centro della parete.
        func openCameraPos() -> SCNVector3? {
            guard let idx = openCellIdx, idx < cellNodes.count else { return nil }
            let cell = cellNodes[idx].position
            return SCNVector3(cell.x + Self.openOffset.x, cell.y + Self.openOffset.y, cell.z + Self.openOffset.z)
        }

        func applyCameraPose(animated: Bool, duration: CFTimeInterval = 0.25) {
            guard let cameraNode, selectedFolderIdx == nil, creationCellIdx == nil else { return }
            let isOpen = openCellIdx != nil
            let base = isOpen ? (openCameraPos() ?? closedCameraPos) : closedCameraPos
            let basePitch = isOpen ? openCameraPitch : closedCameraPitch
            // Aperto: visuale bloccata, solo un filo di "shake"
            let ampX: CGFloat = isOpen ? 0.07 : 1.7
            let ampY: CGFloat = isOpen ? 0.04 : 0.95

            // curva breve in easeOut: viene richiamata a ogni evento mouse,
            // con l'ease-in-out lunga ogni step ripartiva lento = scattoso
            moveCamera(
                to: SCNVector3(base.x + mouseOffset.x * ampX,
                               base.y + mouseOffset.y * ampY,
                               base.z),
                pitch: basePitch + mouseOffset.y * (isOpen ? 0.005 : 0.025),
                yaw: -mouseOffset.x * (isOpen ? 0.008 : 0.045),
                duration: animated ? duration : 0,
                timing: .easeOut
            )
        }

        @objc func handleClick(_ gr: NSClickGestureRecognizer) {
            guard let view, let parent else { return }
            // in modalità creazione, click sulla scena = annulla
            if creationCellIdx != nil {
                DispatchQueue.main.async { parent.creatingCell = nil }
                exitCreation()
                return
            }
            let point = gr.location(in: view)
            let hits = view.hitTest(point, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])
            var tappedCell: Int?
            for hit in hits {
                var node: SCNNode? = hit.node
                while let n = node {
                    if let name = n.name, name.hasPrefix("cell_"), let idx = Int(name.dropFirst(5)) {
                        tappedCell = idx
                        break
                    }
                    node = n.parent
                }
                if tappedCell != nil { break }
            }

            if openCellIdx != nil {
                // Cartella estratta? Qualsiasi click la rimette a posto.
                if selectedFolderIdx != nil {
                    DispatchQueue.main.async { parent.selectedFolder = nil }
                    deselectFolder()
                    return
                }
                // Click su una cartella: "+" = nuova password, con nome = estraila.
                // Solo il PRIMO hit (il più vicino): così il fronte del cassetto
                // fa da schermo e non si clicca una cartella che sta dietro.
                if let idx = Self.folderIndex(of: hits.first?.node) {
                    if idx == 0 {
                        DispatchQueue.main.async { parent.onTapNewEntry() }
                    } else {
                        DispatchQueue.main.async { parent.selectedFolder = idx }
                        selectFolder(idx)
                    }
                    return
                }
                // Click su un altro cassetto con un progetto: quello aperto si
                // richiude mentre la camera si sposta sul nuovo, un solo
                // movimento — non serve passare dalla vista d'insieme.
                if let idx = tappedCell, idx != openCellIdx, parent.labels[idx] != nil {
                    closeDrawer()
                    openDrawer(idx)
                    DispatchQueue.main.async { parent.openCell = idx }
                    return
                }
                closeDrawer()
                DispatchQueue.main.async { parent.openCell = nil }
                return
            }

            guard let idx = tappedCell, parent.labels[idx] != nil else { return }
            openDrawer(idx)
            DispatchQueue.main.async { parent.openCell = idx }
        }

        /// Apre IL CASSETTO DI QUELLA CELLA, sul posto: scorre in avanti lungo
        /// Z lì dov'è, la camera gli si avvicina restando allineata alla sua
        /// posizione in griglia — nessuno spostamento al centro.
        func openDrawer(_ idx: Int) {
            guard let node = cellDrawerNodes[idx], let cameraNode else { return }
            openCellIdx = idx

            let ctx = cellFolders[idx] ?? DrawerFolders()
            folderPivots = ctx.pivots
            folderFillMats = ctx.fillMats
            folderTextMats = ctx.textMats
            folderBaseY = ctx.baseY
            folderWidth = ctx.width
            maxFolderFocus = ctx.maxFocus
            folderFocus = 0
            revealedFolderIdx = nil
            // le altezze sono per-cassetto: l'indice 3 di questo non è
            // l'indice 3 di quello di prima. Senza azzerare, le cartelle
            // ereditavano la misura di un altro progetto.
            folderBodyHByIdx = [:]
            folderBodyH = DrawerWall3D.folderBaseBodyH
            scrollUnderflow = 0
            folderPivots.forEach { $0.eulerAngles.x = 0; $0.position.x = 0; $0.opacity = 1 }
            applyFolderScroll()

            isAnimatingDrawer = true
            updateClosedPose()
            let targetCamPos = SCNVector3(
                cellNodes[idx].position.x + Self.openOffset.x,
                cellNodes[idx].position.y + Self.openOffset.y,
                cellNodes[idx].position.z + Self.openOffset.z
            )
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.65
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            SCNTransaction.completionBlock = { [weak self] in
                self?.isAnimatingDrawer = false
                self?.applyCameraPose(animated: true)
            }
            node.position.z = DrawerWall3D.pullDistance
            SCNTransaction.commit()
            moveCamera(to: targetCamPos, pitch: openCameraPitch)
        }

        func closeDrawer() {
            guard let idx = openCellIdx, let node = cellDrawerNodes[idx], let cameraNode else { return }
            // se una cartella era evidenziata resterebbe nera dentro al
            // cassetto chiuso, e si intravede sulla parete
            clearHover()
            // se una cartella era estratta/alzata, riportala giù PRIMA di
            // salvare lo stato: altrimenti al prossimo apri risulta ancora
            // estratta, con la posizione sbagliata. Animato insieme alla
            // chiusura (stessa durata): a scatto si vedeva un flash.
            // il corpo torna alla misura base subito, fuori dall'animazione:
            // dentro, la linguetta si sarebbe staccata scendendo in ritardo
            if let old = selectedFolderIdx, old < folderPivots.count {
                setFolderOnTop(old, false)
                setFolderBodyHeight(old, h: DrawerWall3D.folderBaseBodyH)
            }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.65
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if let old = selectedFolderIdx, old < folderPivots.count {
                let n = folderPivots[old]
                n.opacity = 1; n.eulerAngles.x = 0; n.position.x = 0
            }
            setDim(false)
            folderExtracted = false
            folderFocus = 0
            revealedFolderIdx = nil
            applyFolderScroll()
            SCNTransaction.commit()

            // salva lo stato (ora resettato) delle cartelle di questo cassetto
            var ctx = cellFolders[idx] ?? DrawerFolders()
            ctx.pivots = folderPivots
            cellFolders[idx] = ctx

            openCellIdx = nil
            selectedFolderIdx = nil
            DispatchQueue.main.async { [weak self] in
                if self?.parent?.selectedFolder != nil { self?.parent?.selectedFolder = nil }
                if self?.parent?.folderRect != nil { self?.parent?.folderRect = nil }
            }

            isAnimatingDrawer = true
            updateClosedPose()
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.65
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            SCNTransaction.completionBlock = { [weak self] in
                self?.isAnimatingDrawer = false
                self?.applyCameraPose(animated: true)
            }
            node.position.z = 0
            SCNTransaction.commit()
            // se subito dopo si entra in modifica (bottone "modifica" sul
            // cassetto aperto), la camera non torna alla parete: ci pensa
            // enterCreation a portarla sul fronte con un movimento solo
            if parent?.creatingCell == nil {
                // Diretti alla posa chiusa COMPRESA la parallasse del mouse.
                // Prima si tornava alla posa senza parallasse e subito dopo
                // un secondo movimento la correggeva: con un'ampiezza di 1.7
                // quel ritocco si vedeva eccome, come uno scatto a fine corsa.
                applyCameraPose(animated: true, duration: 0.65)
            }
        }

        /// Firma delle cartelle già disegnate, cella per cella.
        var folderSignatures: [Int: String] = [:]

        /// Rifà le cartelle di un solo cassetto, lasciando stare il resto
        /// della parete. Ricostruire tutto per una voce in più costava
        /// centodiciassette celle di geometria e si vedeva come uno scatto.
        func rebuildFolders(cell idx: Int, entries: [String]) {
            folderSignatures[idx] = entries.joined(separator: ",")
            guard let drawer = cellDrawerNodes[idx] else { return }

            // via le vecchie
            (cellFolders[idx]?.pivots ?? []).forEach { $0.removeFromParentNode() }

            let w = DrawerWall3D.cellW - 0.14
            let iw = w - 0.1
            var ctx = DrawerFolders()
            ctx.width = iw - 0.08
            let labeled = entries.count + 1          // +1 per la "+"
            let totalFolders = min(labeled + 24, 44)
            for f in 0..<totalFolders {
                let title: String? = f == 0 ? "+" : (f < labeled ? entries[f - 1] : nil)
                let (folder, fillMat, textMat) = makeFolder(index: f, title: title,
                                                            width: iw - 0.08,
                                                            z: Self.conveyorZ(index: f, focus: 0))
                drawer.addChildNode(folder)
                ctx.pivots.append(folder)
                ctx.baseY = folder.position.y
                if let fillMat { ctx.fillMats[f] = [fillMat] }
                if let textMat { ctx.textMats[f] = [textMat] }
            }
            ctx.maxFocus = CGFloat(labeled - 1)
            cellFolders[idx] = ctx

            // se è il cassetto aperto, le cartelle in uso sono queste
            if openCellIdx == idx {
                folderPivots = ctx.pivots
                folderFillMats = ctx.fillMats
                folderTextMats = ctx.textMats
                folderBaseY = ctx.baseY
                folderWidth = ctx.width
                maxFolderFocus = ctx.maxFocus
                folderBodyHByIdx = [:]
                applyFolderScroll()
            }
        }

        // MARK: - Costruzione scena

        func buildScene(in view: SCNView) {
            guard let parent else { return }
            self.view = view
            signature = parent.labels.map { $0 ?? "·" }.joined(separator: "|")
                + "§" + parent.icons.map { $0 ?? "·" }.joined(separator: "|")
                + "§" + parent.noteColors.map { $0 ?? "·" }.joined(separator: "|")
            // il cassetto aperto va richiuso con la sua animazione, non con lo
            // scatto secco del rebuild (succede entrando in modifica)
            let wasOpen = openCellIdx
            openCellIdx = nil

            let scene = SCNScene()
            scene.background.contents = DrawerWall3D.paper

            let cellW = DrawerWall3D.cellW, cellH = DrawerWall3D.cellH
            let originX = -CGFloat(parent.cols - 1) * cellW / 2
            let originY = CGFloat(parent.rows - 1) * cellH / 2

            cellNodes = []
            cellDrawerNodes = [:]
            cellFolders = [:]
            // se eravamo già in creazione su questa cella, dopo il rebuild la
            // camera va rimessa dov'era invece di rianimare lo zoom
            let wasCreating = creationCellIdx
            creationCellIdx = nil
            // posa corrente della camera: va conservata attraverso il rebuild,
            // altrimenti ogni ricostruzione la riporta alla vista d'insieme e
            // l'animazione successiva riparte da lì (sembra un nuovo zoom)
            let previousPose: (SCNVector3, CGFloat, CGFloat)? = cameraNode.map {
                ($0.position, $0.eulerAngles.x, $0.eulerAngles.y)
            }
            for i in 0..<(parent.cols * parent.rows) {
                let col = i % parent.cols, row = i / parent.cols
                let hasProject = parent.labels[i] != nil
                let cell = SCNNode()
                cell.name = "cell_\(i)"
                cell.position = SCNVector3(originX + CGFloat(col) * cellW, originY - CGFloat(row) * cellH, 0)

                cell.addChildNode(Self.cabinet())
                // ogni cassetto con un progetto è apribile sul posto, non solo il centro
                let (drawer, folders) = makeDrawer(label: parent.labels[i],
                                                   icon: i < parent.icons.count ? parent.icons[i] : nil,
                                                   noteColor: i < parent.noteColors.count ? parent.noteColors[i] : nil,
                                                   withFolders: hasProject ? (i < parent.entriesByCell.count ? parent.entriesByCell[i] : []) : nil)
                drawer.name = "drawer"
                cell.addChildNode(drawer)
                if hasProject {
                    cellDrawerNodes[i] = drawer
                    cellFolders[i] = folders
                    folderSignatures[i] = (i < parent.entriesByCell.count ? parent.entriesByCell[i] : []).joined(separator: ",")
                }
                // il cassetto che era aperto riparte da fuori: lo richiudiamo
                // subito dopo con un'animazione, così il movimento è continuo
                if i == wasOpen { drawer.position.z = DrawerWall3D.pullDistance }

                scene.rootNode.addChildNode(cell)
                cellNodes.append(cell)
            }

            // Camera: frontale, un filo dall'alto — riempie la finestra (overscan)
            updateClosedPose()
            let camera = SCNCamera()
            camera.fieldOfView = 40
            camera.zNear = 0.1
            camera.zFar = 100
            let camNode = SCNNode()
            camNode.camera = camera
            if let (pos, pitch, yaw) = previousPose {
                camNode.position = pos
                camNode.eulerAngles.x = pitch
                camNode.eulerAngles.y = yaw
            } else {
                camNode.position = closedCameraPos
                camNode.eulerAngles.x = closedCameraPitch
            }
            scene.rootNode.addChildNode(camNode)
            cameraNode = camNode

            // velo scuro fra la cartella estratta e tutto il resto: appeso
            // alla camera, così copre sempre l'inquadratura. Non legge né
            // scrive profondità — a decidere chi sta sopra è renderingOrder
            let dim = SCNNode(geometry: SCNPlane(width: 40, height: 40))
            let dimMat = SCNMaterial()
            dimMat.diffuse.contents = NSColor.black
            dimMat.lightingModel = .constant
            dimMat.readsFromDepthBuffer = false
            dimMat.writesToDepthBuffer = false
            dim.geometry?.materials = [dimMat]
            dim.position = SCNVector3(0, 0, -1)
            dim.opacity = 0
            dim.renderingOrder = 900
            dim.isHidden = true
            camNode.addChildNode(dim)
            dimNode = dim

            view.scene = scene

            // Il cassetto che era fuori rientra animato (entrando in modifica
            // il rebuild lo avrebbe fatto sparire di scatto)
            if let open = wasOpen, let drawer = cellDrawerNodes[open] {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.55
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                drawer.position.z = 0
                SCNTransaction.commit()
            }

            // La scena si ricostruisce anche mentre si sta già creando/modificando
            // (cambio icona/colore): in quel caso rimettiamo subito la camera
            // dov'era, senza animazione. Se invece la creazione sta appena
            // iniziando, non tocchiamo nulla: ci pensa enterCreation ad animare.
            // Uscita dalla modifica: il rebuild avviene nello stesso giro in cui
            // creatingCell torna nil, quindi updateNSView non vedrebbe più il
            // cambiamento e la camera resterebbe zoomata (poi scattava al primo
            // movimento del mouse). Qui l'uscita viene animata esplicitamente.
            if wasCreating != nil, parent.creatingCell == nil {
                noteFocused = false
                isReturningFromCreation = true
                DispatchQueue.main.async { [weak self] in
                    self?.parent?.plateRect = nil
                    self?.parent?.noteRect = nil
                }
                moveCamera(to: closedCameraPos, pitch: closedCameraPitch)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.isReturningFromCreation = false
                }
            }

            if let cell = parent.creatingCell, cell < cellNodes.count, wasCreating == cell {
                creationCellIdx = cell
                let c = cellNodes[cell].position
                if noteFocused {
                    let note = Self.notePosition
                    camNode.position = SCNVector3(c.x + note.x, c.y + note.y, 1.0)
                    camNode.eulerAngles.x = 0
                } else {
                    camNode.position = SCNVector3(c.x, c.y + 0.1, 2.4)
                    camNode.eulerAngles.x = -0.04
                }
                camNode.eulerAngles.y = 0
                DispatchQueue.main.async { [weak self] in self?.syncOverlays() }
            }
        }

        // MARK: - Pezzi

        /// Mobile della cella: 4 traverse + fondo, aperto sul davanti.
        /// Traverse e montanti non disegnano i tappi alle estremità: erano
        /// quei trattini a incrociarsi dove i pezzi si innestano fra loro.
        static func cabinet() -> SCNNode {
            let root = SCNNode()
            let w = DrawerWall3D.cellW, h = DrawerWall3D.cellH, d = DrawerWall3D.cabinetDepth
            let t: CGFloat = 0.05
            let zMid = -d / 2

            let top = lineBox(w: w, h: t, l: d, edgeSet: .railX, face: frame); top.position = SCNVector3(0, h / 2 - t / 2, zMid)
            let bottom = lineBox(w: w, h: t, l: d, edgeSet: .railX, face: frame); bottom.position = SCNVector3(0, -h / 2 + t / 2, zMid)
            let left = lineBox(w: t, h: h - t * 2, l: d, edgeSet: .railY, face: frame); left.position = SCNVector3(-w / 2 + t / 2, 0, zMid)
            let right = lineBox(w: t, h: h - t * 2, l: d, edgeSet: .railY, face: frame); right.position = SCNVector3(w / 2 - t / 2, 0, zMid)
            let back = lineBox(w: w, h: h, l: t, edgeSet: .none); back.position = SCNVector3(0, 0, -d + t / 2)
            [top, bottom, left, right, back].forEach(root.addChildNode)
            return root
        }

        /// Cassetto completo: fronte (targhetta + maniglia) + vasca "infinita"
        /// (senza parete di fondo: la fila di cartelle continua e si perde
        /// dentro il mobile). Nodo unico così l'estrazione è un solo move.
        /// Le cartelle tornano in un `DrawerFolders` a parte (una per cassetto,
        /// non condivisa) così ogni cella può aprirsi con le proprie.
        func makeDrawer(label: String?, icon: String?, noteColor: String?, withFolders folders: [String]?) -> (SCNNode, DrawerFolders) {
            let root = SCNNode()
            let w = DrawerWall3D.cellW - 0.14, h = DrawerWall3D.cellH - 0.14

            // fronte
            let front = Self.lineBox(w: w, h: h, l: 0.05)
            front.position = SCNVector3(0, 0, 0.025)
            root.addChildNode(front)

            // targhetta con etichetta
            let plate = Self.lineBox(w: 0.62, h: 0.24, l: 0.03)
            plate.position = SCNVector3(0, h * 0.18, 0.06)
            root.addChildNode(plate)
            if let label {
                let text = Self.textNode(label.lowercased(), maxWidth: 0.54, maxHeight: 0.16, maxScale: 0.1)
                text.name = "plateLabel"
                text.position = SCNVector3(text.position.x, h * 0.18 + text.position.y, 0.085)
                root.addChildNode(text)
            }

            if let note = Self.makeNote(icon: icon, color: noteColor, seedText: label ?? icon ?? "") {
                note.name = "postit"
                root.addChildNode(note)
            }

            // maniglia a staffa: barra + due supporti
            let bar = Self.lineBox(w: 0.5, h: 0.06, l: 0.05)
            bar.position = SCNVector3(0, -h * 0.22, 0.11)
            let supL = Self.lineBox(w: 0.05, h: 0.05, l: 0.09)
            supL.position = SCNVector3(-0.21, -h * 0.22, 0.055)
            let supR = Self.lineBox(w: 0.05, h: 0.05, l: 0.09)
            supR.position = SCNVector3(0.21, -h * 0.22, 0.055)
            [bar, supL, supR].forEach(root.addChildNode)

            // vasca: solo fondo e sponde, lunghissima e SENZA parete di fondo —
            // sparisce dentro il mobile, il cassetto non "finisce" mai
            let trayD: CGFloat = 7.0
            let iw = w - 0.1
            let sideH: CGFloat = 0.5
            let sideY = -h / 2 + sideH / 2 + 0.03

            let bottomTray = Self.lineBox(w: iw, h: 0.03, l: trayD)
            bottomTray.position = SCNVector3(0, -h / 2 + 0.045, -trayD / 2)
            let leftTray = Self.lineBox(w: 0.03, h: sideH, l: trayD)
            leftTray.position = SCNVector3(-iw / 2 + 0.015, sideY, -trayD / 2)
            let rightTray = Self.lineBox(w: 0.03, h: sideH, l: trayD)
            rightTray.position = SCNVector3(iw / 2 - 0.015, sideY, -trayD / 2)
            [bottomTray, leftTray, rightTray].forEach(root.addChildNode)

            // cartelle sul "nastro": la prima è "+" (nuova password), poi le
            // voci con nome, poi anonime a riempire il fondo. Tutte partecipano
            // al movimento, così quelle dietro si avvicinano quando sfogli.
            var ctx = DrawerFolders()
            if let folders {
                let labeled = folders.count + 1   // +1 per la "+"
                let totalFolders = min(labeled + 24, 44)
                ctx.width = iw - 0.08
                for f in 0..<totalFolders {
                    let z = Self.conveyorZ(index: f, focus: 0)
                    let title: String?
                    if f == 0 {
                        title = "+"
                    } else if f < labeled {
                        title = folders[f - 1]
                    } else {
                        title = nil
                    }
                    let (folder, fillMat, textMat) = makeFolder(index: f, title: title, width: iw - 0.08, z: z)
                    root.addChildNode(folder)
                    ctx.pivots.append(folder)
                    ctx.baseY = folder.position.y
                    if let fillMat { ctx.fillMats[f] = [fillMat] }
                    if let textMat { ctx.textMats[f] = [textMat] }
                }
                ctx.maxFocus = CGFloat(labeled - 1)
            }

            return (root, ctx)
        }

        /// Cartella-divider come nella reference: corpo largo con linguetta
        /// trapezoidale (spallette oblique) che alterna sinistra/destra,
        /// "001  nome" sopra la linguetta. Hover: si inverte (nera, testo bianco).
        func makeFolder(index: Int, title: String?, width: CGFloat, z: CGFloat) -> (SCNNode, SCNMaterial?, SCNMaterial?) {
            let node = SCNNode()
            node.name = title != nil ? "folder_\(index)" : nil

            let h = DrawerWall3D.folderBaseBodyH
            // origine del nodo = bordo inferiore della cartella, così la
            // rotazione dello "sfoglio" avviene sulla base, come nella realtà
            let bottomY: CGFloat = -DrawerWall3D.cellH / 2 + 0.12
            node.position = SCNVector3(0, bottomY, z)

            let (shapeNode, fillMat) = Self.folderBody(index: index, width: width, bodyH: h)
            node.addChildNode(shapeNode)

            var textMat: SCNMaterial?
            if let title {
                let (x1, x2) = Self.folderTabX(index: index, width: width)
                let label = title == "+" ? "+" : String(format: "%03d  %@", index, title.lowercased())
                let text = Self.textNode(label,
                                         maxWidth: (x2 - x1) - DrawerWall3D.folderTabSlant * 2 - 0.05,
                                         maxHeight: DrawerWall3D.folderTabH * 0.62)
                text.name = "tabText"
                textMat = text.geometry?.firstMaterial
                text.position = SCNVector3(
                    (x1 + x2) / 2 + text.position.x,
                    h + DrawerWall3D.folderTabH * 0.44 + text.position.y,
                    0.012
                )
                node.addChildNode(text)
            }

            return (node, title != nil ? fillMat : nil, textMat)
        }

        /// Estremi orizzontali della linguetta (alternata sinistra/destra).
        static func folderTabX(index: Int, width: CGFloat) -> (CGFloat, CGFloat) {
            let tabW = width * 0.52
            let x1 = index.isMultiple(of: 2) ? -width / 2 + width * 0.04
                                             : width / 2 - width * 0.04 - tabW
            return (x1, x1 + tabW)
        }

        /// Sagoma della cartella: corpo + linguetta trapezoidale. Il corpo ha
        /// altezza variabile (cresce coi dati dentro), la linguetta no.
        static func folderBody(index: Int, width: CGFloat, bodyH h: CGFloat) -> (SCNNode, SCNMaterial?) {
            let tabH = DrawerWall3D.folderTabH
            let slant = DrawerWall3D.folderTabSlant
            let (x1, x2) = folderTabX(index: index, width: width)
            let points: [CGPoint] = [
                CGPoint(x: -width / 2, y: -h / 2),
                CGPoint(x: width / 2, y: -h / 2),
                CGPoint(x: width / 2, y: h / 2),
                CGPoint(x: x2, y: h / 2),
                CGPoint(x: x2 - slant, y: h / 2 + tabH),
                CGPoint(x: x1 + slant, y: h / 2 + tabH),
                CGPoint(x: x1, y: h / 2),
                CGPoint(x: -width / 2, y: h / 2)
            ]
            let (shapeNode, fillMat) = extrudedOutline(points: points, depth: 0.015)
            shapeNode.name = "folderBody"
            shapeNode.position = SCNVector3(0, h / 2, 0)
            return (shapeNode, fillMat)
        }

        /// Y della cartella estratta: la base scende di metà della crescita,
        /// così il corpo resta centrato sullo schermo qualunque sia l'altezza.
        static func extractedBaseY(bodyH: CGFloat) -> CGFloat {
            0.62 - (bodyH - DrawerWall3D.folderBaseBodyH) / 2
        }

        /// Ricostruisce il corpo della cartella con una nuova altezza e
        /// risistema la linguetta sopra. La geometria va rifatta: scalare in Y
        /// stirerebbe anche linguetta e testo.
        func setFolderBodyHeight(_ idx: Int, h: CGFloat) {
            guard idx < folderPivots.count else { return }
            let node = folderPivots[idx]
            let old = folderBodyHByIdx[idx] ?? DrawerWall3D.folderBaseBodyH
            guard abs(old - h) > 0.001 else { return }
            folderBodyHByIdx[idx] = h
            folderBodyH = h
            // Transazione propria a durata zero. La geometria del corpo si
            // ricostruisce di scatto (non è interpolabile), quindi anche la
            // linguetta deve saltare con lei. Non basta abbassare la durata
            // della transazione in corso: quel valore vale per tutta la
            // transazione al momento del commit, quindi il testo animava
            // comunque e scendeva staccato dal corpo, in ritardo.
            // Da chiamare comunque FUORI dalle transazioni animate.
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            node.childNode(withName: "folderBody", recursively: false)?.removeFromParentNode()
            let (body, fill) = Self.folderBody(index: idx, width: folderWidth, bodyH: h)
            node.insertChildNode(body, at: 0)
            if let fill { folderFillMats[idx] = [fill] }
            // shift, non assegnazione: il testo ha già un suo offset di
            // centratura dentro position.y
            node.childNode(withName: "tabText", recursively: false)?
                .position.y += (h - old)
            SCNTransaction.commit()
            // il corpo è nuovo di zecca: rimettilo sopra a tutto se serve
            if selectedFolderIdx == idx { setFolderOnTop(idx, true) }
        }

        // MARK: - Primitive line-art

        /// Post-it con icona, appiccicato storto sul fronte del cassetto.
        static func makeNote(icon: String?, color: String?, seedText: String) -> SCNNode? {
            guard let icon, let image = symbolImage(icon) else { return nil }
            let w = DrawerWall3D.cellW - 0.14, h = DrawerWall3D.cellH - 0.14
            let side: CGFloat = 0.22
            let note = SCNNode()
            note.position = SCNVector3(w / 2 - side / 2 - 0.1, h * 0.26, 0.06)
            // storto come un vero post-it: angolo casuale in entrambi i versi,
            // ma stabile per lo stesso progetto (dipende dal nome)
            let seed = Double(abs(seedText.hashValue % 1000)) / 1000.0
            note.eulerAngles.z = CGFloat(seed * 0.18 - 0.09)

            let paperNote = SCNPlane(width: side, height: side)
            let noteMat = SCNMaterial()
            noteMat.diffuse.contents = self.color(hex: color) ?? DrawerWall3D.yellowNote
            noteMat.lightingModel = .constant
            paperNote.materials = [noteMat]
            note.addChildNode(SCNNode(geometry: paperNote))

            let glyphPlane = SCNPlane(width: side * 0.58, height: side * 0.58)
            let mat = SCNMaterial()
            mat.diffuse.contents = image
            mat.lightingModel = .constant
            glyphPlane.materials = [mat]
            let glyph = SCNNode(geometry: glyphPlane)
            glyph.position = SCNVector3(0, 0, 0.002)
            note.addChildNode(glyph)
            return note
        }

        /// Colore da stringa esadecimale "#RRGGBB" (nil se non valida).
        static func color(hex: String?) -> NSColor? {
            guard let hex else { return nil }
            let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
            return NSColor(
                red: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255,
                alpha: 1
            )
        }

        /// SF Symbol rasterizzato in nero su fondo trasparente, da usare come
        /// texture per l'icona 3D sul fronte del cassetto.
        static func symbolImage(_ name: String) -> NSImage? {
            let config = NSImage.SymbolConfiguration(pointSize: 128, weight: .medium)
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return nil }

            // canvas quadrato con il simbolo centrato e in proporzione: la
            // texture finisce su un piano quadrato, disegnarlo a tutta area
            // lo schiaccerebbe (i simboli hanno rapporti d'aspetto diversi)
            let side = max(symbol.size.width, symbol.size.height)
            let canvas = NSSize(width: side, height: side)
            let fitted = NSRect(
                x: (side - symbol.size.width) / 2,
                y: (side - symbol.size.height) / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )

            let out = NSImage(size: canvas)
            out.lockFocus()
            symbol.draw(in: fitted)
            ink.set()
            NSRect(origin: .zero, size: canvas).fill(using: .sourceAtop)
            out.unlockFocus()
            return out
        }

        static func flatMaterial(_ color: NSColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .constant
            return m
        }

        /// Quali spigoli tracciare di un box.
        enum EdgeSet {
            case all
            case none
            /// Traverse: solo gli spigoli lunghi + quelli di profondità. Salta
            /// i tappi corti alle estremità, che altrimenti disegnano trattini
            /// dove la traversa si innesta nel montante.
            case railX
            case railY
        }

        /// Box pieno color carta + gli spigoli come geometria a linee nere.
        static func lineBox(w: CGFloat, h: CGFloat, l: CGFloat, edgeSet: EdgeSet = .all, face: NSColor? = nil) -> SCNNode {
            let box = SCNBox(width: w, height: h, length: l, chamferRadius: 0)
            box.materials = [flatMaterial(face ?? paper)]
            let node = SCNNode(geometry: box)
            if edgeSet != .none {
                node.addChildNode(edges(w: w, h: h, l: l, edgeSet: edgeSet))
            }
            return node
        }

        /// Sagoma poligonale estrusa (SCNShape) color carta + tutti gli spigoli
        /// (perimetro fronte, perimetro retro, verticali) come linee nere.
        /// Ritorna anche il materiale del riempimento, per l'inversione in hover.
        static func extrudedOutline(points: [CGPoint], depth: CGFloat) -> (SCNNode, SCNMaterial) {
            let path = NSBezierPath()
            path.move(to: points[0])
            points.dropFirst().forEach { path.line(to: $0) }
            path.close()
            path.flatness = 0.05

            let shape = SCNShape(path: path, extrusionDepth: depth)
            let fill = flatMaterial(paper)
            shape.materials = [fill]
            let node = SCNNode(geometry: shape)

            let n = points.count
            let zf = depth / 2
            var vertices: [SCNVector3] = []
            vertices += points.map { SCNVector3($0.x, $0.y, zf) }
            vertices += points.map { SCNVector3($0.x, $0.y, -zf) }
            var indices: [Int32] = []
            for i in 0..<n {
                let j = (i + 1) % n
                indices += [Int32(i), Int32(j)]              // perimetro fronte
                indices += [Int32(i + n), Int32(j + n)]      // perimetro retro
                indices += [Int32(i), Int32(i + n)]          // spigoli verticali
            }
            let source = SCNGeometrySource(vertices: vertices)
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            let lineGeo = SCNGeometry(sources: [source], elements: [element])
            lineGeo.materials = [flatMaterial(edgeInk)]
            let lineNode = SCNNode(geometry: lineGeo)
            lineNode.scale = SCNVector3(1.004, 1.004, 1.004)
            node.addChildNode(lineNode)

            return (node, fill)
        }

        /// Geometria dei 12 spigoli di un box, leggermente gonfiata per evitare
        /// z-fighting con le facce; il depth test nasconde le linee coperte.
        static func edges(w: CGFloat, h: CGFloat, l: CGFloat, edgeSet: EdgeSet = .all) -> SCNNode {
            let x = Float(w / 2), y = Float(h / 2), z = Float(l / 2)
            let v: [SCNVector3] = [
                SCNVector3(-x, -y, -z), SCNVector3(x, -y, -z), SCNVector3(x, y, -z), SCNVector3(-x, y, -z),
                SCNVector3(-x, -y, z), SCNVector3(x, -y, z), SCNVector3(x, y, z), SCNVector3(-x, y, z)
            ]
            // spigoli raggruppati per direzione
            let alongX: [Int32] = [0, 1, 3, 2, 4, 5, 7, 6]
            let alongY: [Int32] = [1, 2, 0, 3, 5, 6, 4, 7]
            let alongZ: [Int32] = [0, 4, 1, 5, 2, 6, 3, 7]
            let indices: [Int32]
            switch edgeSet {
            case .all, .none: indices = alongX + alongY + alongZ
            case .railX:      indices = alongX + alongZ   // traversa orizzontale
            case .railY:      indices = alongY + alongZ   // montante verticale
            }
            let source = SCNGeometrySource(vertices: v)
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            let geo = SCNGeometry(sources: [source], elements: [element])
            geo.materials = [flatMaterial(edgeInk)]
            let node = SCNNode(geometry: geo)
            node.scale = SCNVector3(1.003, 1.003, 1.003)
            return node
        }

        /// Testo nero piatto, scalato per stare in un riquadro dato; il nodo
        /// torna già centrato (position contiene l'offset di centraggio).
        /// `maxScale` limita l'ingrandimento: senza, un nome corto verrebbe
        /// gonfiato fino a riempire la targhetta e risulterebbe enorme
        /// rispetto a uno lungo.
        static func textNode(_ string: String, maxWidth: CGFloat, maxHeight: CGFloat, maxScale: CGFloat = .infinity) -> SCNNode {
            let text = SCNText(string: string, extrusionDepth: 0)
            text.font = NSFont.monospacedSystemFont(ofSize: 1, weight: .semibold)
            text.flatness = 0.05
            text.materials = [flatMaterial(ink)]
            let node = SCNNode(geometry: text)
            let (minB, maxB) = text.boundingBox
            let rawW = CGFloat(maxB.x - minB.x), rawH = CGFloat(maxB.y - minB.y)
            guard rawW > 0, rawH > 0 else { return node }
            let scale = min(min(maxWidth / rawW, maxHeight / rawH), maxScale)
            node.scale = SCNVector3(scale, scale, scale)
            node.position = SCNVector3(
                -(rawW * scale) / 2 - CGFloat(minB.x) * scale,
                -(rawH * scale) / 2 - CGFloat(minB.y) * scale,
                0
            )
            return node
        }
    }
}

/// SCNView che traccia il movimento del mouse (senza click) e lo riporta
/// normalizzato in -1…1 rispetto al centro della vista, per la parallasse.
final class ParallaxSCNView: SCNView {
    /// (offset normalizzato -1…1, punto grezzo nella vista per l'hit-test)
    var onMouseMove: ((CGPoint, CGPoint) -> Void)?
    /// Delta verticale dello scroll (trackpad/rotella), per scorrere tra le cartelle.
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(-event.scrollingDeltaY)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let nx = (p.x / bounds.width) * 2 - 1
        let ny = (p.y / bounds.height) * 2 - 1
        onMouseMove?(CGPoint(x: max(-1, min(1, nx)), y: max(-1, min(1, ny))), p)
    }
}

extension Array {
    /// Accesso indicizzato che non esplode fuori dai limiti.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
