import SwiftUI

// MARK: - Brand Color Palette
// Extracted from VSTEP Writing logo
// Primary: #16433F (RGB: 22, 67, 63) - Very Dark Teal
enum BrandColor {
    // Core brand colors extracted directly from logo
    static let primary = Color(hex: "16433F")       // Logo strokes + main text
    static let dark    = Color(hex: "0D2B28")        // Deeper variant for pressed states
    static let medium  = Color(hex: "1E5C56")        // Subtitle text tone in logo
    static let light   = Color(hex: "2E8B82")        // Lighter teal for icons/accents

    // Tonal surface colors derived from brand palette
    static let soft    = Color(hex: "5BB5AC")        // Soft teal - chips, tags
    static let pale    = Color(hex: "A8D5D0")        // Pale teal - subtle highlights
    static let muted   = Color(hex: "D4EEEC")        // Very light - card backgrounds

    // Neutral from logo background
    static let cream   = Color(hex: "F2EDE3")        // Off-white background of logo

    // Semantic aliases
    static let accent:    Color = primary
    static let tint:      Color = primary
    static let highlight: Color = medium
}

// MARK: - Color Hex Initializer
extension Color {
    // Init Color from 6-digit hex string (with or without #)
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
