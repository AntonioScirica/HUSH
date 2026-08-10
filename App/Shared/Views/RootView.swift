import SwiftUI
import VaultCore

public struct RootView: View {
    @StateObject private var vm = VaultViewModel()
    /// Tre stati soli: mai configurato → onboarding; configurato ma chiuso →
    /// porta del caveau; aperto → la parete dei cassetti.
    @State private var unlocked = false
    @State private var configured = MasterKey.isConfigured
    /// Distingue "richiuso col lucchetto" da "appena avviato": nel primo caso
    /// la porta si richiude sotto gli occhi invece di comparire già chiusa.
    @State private var lockedByHand = false
    /// Richiude Hush lasciato lì aperto.
    @StateObject private var idle = IdleWatcher()
    /// Prova finita e nessuna licenza: si passa dal muro, non dai cassetti.
    @State private var licensed = License.isLicensed
    @State private var trialLeft = License.trialDaysLeft
    @State private var openSettings = false
    /// Stessa chiave di Preferences.vistaClassica: @AppStorage la osserva
    /// dal vivo, così lo switch nelle impostazioni cambia schermata subito.
    @AppStorage("scrigno.pref.vistaClassica") private var vistaClassica = false
    /// Vera mentre l'anta si sta aprendo: la vista dietro si carica subito,
    /// così dal vano si vedono già i progetti invece di un foglio vuoto.
    @State private var aperturaInCorso = false
    #if os(macOS)
    /// Sempre in ascolto mentre Hush è sbloccato: il telefono che cerca
    /// trova il Mac senza che tu debba premere niente prima.
    @ObservedObject private var sync = LocalSync.shared
    #endif
    #if os(iOS)
    /// Per richiudere il vault quando l'app finisce in secondo piano e per
    /// coprire l'istantanea che iOS scatta per il multitasking.
    @Environment(\.scenePhase) private var scenePhase
    #endif

    public init() {
        // Prima di qualunque lettura: l'app si chiamava Scrigno, e i suoi
        // dati stanno ancora sotto quel nome.
        Migration.run()
        VaultTransfer.assegnaIconeDalNome()
        Preferences.registerDefaults()
    }

    private func lockUp() {
        // prima si scrive quel che è in sospeso, poi si butta via la chiave:
        // invertendo l'ordine il salvataggio non avrebbe più con cosa cifrare
        VaultLibrary.shared.closeAll(VaultFileManager.shared.projects)
        MasterKey.lock()
        vm.lock()
        idle.stop()
        lockedByHand = true
        unlocked = false
    }

