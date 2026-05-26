import SwiftUI

enum AppTheme {
    enum Colors {
        static let background = Color(hex: 0x0C1916)
        static let surface = Color(hex: 0x152E27)
        static let surfaceLight = Color(hex: 0x1C3D34)
        static let surfaceBorder = Color(hex: 0x26524A)
        static let primary = Color(hex: 0xE8643C)
        static let primaryLight = Color(hex: 0xF08B5A)
        static let primaryDim = Color(hex: 0x3A241C)
        static let success = Color(hex: 0x3DA874)
        static let successDim = Color(hex: 0x173326)
        static let warning = Color(hex: 0xF0AA3C)
        static let warningDim = Color(hex: 0x3F3120)
        static let error = Color(hex: 0xE85252)
        static let errorDim = Color(hex: 0x3C2020)
        static let record = Color(hex: 0xFF5733)
        static let text = Color(hex: 0xFDF8F0)
        static let textSecondary = Color(hex: 0xB8A898)
        static let textTertiary = Color(hex: 0x7A6A5A)
        static let border = Color(hex: 0x2B4A42)
        static let tabBar = Color(hex: 0x0A1512)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
