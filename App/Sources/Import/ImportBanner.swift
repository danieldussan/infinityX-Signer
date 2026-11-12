import SwiftUI

/// Non-blocking glass pill pinned at the top while imports run. Only the pill itself takes touches.
struct ImportBanner: View {
    let jobs: [ImportJob]

    private var current: ImportJob? { jobs.first }

    private var title: String {
        jobs.count > 1 ? "Importando \(jobs.count) archivos" : "Importando \(current?.fileName ?? "")"
    }

    private var subtitle: String {
        guard let job = current else { return "" }
        var text = job.phase.text
        if let p = job.progress { text += " \(Int((p * 100).rounded()))%" }
        return jobs.count > 1 ? "\(job.fileName) · \(text)" : text
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.text)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13.5, weight: .bold)).foregroundColor(Theme.text)
                    .lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.system(size: 12)).foregroundColor(Theme.text2)
                    .lineLimit(1).truncationMode(.middle)
                if let p = current?.progress {
                    ProgressBar(value: p)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if current?.progress == nil {
                ProgressView().tint(.white)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(GlassBackground(radius: 18))
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(Theme.ctaGradient)
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
    }
}
