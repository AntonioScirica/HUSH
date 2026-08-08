import SwiftUI

/// Impostazioni dello scrigno. Poche cose, tutte sulla chiave d'accesso:
/// è l'unica configurazione che conta in un caveau.
struct SettingsView: View {
    let onClose: () -> Void

    @State private var biometry = MasterKey.biometryEnabled
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                IndexLabel(number: 1, text: "impostazioni")
                Rectangle().fill(Theme.line).frame(height: 1.2)
            }

            if MasterKey.biometryAvailable {
                row(
                    title: "sblocco col dito",
                    detail: "apre lo scrigno col sensore invece della password. la password finisce nel Portachiavi di questo computer, protetta dal sistema."
                ) {
                    Toggle("", isOn: $biometry)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: biometry) { _, on in apply(on) }
                }
            } else {
                Text("questo computer non ha un sensore biometrico.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
            }

            Rectangle().fill(Theme.line.opacity(0.4)).frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("promemoria della password")
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(reminderText)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error {
                Text(error)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.danger)
            }

            Spacer(minLength: 0)

            Button("chiudi") { onClose() }
                .buttonStyle(InkButtonStyle(prominent: true))
        }
        .padding(30)
        .frame(width: 440, height: 400)
        .background(Theme.paper)
        .preferredColorScheme(.light)
    }

    private func row<Control: View>(title: String, detail: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            control()
        }
    }

    private var reminderText: String {
        let days = Int(MasterKey.typeAgainAfter / 86_400)
        guard MasterKey.biometryEnabled else {
            return "la password si digita a ogni apertura."
        }
        let elapsed = Int(MasterKey.sinceTyped / 86_400)
        let left = max(0, days - elapsed)
        return left == 0
            ? "alla prossima apertura la password va riscritta a mano."
            : "ogni \(days) giorni la password va riscritta a mano, per non dimenticarla. mancano \(left) giorni."
    }

    /// Accendere il dito significa mettere la password nel Portachiavi: si può
    /// fare solo a scrigno aperto, perché è lì che la chiave è in memoria.
    private func apply(_ on: Bool) {
        error = nil
        guard on else {
            MasterKey.disableBiometry()
            return
        }
        guard let key = MasterKey.session else {
            error = "scrigno bloccato: riapri e riprova."
            biometry = false
            return
        }
        do {
            try MasterKey.enableBiometry(password: key)
        } catch {
            self.error = "non è stato possibile attivarlo: \(error.localizedDescription)"
            biometry = false
        }
    }
}
