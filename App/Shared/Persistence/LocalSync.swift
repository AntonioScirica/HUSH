import Foundation
import MultipeerConnectivity
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Collega Mac e iPhone sulla stessa rete WiFi per travasare i cassetti,
/// senza passare da nessun server: è lo stesso framework che usa AirDrop
/// sotto il cofano, qui usato punto a punto fra le due app.
///
/// Il Mac si mette in ascolto e aspetta che tu confermi ("richiestaDaAccettare"):
/// senza quella conferma chiunque sulla stessa rete potrebbe chiedere di
/// collegarsi e prendersi i cassetti in silenzio. Il collegamento stesso è
/// cifrato di suo (`encryptionPreference: .required`).
@MainActor
final class LocalSync: NSObject, ObservableObject {
    static let serviceType = "hush-sync"
    /// Un'unica istanza per app: sul Mac resta sempre in ascolto mentre
    /// Hush è aperto, così non serve premere niente prima che il telefono
    /// lo trovi — e le Impostazioni ne mostrano solo lo stato, condiviso.
    static let shared = LocalSync()

    enum Stato: Equatable {
        case fermo
        case inAttesa                    // Mac: in ascolto
        case inCerca                     // iPhone: sta cercando
        case collegato(String)           // nome dell'altro dispositivo
        case trasferendo(fatti: Int, totale: Int)
        case fatto(Int)                  // quanti file sono arrivati/partiti
        case errore(String)
    }

    @Published private(set) var stato: Stato = .fermo
    @Published private(set) var trovati: [MCPeerID] = []
    /// Nome di chi sta chiedendo di collegarsi: comparire vuol dire che va
    /// mostrato un conferma/rifiuta, non che si è già collegati.
    @Published private(set) var richiestaDaAccettare: String?

    private let peerID = MCPeerID(displayName: LocalSync.nomeDispositivo())
    private lazy var session: MCSession = {
        let s = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invitationHandler: ((Bool, MCSession?) -> Void)?

    // MARK: - Mac: manda

    private var fileDaMandare: [URL] = []
    /// Chi si mette in ascolto senza sapere già cosa mandare (il Mac, sempre
    /// acceso in sottofondo) lo scopre solo quando qualcuno si collega:
    /// questa chiusura prepara i file al volo e li passa a `pronto(files:per:)`.
    var quandoConnesso: ((MCPeerID) -> Void)?

    /// Si mette in ascolto. Se i file sono già pronti partono appena
    /// qualcuno si collega e viene accettato; altrimenti si aspetta
    /// `quandoConnesso` per prepararli al momento.
    func avviaAscolto(files: [URL] = []) {
        guard advertiser == nil else { return }
        fileDaMandare = files
        stato = .inAttesa
        let a = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        a.delegate = self
        a.startAdvertisingPeer()
        advertiser = a
    }

    /// I file sono pronti per il peer che si è appena collegato: li manda.
    func pronto(files: [URL], per peer: MCPeerID) {
        fileDaMandare = files
        mandaTutti(a: peer)
    }

    func accettaRichiesta() {
        invitationHandler?(true, session)
        invitationHandler = nil
        richiestaDaAccettare = nil
    }

    func rifiutaRichiesta() {
        invitationHandler?(false, nil)
        invitationHandler = nil
        richiestaDaAccettare = nil
        stato = .inAttesa
    }

    private func mandaTutti(a destinatario: MCPeerID) {
        let totale = fileDaMandare.count
        guard totale > 0 else { stato = .fatto(0); return }
        stato = .trasferendo(fatti: 0, totale: totale)

        guard let conteggio = try? JSONSerialization.data(withJSONObject: ["totale": totale]) else { return }
        try? session.send(conteggio, toPeers: [destinatario], with: .reliable)

        var fatti = 0
        for file in fileDaMandare {
            session.sendResource(at: file, withName: file.lastPathComponent, toPeer: destinatario) { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    fatti += 1
                    if let error {
                        self.stato = .errore("invio non riuscito: \(error.localizedDescription)")
                        return
                    }
                    self.stato = .trasferendo(fatti: fatti, totale: totale)
                    if fatti == totale {
                        self.stato = .fatto(totale)
                        // la copia temporanea esportata per l'invio non
                        // serve più: cifrata sì, ma in giro non si lascia
                        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
                        for cartella in Set(self.fileDaMandare.map { $0.deletingLastPathComponent() })
                        where cartella.standardizedFileURL.path.hasPrefix(tmp) {
                            try? FileManager.default.removeItem(at: cartella)
                        }
                        // pronto per il prossimo: senza svuotarli, una
                        // seconda connessione rimanderebbe questi stessi
                        // file invece di ripreparali al volo
                        self.fileDaMandare = []
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            if case .fatto = self.stato { self.stato = .inAttesa }
                        }
                    }
                }
            }
        }
    }

    // MARK: - iPhone: cerca

    func avviaRicerca() {
        trovati = []
        stato = .inCerca
        let b = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b
    }

    func collegati(a peer: MCPeerID) {
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 20)
    }

    /// Cartella temporanea dove atterrano i file di questa sessione, e
    /// quanti ne aspettiamo prima di dire che è finita.
    private var cartellaRicezione: URL?
    private var totaleAtteso: Int?
    private var arrivati = 0

    /// Chiamata quando tutti i file annunciati sono arrivati: la cartella
    /// è pronta per `VaultTransfer.importAll(from:)`.
    var alCompletamento: ((URL) -> Void)?

    func ferma() {
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session.disconnect()
        stato = .fermo
        trovati = []
        cartellaRicezione = nil
        totaleAtteso = nil
        arrivati = 0
    }

    private static func nomeDispositivo() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }
}

