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
    /// Richiude lo scrigno lasciato lì aperto.
    @StateObject private var idle = IdleWatcher()
    /// Prova finita e nessuna licenza: si passa dal muro, non dai cassetti.
    @State private var licensed = License.isLicensed
    @State private var trialLeft = License.trialDaysLeft
    @State private var openSettings = false

    public init() {
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
                    ProjectsHomeView(
                        onLock: { lockUp() },
                        chromeVisible: unlocked,
                        showSettingsSignal: $openSettings
                    )
                    .environmentObject(vm)
                    // a scrigno chiuso si guarda soltanto: niente click che
                    // arrivino ai cassetti attraverso il vano
                    .allowsHitTesting(unlocked)

                    // promemoria della prova nell'angolo, fuori dai piedi
                    if !licensed && unlocked {
                        VStack {
                            HStack {
                                TrialBanner { openSettings = true }
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(20)
                    }

                    if !unlocked {
                        VaultDoorView(closing: lockedByHand) {
                            lockedByHand = false
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
        .preferredColorScheme(.light)
    }
}
