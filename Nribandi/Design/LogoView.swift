import SwiftUI

/// Brand mark: teal circle + building icon + optional NRICare wordmark.
struct LogoView: View {
    enum Style {
        case hero
        case compact
        case markOnly
    }

    var style: Style = .hero
    var animate: Bool = false

    @State private var appeared = false

    var body: some View {
        Group {
            switch style {
            case .hero:
                VStack(alignment: .leading, spacing: 14) {
                    mark(size: 64, icon: 28)
                    Text("NRICare")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                        .foregroundStyle(NriTheme.ink)
                        .tracking(1.2)
                }
            case .compact:
                HStack(spacing: 12) {
                    mark(size: 40, icon: 18)
                    Text("NRICare")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(NriTheme.ink)
                        .tracking(0.8)
                }
            case .markOnly:
                mark(size: 56, icon: 24)
            }
        }
        .opacity(animate ? (appeared ? 1 : 0) : 1)
        .offset(y: animate ? (appeared ? 0 : 10) : 0)
        .onAppear {
            guard animate else { return }
            withAnimation(.easeOut(duration: 0.55)) {
                appeared = true
            }
        }
    }

    private func mark(size: CGFloat, icon: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(NriTheme.teal)
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .stroke(NriTheme.sage.opacity(0.55), lineWidth: 2)
                        .padding(3)
                }
            Image(systemName: "building.2.fill")
                .font(.system(size: icon, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityHidden(true)
    }
}
