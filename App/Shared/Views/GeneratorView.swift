import SwiftUI
import VaultCore

struct GeneratorView: View {
    @EnvironmentObject var vm: VaultViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var length: Double = 20
    @State private var lowercase = true
    @State private var uppercase = true
    @State private var digits = true
    @State private var symbols = true
    @State private var generated = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                IndexLabel(number: 6, text: "generatore")
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.ink)
            }

            // Password su blocco nero, mono, come i display delle reference
            Text(generated.isEmpty ? " " : generated)
                .font(Theme.mono(15, .semibold))
                .foregroundStyle(Theme.paper)
                .multilineTextAlignment(.center)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Theme.ink)
                .textSelection(.enabled)

            HStack {
                Text("lunghezza")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
                Slider(value: $length, in: 8...64, step: 1)
                    .tint(Theme.ink)
                Text("\(Int(length))")
                    .font(Theme.mono(12, .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26)
            }
            .onChange(of: length) { regenerate() }

            HStack(spacing: 8) {
                charToggle("abc", $lowercase)
                charToggle("ABC", $uppercase)
                charToggle("123", $digits)
                charToggle("#!?", $symbols)
            }
            .onChange(of: lowercase) { regenerate() }
            .onChange(of: uppercase) { regenerate() }
            .onChange(of: digits) { regenerate() }
            .onChange(of: symbols) { regenerate() }

            HStack(spacing: 10) {
                Button("rigenera") { regenerate() }
                    .buttonStyle(OutlineButtonStyle())
                Button("copia") { vm.copyToClipboard(generated, label: "Password generata") }
                    .buttonStyle(InkButtonStyle(prominent: true))
            }
        }
        .padding(26)
        .frame(minWidth: 420)
        .background(Theme.paper)
        .preferredColorScheme(.light)
        .onAppear { regenerate() }
    }

    private func charToggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Button {
            binding.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(Theme.mono(12, .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(binding.wrappedValue ? Theme.paper : Theme.ink)
                .background(binding.wrappedValue ? Theme.ink : Theme.paperRaised)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func regenerate() {
        let opts = PasswordGeneratorOptions(
            length: Int(length), lowercase: lowercase, uppercase: uppercase, digits: digits, symbols: symbols
        )
        generated = PasswordGenerator.generate(opts)
    }
}
