//
//  CountryColors.swift
//  Day Memory
//

import SwiftUI

enum CountryColors {
    static func baseColor(for code: String) -> Color {
        let normalized = code.uppercased()
        return countryBaseColors[normalized] ?? fallbackColor(for: normalized)
    }

    static func dotColor(countryCode: String, isWorking: Bool) -> Color {
        baseColor(for: countryCode).opacity(isWorking ? 0.95 : 0.45)
    }

    /// Distinct basic colors for frequently used countries.
    private static let countryBaseColors: [String: Color] = [
        "NL": .green,
        "DE": .orange,
        "BE": .yellow,
        "FR": .red,
        "GB": .blue,
        "IE": .cyan,
        "ES": .purple,
        "PT": .pink,
        "IT": Color(hue: 0.12, saturation: 0.72, brightness: 0.82),
        "CH": .indigo,
        "AT": .brown,
        "US": Color(hue: 0.52, saturation: 0.62, brightness: 0.76),
        "CA": Color(hue: 0.88, saturation: 0.56, brightness: 0.78),
        "AU": Color(hue: 0.07, saturation: 0.78, brightness: 0.86),
        "NZ": Color(hue: 0.62, saturation: 0.52, brightness: 0.72),
        "JP": Color(hue: 0.95, saturation: 0.48, brightness: 0.76),
        "SG": Color(hue: 0.72, saturation: 0.58, brightness: 0.75),
        "AE": .blue,
    ]

    /// Evenly spaced hues for countries not in the explicit palette.
    private static func fallbackColor(for code: String) -> Color {
        let hash = code.unicodeScalars.reduce(0) { acc, scalar in
            ((acc * 31) &+ Int(scalar.value)) & 0x7fffffff
        }
        let paletteCount = 12
        let index = hash % paletteCount
        let hue = (Double(index) + 0.5) / Double(paletteCount)
        return Color(hue: hue, saturation: 0.65, brightness: 0.78)
    }
}

struct CountryColorDot: View {
    var code: String
    var isWorking: Bool = true

    var body: some View {
        Circle()
            .fill(CountryColors.dotColor(countryCode: code, isWorking: isWorking))
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }
}
