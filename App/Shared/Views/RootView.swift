import SwiftUI
import VaultCore

public struct RootView: View {
    @StateObject private var vm = VaultViewModel()

    public init() {}

    public var body: some View {
        Group {
            // ProjectsHomeView (la parete di cassetti 3D) è tutta l'app ormai:
            // VaultListView era la schermata prima del rewrite e non va più
            // mostrata — ci si finiva appena vm.isUnlocked diventava true
            // (es. creando un progetto), dirottando "nuova password" & co.
            // sul vecchio form invece che sul flusso nel cassetto.
            ProjectsHomeView()
                .environmentObject(vm)
        }
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
