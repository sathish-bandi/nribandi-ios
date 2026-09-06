import Foundation
import SwiftUI

enum NriTheme {
    static let ink = Color(red: 0.10, green: 0.14, blue: 0.18)
    static let slate = Color(red: 0.35, green: 0.40, blue: 0.45)
    static let sand = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let mist = Color(red: 0.93, green: 0.95, blue: 0.94)
    static let teal = Color(red: 0.07, green: 0.45, blue: 0.48)
    static let terracotta = Color(red: 0.72, green: 0.35, blue: 0.24)
    static let leaf = Color(red: 0.22, green: 0.55, blue: 0.38)
    static let local = Color(red: 0.07, green: 0.45, blue: 0.48)
    static let test = Color(red: 0.75, green: 0.48, blue: 0.12)
    static let prod = Color(red: 0.55, green: 0.18, blue: 0.22)
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
        Text(env.displayName.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
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
    var body: some View {
        Text(text.replacingOccurrences(of: "_", with: " "))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(NriTheme.ink)
            .background(NriTheme.sand, in: Capsule())
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
