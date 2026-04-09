import SwiftUI

extension MV {

    // MARK: - Typography

    enum Type {
        // Display — hero titles
        static let displayLarge  = Font.system(size: 34, weight: .bold, design: .default)
        static let displayMedium = Font.system(size: 28, weight: .bold, design: .default)

        // Headlines — section titles
        static let headline      = Font.system(size: 20, weight: .semibold, design: .default)
        static let subheadline   = Font.system(size: 17, weight: .semibold, design: .default)

        // Body — readable text
        static let body          = Font.system(size: 17, weight: .regular, design: .default)
        static let bodyMedium    = Font.system(size: 17, weight: .medium, design: .default)
        static let callout       = Font.system(size: 15, weight: .regular, design: .default)
        static let calloutMedium = Font.system(size: 15, weight: .medium, design: .default)

        // Small — secondary info
        static let footnote      = Font.system(size: 13, weight: .regular, design: .default)
        static let footnoteMedium = Font.system(size: 13, weight: .medium, design: .default)
        static let caption       = Font.system(size: 11, weight: .regular, design: .default)
        static let captionMedium = Font.system(size: 11, weight: .medium, design: .default)

        // Mono — countdown, times, IDs
        static let mono          = Font.system(size: 16, weight: .medium, design: .monospaced)
        static let monoLarge     = Font.system(size: 22, weight: .bold, design: .monospaced)
        static let monoSmall     = Font.system(size: 13, weight: .medium, design: .monospaced)

        // Badge — line numbers
        static let badge         = Font.system(size: 14, weight: .bold, design: .rounded)
        static let badgeLarge    = Font.system(size: 17, weight: .bold, design: .rounded)
    }
}
