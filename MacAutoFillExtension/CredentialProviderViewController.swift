import AuthenticationServices
import SwiftUI
import AppKit
import VaultCore

/// Stessa cosa dell'estensione AutoFill su iPhone (AutoFillExtension/), ma
/// per il riempimento automatico di sistema su Mac — quello che compare
/// nel piccolo menu "chiave" di Safari accanto al campo, come 1Password.
/// Attivabile da Impostazioni di Sistema → Password → Opzioni di
/// riempimento automatico.
final class CredentialProviderViewController: ASCredentialProviderViewController {

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        presentAutoFillUI(serviceIdentifiers: serviceIdentifiers.map(\.identifier))
    }

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        // Come su iPhone: mai un riempimento silenzioso, sempre un passaggio
        // (password/Touch ID) prima di consegnare qualunque credenziale.
        let error = NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userInteractionRequired.rawValue)
        extensionContext.cancelRequest(withError: error)
    }

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        presentAutoFillUI(serviceIdentifiers: [credentialIdentity.serviceIdentifier.identifier])
    }

    private func presentAutoFillUI(serviceIdentifiers: [String]) {
        let vm = AutoFillViewModel(serviceIdentifiers: serviceIdentifiers)
        let rootView = AutoFillRootView(
            vm: vm,
            preselectId: nil,
            onSelect: { [weak self] username, password in
                self?.complete(username: username, password: password)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )
        embed(SwiftUI.AnyView(rootView))
    }

    private func embed<V: View>(_ view: V) {
        children.forEach { $0.removeFromParent() }
        self.view.subviews.forEach { $0.removeFromSuperview() }

        let hosting = NSHostingController(rootView: view)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
    }

    private func complete(username: String, password: String) {
        let credential = ASPasswordCredential(user: username, password: password)
        extensionContext.completeRequest(withSelectedCredential: credential, completionHandler: nil)
    }

    private func cancel() {
        let error = NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue)
        extensionContext.cancelRequest(withError: error)
    }
}
