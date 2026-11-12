import SwiftUI
import UIKit

// MARK: - Buttons

/// Big gradient call-to-action ("Firmar N apps").
struct CTAButtonStyle: ButtonStyle {
    var enabled: Bool = true
    var height: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.system(size: 17, weight: .heavy).italic())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.ctaRadius, style: .continuous)
                    .fill(Theme.ctaGradient)
                    .shadow(color: Theme.blue.opacity(0.5), radius: 16, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.ctaRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.clear],
                                                 startPoint: .top, endPoint: .center), lineWidth: 1)
            )
            .grayscale(enabled ? 0 : 0.8)
            .brightness(enabled ? 0 : -0.3)
            .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Secondary glass button of the same size family as the CTA.
struct GhostButtonStyle: ButtonStyle {
    var height: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.system(size: 17, weight: .heavy).italic())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.ctaRadius, style: .continuous).fill(Theme.glass2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.ctaRadius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Small pill button ("Ver", "Actualizar").
struct SmallButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, danger }
    var kind: Kind = .normal

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundColor(kind == .danger ? Theme.red : .white)
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 38)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(kind == .primary ? AnyShapeStyle(Theme.segGradient) : AnyShapeStyle(Theme.glass2)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(kind == .danger ? Theme.red.opacity(0.45) : Theme.line, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Plain press-scale for custom tappable cards.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

// MARK: - Chips, labels, icons

struct StatusChip: View {
    let text: String
    var color: Color? = Theme.green

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color ?? Theme.text3)
                .frame(width: 7, height: 7)
                .shadow(color: (color ?? Color.clear).opacity(0.9), radius: 4)
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.glass))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Uppercase tracking label above a field or section.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label)
            .tracking(1.3)
            .foregroundColor(Theme.text3)
    }
}

struct IconBox: View {
    let systemName: String
    var green = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(green ? Theme.iconGreenGradient : Theme.iconGradient))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Circular selection indicator for list items.
struct SelectDot: View {
    let on: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Theme.green : Theme.text3, lineWidth: 2)
            if on {
                Circle().fill(Theme.green)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(.black)
            }
        }
        .frame(width: 22, height: 22)
        .scaleEffect(on ? 1.1 : 1)
        .animation(Theme.spring, value: on)
    }
}

struct EmptyStateView: View {
    let systemName: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemName).font(.system(size: 36)).foregroundColor(Theme.text2)
            Text(text).font(Theme.sub).foregroundColor(Theme.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

/// Spinning ring (replaced by a system spinner when Reduce Motion is on).
struct SpinnerRing: View {
    var size: CGFloat = 22
    var lineWidth: CGFloat = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    var body: some View {
        if reduceMotion {
            ProgressView().scaleEffect(0.7).frame(width: size, height: size)
        } else {
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(Theme.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { angle = 360 }
            }
        }
    }
}

// MARK: - Dashed import card

struct DropCard: View {
    let title: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Theme.brandGradient))
                    .padding(.bottom, 4)
                Text(title).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                Text(hint).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(Theme.text3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
    }
}

// MARK: - Inputs

/// Rounded dark field with blue focus ring and red "bad" state.
struct XField: View {
    let placeholder: String
    @Binding var text: String
    var bad = false
    var secure = false
    var keyboard: UIKeyboardType = .default
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .focused($focused)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.white)
        .tint(Theme.blue)
        .keyboardType(keyboard)
        .autocorrectionDisabled(true)
        .textInputAutocapitalization(.never)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).fill(Theme.field))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .strokeBorder(bad ? Theme.red : (focused ? Theme.blue : Theme.line), lineWidth: bad || focused ? 2 : 1)
        )
        .animation(.easeOut(duration: 0.2), value: focused)
        .animation(.easeOut(duration: 0.2), value: bad)
    }
}

/// Segmented control with a sliding indicator.
struct XSegmented: View {
    let options: [String]
    @Binding var selection: Int
    var height: CGFloat = 36
    /// Optional count badge per option.
    var counts: [Int]? = nil

    var body: some View {
        GeometryReader { geo in
            let w = max(0, (geo.size.width - 8) / CGFloat(max(options.count, 1)))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.segGradient)
                    .shadow(color: Theme.blue.opacity(0.5), radius: 8, x: 0, y: 4)
                    .frame(width: w, height: height)
                    .offset(x: 4 + CGFloat(selection) * w, y: 4)
                HStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { i in
                        Button {
                            Haptics.light()
                            withAnimation(Theme.spring) { selection = i }
                        } label: {
                            HStack(spacing: 5) {
                                Text(options[i])
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                if let counts = counts, i < counts.count {
                                    Text("\(counts[i])")
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Capsule().fill(Color.white.opacity(selection == i ? 0.25 : 0.12)))
                                }
                            }
                            .foregroundColor(selection == i ? Theme.text : Theme.text2)
                            .frame(width: w, height: height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .offset(x: 4, y: 4)
            }
        }
        .frame(height: height + 8)
        .background(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).fill(Color.black.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Custom on/off switch (green track, white knob).
struct XSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            Haptics.light()
            withAnimation(Theme.spring) { isOn.toggle() }
        } label: {
            ZStack(alignment: .leading) {
                Capsule().fill(isOn ? Theme.green : Color.white.opacity(0.16))
                Circle()
                    .fill(Color.white)
                    .frame(width: 26, height: 26)
                    .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 2)
                    .offset(x: isOn ? 23 : 3)
            }
            .frame(width: 52, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "Activado" : "Desactivado")
    }
}

/// Small pill tag used for the live preview ("WAB 21 · chip.21").
struct PreviewTag: View {
    let text: String
    var accent: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            if let accent = accent {
                Text("·").foregroundColor(Theme.green)
                Text(accent)
            }
        }
        .font(Theme.monoTag)
        .foregroundColor(Theme.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Simple wrapping layout for tags (iOS 16 Layout protocol).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(width: usedWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