    public var body: some View {
        Group {
            if !licensed && trialLeft <= 0 {
                LicenseWall {
                    licensed = true
                    trialLeft = License.trialDaysLeft
                }
            } else if !configured {
                OnboardingView {
                    configured = true
                    // l'onboarding lascia già la sessione aperta
                    unlocked = MasterKey.isUnlocked
                    if unlocked {
                        idle.onIdle = { lockUp() }
                        idle.start()
                    }
                }
                .transition(.opacity)
            } else {
                // La home sta SEMPRE lì sotto, anche a scrigno chiuso: è la
                // stessa vista che si vede attraverso il vano della porta e
                // che resta a fine animazione. Prima erano due, e allo
                // sblocco si scambiavano: bastava un pelo di differenza fra
                // le due camere 3D per vedere uno scatto.
                //
                // ProjectsHomeView (la parete di cassetti 3D) è tutta l'app
                // ormai: VaultListView era la schermata prima del rewrite e
                // non va più mostrata — ci si finiva appena vm.isUnlocked
                // diventava true (es. creando un progetto), dirottando
                // "nuova password" & co. sul vecchio form.
                ZStack {
                    #if os(iOS)
                    // su iPhone la casa è la vista a elenco: la parete 3D
                    // con la camera e la rotellina è pensata per il Mac
                    ClassicHomeView(onLock: { lockUp() }, attiva: unlocked || aperturaInCorso)
                        .environmentObject(vm)
                        .allowsHitTesting(unlocked)
                    #else
                    if vistaClassica {
                        // la schermata di prima del rewrite, a richiesta.
                        // Sta sotto la porta fin dall'avvio, come la parete:
                        // così all'apertura non c'è nessuno scambio di viste.
                        // Si carica appena l'anta si muove; la barra coi
                        // tasti invece compare solo a porta spalancata.
                        ClassicHomeView(onLock: { lockUp() },
                                        attiva: unlocked || aperturaInCorso,
                                        chromeVisibile: unlocked)
                            .environmentObject(vm)
                            .allowsHitTesting(unlocked)
                    } else {
                    ProjectsHomeView(
                        onLock: { lockUp() },
                        chromeVisible: unlocked,
                        showSettingsSignal: $openSettings
                    )
                    .environmentObject(vm)
                    // a scrigno chiuso si guarda soltanto: niente click che
                    // arrivino ai cassetti attraverso il vano
                    .allowsHitTesting(unlocked)
                    }
                    #endif

                    // promemoria della prova nell'angolo, fuori dai piedi:
                    // in alto sulla parete, in basso nella vista a elenco
                    // (lì sopra c'è la barra laterale coi progetti)
                    if !licensed && unlocked {
                        VStack {
                            #if os(iOS)
                            Spacer()
                            #else
                            if vistaClassica { Spacer() }
                            #endif
                            HStack {
                                TrialBanner { openSettings = true }
                                Spacer()
                            }
                            #if os(macOS)
                            if !vistaClassica { Spacer() }
                            #endif
                        }
                        .padding(20)
                    }

                    if !unlocked {
                        VaultDoorView(closing: lockedByHand,
                                      onOpeningStarted: { aperturaInCorso = true }) {
                            lockedByHand = false
                            aperturaInCorso = false
                            unlocked = true
                            // il conto dell'inattività parte da qui: prima
                            // non c'era niente di aperto da richiudere
                            idle.onIdle = { lockUp() }
                            idle.start()
                        }
                    }
                }
            }
        }
        // Nessuna dissolvenza fra porta e home: dietro l'anta c'è già la
        // stessa parete, con gli stessi progetti nelle stesse celle, quindi
        // il cambio è invisibile di suo. Incrociarle in dissolvenza faceva
        // solo velare l'immagine a fine corsa.
        .animation(.easeInOut(duration: 0.35), value: configured)
        .onChange(of: vistaClassica) { _, classica in
            // si lascia la vista classica: il suo store va chiuso, così la
            // parete rilegge da disco e non restano due copie in memoria
            if !classica { vm.lock() }
        }
        #if os(macOS)
        .onChange(of: unlocked) { _, on in
            if on {
                // il telefono che si collega non sa già cosa mandargli:
                // lo prepariamo al volo solo quando serve davvero
                sync.quandoConnesso = { peer in
                    Task {
                        guard let (_, folder) = try? await VaultTransfer.exportAsync(
                            to: FileManager.default.temporaryDirectory
                        ) else { return }
                        let files = (try? FileManager.default.contentsOfDirectory(
                            at: folder, includingPropertiesForKeys: nil
                        )) ?? []
                        sync.pronto(files: files, per: peer)
                    }
                }
                sync.avviaAscolto()
            } else {
                sync.ferma()
            }
        }
        .alert(sync.richiestaDaAccettare ?? "", isPresented: Binding(
            get: { sync.richiestaDaAccettare != nil },
            set: { if !$0 { sync.rifiutaRichiesta() } }
        )) {
            Button("rifiuta", role: .cancel) { sync.rifiutaRichiesta() }
            Button("accetta") { sync.accettaRichiesta() }
        } message: {
            Text("vuole ricevere i tuoi cassetti via WiFi. accetta solo se sei tu.")
        }
        #endif
        .overlay(alignment: .bottom) {
            if let toast = vm.toast {
                Text(toast.lowercased())
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.ink)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.toast)
        #if os(iOS)
        .onChange(of: scenePhase) { _, fase in
            // app in secondo piano = vault chiuso: sul telefono non c'è
            // il conto dell'inattività del Mac, c'è questo. Col volto o
            // col dito rientrare costa un'occhiata.
            if fase == .background && unlocked {
                lockUp()
                // niente animazione di chiusura al rientro: la porta deve
                // farsi trovare già chiusa
                lockedByHand = false
            }
        }
        .overlay {
            // scudo per l'istantanea del multitasking: senza, iOS fotografa
            // la schermata con le password in chiaro e la mostra a chiunque
            // scorra le app aperte
            if scenePhase != .active {
                ZStack {
                    Theme.paper.ignoresSafeArea()
                    Text("HUSH")
                        .font(Theme.display(40))
                        .kerning(-1)
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        #endif
        .preferredColorScheme(.light)
    }
}
