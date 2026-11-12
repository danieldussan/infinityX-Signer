import SwiftUI

/// Glass surface: material + gradient fill + 1px border + top inner highlight.
struct GlassBackground: View {
    var radius: CGFloat = Theme.cardRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(LinearGradient(colors: [Theme.glass2, Theme.glass],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(Theme.line, lineWidth: 1)
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.18), Color.clear],
                                              startPoint: .top, endPoint: .center), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.45), radius: 16, x: 0, y: 10)
    }
}

struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassBackground())
    }
}

/// Staggered entrance: fades and slides up, delayed by `index`.
struct Rise: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(Theme.riseSpring.delay(Double(index) * Theme.riseStagger)) { shown = true }
                }
            }
    }
}

extension View {
    func rise(_ index: Int) -> some View { modifier(Rise(index: index)) }
}

/// "INFINITY X" wordmark from the designer asset (Wordmark imageset).
struct BrandLogo: View {
    var showSubtitle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(Theme.wordmarkImageName)
                .resizable()
                .scaledToFit()
                .frame(height: 30)
                .accessibilityLabel("Infinity X")
            if showSubtitle {
                Text("SIGNER").font(.system(size: 11, weight: .semibold)).tracking(2.2).foregroundColor(Theme.text3)
            }
        }
    }
}

/// Common screen wrapper: brand header (+ optional trailing chip), big title, subtitle, content.
/// The global XBackground lives in ContentView.
struct XScreen<Accessory: View, Content: View>: View {
    let title: String
    let subtitle: String
    var showSubtitleLogo = false
    /// Id (set with `.id(...)` on a content view) to scroll to when this value changes.
    var scrollTo: String? = nil
    private let accessory: Accessory
    private let content: Content

    init(title: String, subtitle: String, showSubtitleLogo: Bool = false, scrollTo: String? = nil,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.scrollTo = scrollTo
        self.title = title
        self.subtitle = subtitle
        self.showSubtitleLogo = showSubtitleLogo
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            scroll
                .onChange(of: scrollTo) { target in
                    guard let target = target else { return }
                    // Wait for the entrance animation before scrolling.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(Theme.spring) { proxy.scrollTo(target, anchor: .top) }
                    }
                }
        }
    }

    private var scroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                HStack {
                    BrandLogo(showSubtitle: showSubtitleLogo)
                    Spacer()
                    accessory
                }
                .padding(.horizontal, 2)
                .padding(.top, 8)
                .rise(0)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.screenTitle).foregroundColor(Theme.text)
                    Text(subtitle).font(Theme.sub).foregroundColor(Theme.text2)
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
                .rise(1)

                content
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

extension XScreen where Accessory == EmptyView {
    init(title: String, subtitle: String, showSubtitleLogo: Bool = false, scrollTo: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, showSubtitleLogo: showSubtitleLogo, scrollTo: scrollTo,
                  accessory: { EmptyView() }, content: content)
    }
}
