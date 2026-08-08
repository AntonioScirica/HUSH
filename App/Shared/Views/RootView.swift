import SwiftUI
import VaultCore

public struct RootView: View {
    @StateObject private var vm = VaultViewModel()
    /// Tre stati soli: mai configurato → onboarding; configurato ma chiuso →
    /// porta del caveau; aperto → la parete dei cassetti.
    @State private var unlocked = false
    @State private var configured = MasterKey.isConfigured

    public init() {}

    public var body: some View {
        Group {
            if !configured {
                OnboardingView {
                    configured = true
                    // l'onboarding lascia già la sessione aperta
                    unlocked = MasterKey.isUnlocked
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
                        onLock: {
                            MasterKey.lock()
                            vm.lock()
                            unlocked = false
                        },
                        chromeVisible: unlocked
                    )
                    .environmentObject(vm)
                    // a scrigno chiuso si guarda soltanto: niente click che
                    // arrivino ai cassetti attraverso il vano
                    .allowsHitTesting(unlocked)

                    if !unlocked {
                        VaultDoorView { unlocked = true }
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
