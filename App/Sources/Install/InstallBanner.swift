import SwiftUI

/// Glass pill pinned at the top while an install queue runs, so closing the overlay never hides it.
struct InstallBanner: View {
    @EnvironmentObject var coordinator: InstallCoordinator

    private var run: [InstallItem] { coordinator.runItems }
    private var done: Int { run.filter { $0.state.isFinal }.count }
    private var current: InstallItem? { run.first { !$0.state.isFinal } }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Instalando \(min(done + 1, max(run.count, 1)))/\(run.count)")
                    .font(.system(size: 13.5, weight: .bold)).foregroundColor(Theme.text)
                if let c = current {
                    Text("\(c.app.job.displayName) · \(c.state.label)")
                        .font(.system(size: 12)).foregroundColor(Theme.text2)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(coordinator.cancelling ? "Cancelando..." : "Cancelar") { coordinator.cancelAll() }
                .buttonStyle(SmallButtonStyle(kind: .danger))
                .disabled(coordinator.cancelling)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(GlassBackground(radius: 18))
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}
