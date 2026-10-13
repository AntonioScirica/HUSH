import SwiftUI

/// Pop-up disegnato con la stessa carta e lo stesso inchiostro di tutto il
/// resto, al posto degli alert di sistema (bianchi, arrotondati, fuori
/// stile). Copre tre casi: conferma semplice, conferma distruttiva, e
/// conferma con un campo di testo (es. "nome del nuovo progetto").
struct CustomAlertOverlay: View {
    let title: String
    var message: String? = nil
    /// nil = niente campo (conferma/errore secco). Non-nil = un campo,
    /// tipicamente il nome di qualcosa da creare.
    var textBinding: Binding<String>? = nil
    var placeholder: String = ""
    var confirmLabel: String = "OK"
    var destructive: Bool = false
    /// nil = un solo bottone (es. errore, niente da annullare).
    var cancelLabel: String? = "Annulla"
    let onConfirm: () -> Void
    var onCancel: (() -> Void)? = nil

    @FocusState private var campoAFuoco: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { onCancel?() }

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(Theme.mono(14, .bold))
                    .foregroundStyle(Theme.ink)

                if let message {
                    Text(message)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let textBinding {
                    TextField(placeholder, text: textBinding)
                        .textFieldStyle(PaperFieldStyle())
                        .focused($campoAFuoco)
                        .onSubmit(onConfirm)
                }

                HStack(spacing: 10) {
                    if let cancelLabel, let onCancel {
                        Button(cancelLabel) { onCancel() }
                            .buttonStyle(OutlineButtonStyle())
                            .frame(maxWidth: .infinity)
                    }
                    Button(confirmLabel) { onConfirm() }
                        .buttonStyle(InkButtonStyle(prominent: true))
                        .frame(maxWidth: .infinity)
                        .tint(destructive ? Theme.danger : nil)
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(Theme.paper)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))
            .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
            .padding(.horizontal, 32)
            .task { campoAFuoco = textBinding != nil }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

extension View {
    /// Monta il pop-up custom sopra il resto quando `isPresented` è vero,
    /// stesso posto in cui si sarebbe agganciato un `.alert(...)`.
    @ViewBuilder
    func customAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        textBinding: Binding<String>? = nil,
        placeholder: String = "",
        confirmLabel: String = "OK",
        destructive: Bool = false,
        cancelLabel: String? = "Annulla",
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                CustomAlertOverlay(
                    title: title, message: message, textBinding: textBinding,
                    placeholder: placeholder, confirmLabel: confirmLabel, destructive: destructive,
                    cancelLabel: cancelLabel,
                    onConfirm: { isPresented.wrappedValue = false; onConfirm() },
                    onCancel: cancelLabel == nil ? nil : { isPresented.wrappedValue = false; onCancel?() }
                )
            }
        }
        .animation(.easeOut(duration: 0.15), value: isPresented.wrappedValue)
    }
}
