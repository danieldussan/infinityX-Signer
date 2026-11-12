import SwiftUI

struct TabItem {
    let title: String
    let systemImage: String
}

/// Floating glass tab bar with a highlight pill that slides between tabs.
struct FloatingTabBar: View {
    @Binding var selection: Int
    let items: [TabItem]
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let selected = selection == i
                Button {
                    guard selection != i else { return }
                    Haptics.light()
                    withAnimation(Theme.spring) { selection = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .scaleEffect(selected ? 1.12 : 1)
                            .offset(y: selected ? -1 : 0)
                        Text(items[i].title).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(selected ? Theme.text : Theme.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        ZStack {
                            if selected {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Theme.pillGradient)
                                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                                    .matchedGeometryEffect(id: "pill", in: pillNamespace)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.tabBarFill)
                RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.line, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.6), radius: 18, x: 0, y: 14)
        )
        .padding(.horizontal, 14)
    }
}

/// Top toast; errors are red-tinted and stay longer (see Toaster).
struct ToastHost: View {
    @EnvironmentObject var toaster: Toaster

    var body: some View {
        VStack {
            if let toast = toaster.current {
                HStack(spacing: 8) {
                    Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(toast.isError ? Theme.red : Theme.green)
                    Text(toast.text)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 20 / 255.0, green: 22 / 255.0, blue: 28 / 255.0).opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(toast.isError ? Theme.red.opacity(0.6) : Theme.line, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.6), radius: 14, x: 0, y: 10)
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .id(toast.id)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { toaster.dismiss() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.spring, value: toaster.current)
        .allowsHitTesting(toaster.current != nil)
    }
}
