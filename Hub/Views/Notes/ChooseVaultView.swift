import SwiftUI

/// Leerer Zustand ohne Vault – mit einer klaren nächsten Aktion.
struct ChooseVaultView: View {
    @Environment(AppModel.self) private var model
    var lostPath: String?
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(message == nil ? "Kein Vault ausgewählt" : "Kein Zugriff auf den Vault",
                  systemImage: message == nil ? "folder.badge.questionmark" : "lock.trianglebadge.exclamationmark")
        } description: {
            if let message {
                Text(message)
                if let lostPath {
                    Text(lostPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } else {
                Text("Wähle den Ordner deines Obsidian-Vaults, um deine Notizen hier zu sehen.")
            }
        } actions: {
            Button(message == nil ? "Vault auswählen …" : "Vault erneut auswählen …") {
                model.chooseVault()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Hell") {
    ChooseVaultView()
        .environment(PreviewData.model(withVault: false))
        .frame(width: 360, height: 400)
}

#Preview("Dunkel – Zugriff verloren") {
    ChooseVaultView(lostPath: "/Users/vorschau/Vault", message: "Hub hat keinen Zugriff mehr auf den Vault.")
        .environment(PreviewData.model(withVault: false))
        .frame(width: 360, height: 400)
        .preferredColorScheme(.dark)
}
