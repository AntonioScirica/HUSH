import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers
import VaultCore

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class VaultViewModel: ObservableObject {
    let store = VaultStore()
    private var storeSub: AnyCancellable?

    init() {
        // Il VaultStore è un ObservableObject annidato: senza questo ponte le
        // viste che osservano il ViewModel non si aggiornano dopo add/update/delete.
        storeSub = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    @Published var searchText: String = ""
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false
    @Published var toast: String?

    private var autolockTask: Task<Void, Never>?
    private var clipboardClearTask: Task<Void, Never>?

    let autolockSeconds: TimeInterval = 5 * 60
    let clipboardClearSeconds: TimeInterval = 30

    var isUnlocked: Bool { store.isUnlocked }
    var vaultName: String { store.database?.name ?? "Vault" }

    var filteredEntries: [VaultEntry] {
        let all = store.allEntries.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter { entry in
            if entry.title.lowercased().contains(q)
                || entry.username.lowercased().contains(q)
                || entry.url.lowercased().contains(q)
                || entry.notes.lowercased().contains(q) { return true }
            return entry.customFields.contains { $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q) }
        }
    }

    // MARK: - Apertura / creazione

    func createNew(name: String, password: String) {
        store.createNew(name: name, password: password)
        resetAutolockTimer()
    }

    func open(fileData: [UInt8], password: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await store.open(fileData: fileData, password: password)
            resetAutolockTimer()
            showToast("Vault aperto")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async -> [UInt8]? {
        isBusy = true
        defer { isBusy = false }
        do {
            let bytes = try await store.save()
            showToast("Vault salvato")
            return bytes
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func lock() {
        store.lock()
        autolockTask?.cancel()
        searchText = ""
    }

    // MARK: - Autolock

    func resetAutolockTimer() {
        autolockTask?.cancel()
        autolockTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.autolockSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.lock()
        }
    }

    // MARK: - Clipboard

    func copyToClipboard(_ text: String, label: String) {
        #if os(iOS)
        // localOnly: la password non deve rimbalzare sugli altri dispositivi
        // con la clipboard universale. E una scadenza di sistema, oltre alla
        // nostra: se l'app viene chiusa prima del timer, ci pensa iOS.
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(clipboardClearSeconds),
            ]
        )
        #elseif os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #endif
        showToast("\(label) copiato: si cancella tra 30s")

        clipboardClearTask?.cancel()
        let expected = text
        clipboardClearTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(clipboardClearSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            #if os(iOS)
            if UIPasteboard.general.string == expected { UIPasteboard.general.string = "" }
            #elseif os(macOS)
            if NSPasteboard.general.string(forType: .string) == expected { NSPasteboard.general.clearContents() }
            #endif
        }
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if toast == message { toast = nil }
        }
    }
}