extension LocalSync: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.stato = .collegato(peerID.displayName)
                if !self.fileDaMandare.isEmpty {
                    self.mandaTutti(a: peerID)
                } else {
                    self.quandoConnesso?(peerID)
                }
            case .connecting:
                break
            case .notConnected:
                if case .collegato = self.stato { self.stato = .fermo }
            @unknown default:
                break
            }
        }
    }

    /// Il primo messaggio che manda chi invia: solo il totale dei file,
    /// per sapere quando la ricezione è completa.
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int],
              let totale = json["totale"]
        else { return }
        Task { @MainActor in
            let cartella = FileManager.default.temporaryDirectory
                .appendingPathComponent("hush-ricevuti-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
            self.cartellaRicezione = cartella
            self.totaleAtteso = totale
            self.arrivati = 0
            self.stato = .trasferendo(fatti: 0, totale: totale)
        }
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        Task { @MainActor in
            guard let localURL, error == nil, let cartella = self.cartellaRicezione else { return }
            // il nome arriva dalla rete: si tiene solo l'ultimo pezzo, così
            // un nome ostile con dentro "../" non può scrivere fuori dalla
            // cartella d'atterraggio
            let nome = (resourceName as NSString).lastPathComponent
            let dest = cartella.appendingPathComponent(nome)
            try? FileManager.default.moveItem(at: localURL, to: dest)
            self.arrivati += 1
            let totale = self.totaleAtteso ?? self.arrivati
            self.stato = .trasferendo(fatti: self.arrivati, totale: totale)
            if self.arrivati >= totale {
                self.stato = .fatto(self.arrivati)
                self.alCompletamento?(cartella)
                // i file sono stati copiati nella cartella dei progetti:
                // la copia d'atterraggio non deve restare nei temporanei
                try? FileManager.default.removeItem(at: cartella)
                self.cartellaRicezione = nil
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}
}

extension LocalSync: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            self.invitationHandler = invitationHandler
            self.richiestaDaAccettare = peerID.displayName
            // l'app può essere in secondo piano quando arriva la richiesta:
            // senza portarla avanti, l'avviso da accettare passa inosservato
            #if os(macOS)
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.isMiniaturized { window.deminiaturize(nil) }
            if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
            #endif
        }
    }
}

extension LocalSync: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard !self.trovati.contains(peerID) else { return }
            self.trovati.append(peerID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.trovati.removeAll { $0 == peerID }
        }
    }
}
