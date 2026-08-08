import AuthenticationServices
import SwiftUI
import UIKit
import VaultCore

final class CredentialProviderViewController: ASCredentialProviderViewController {

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        presentAutoFillUI(serviceIdentifiers: serviceIdentifiers.map(\.identifier))
    }

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        // Scegliamo sempre di richiedere l'interazione (Face ID / password),
        // niente riempimento "silenzioso": è la scelta più sicura per un
        // password manager. iOS richiamerà poi prepareInterfaceToProvideCredential.
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
        children.forEach { $0.willMove(toParent: nil); $0.view.removeFromSuperview(); $0.removeFromParent() }
        let hosting = UIHostingController(rootView: view)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
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
