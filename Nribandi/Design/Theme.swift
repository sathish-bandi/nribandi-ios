import Foundation
import SwiftUI

enum NriTheme {
    /// Charcoal body text
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.16)
    /// Secondary / muted
    static let slate = Color(red: 0.38, green: 0.42, blue: 0.44)
    /// Warm stone surface (not cream cliché)
    static let sand = Color(red: 0.95, green: 0.94, blue: 0.92)
    /// Soft sage mist panels
    static let mist = Color(red: 0.93, green: 0.95, blue: 0.93)
    /// Deep teal / emerald primary — rental marketplace
    static let teal = Color(red: 0.04, green: 0.42, blue: 0.36)
    /// Soft sage accent
    static let sage = Color(red: 0.66, green: 0.77, blue: 0.71)
    /// Emerald leaf for positive states
    static let leaf = Color(red: 0.18, green: 0.52, blue: 0.40)
    /// Warm alert (not terracotta brand accent)
    static let terracotta = Color(red: 0.70, green: 0.32, blue: 0.28)
    static let local = Color(red: 0.04, green: 0.42, blue: 0.36)
    static let test = Color(red: 0.72, green: 0.50, blue: 0.14)
    static let prod = Color(red: 0.50, green: 0.20, blue: 0.24)

    static var pageBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.97, blue: 0.96),
                Color(red: 0.92, green: 0.95, blue: 0.93),
                Color(red: 0.95, green: 0.94, blue: 0.91)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum NriFormat {
    /// Formats `Decimal` for `Text` / `LocalizedStringKey` without deprecated interpolation.
    static func decimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

struct EnvBadge: View {
    let env: AppEnvironment

    var body: some View {
        if AppEnvironment.allowsEnvironmentSelection {
            Text(env.displayName.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(.white)
                .background(color, in: Capsule())
        }
    }

    private var color: Color {
        switch env {
        case .local: return NriTheme.local
        case .test: return NriTheme.test
        case .prod: return NriTheme.prod
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let accent: Color
    var showsChevron: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(title).font(.caption).foregroundStyle(NriTheme.slate)
                Spacer(minLength: 4)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NriTheme.slate.opacity(0.7))
                }
            }
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(NriTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(NriTheme.mist, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Capsule().fill(accent).frame(width: 18, height: 4).padding(12)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatusChip: View {
    let text: String
    var emphasized: Bool = false

    var body: some View {
        Text(text.replacingOccurrences(of: "_", with: " "))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(emphasized ? .white : NriTheme.ink)
            .background(emphasized ? NriTheme.teal : NriTheme.sand, in: Capsule())
    }
}

extension View {
    /// Visible indicators + always bounce so every iPhone can scroll/discover overflow.
    func nriScrollable() -> some View {
        self
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.always)
    }

    /// Keeps the last rows clear of the tab bar and home indicator on all iPhones.
    func nriPhoneScrollInsets() -> some View {
        self
            .contentMargins(.bottom, 28, for: .scrollContent)
            .safeAreaPadding(.bottom, 8)
    }
}

/// Simple section chrome for ScrollView-based screens (avoids nested List scroll bugs on Mac).
struct NriSectionCard<Content: View>: View {
    let title: String?
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NriTheme.slate)
                    .textCase(.uppercase)
            }
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(NriTheme.sage.opacity(0.35), lineWidth: 1)
            }
            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(NriTheme.slate)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// Wraps content in `NavigationStack` only when the view is shown outside a parent stack (e.g. Ops hub).
struct OpsOptionalNavigationStack: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            NavigationStack { content }
        } else {
            content
        }
    }
}
