import SwiftUI

struct TransitIcon: View {
    let type: TransitType
    var size: CGFloat = 18
    var weight: Font.Weight = .semibold
    var colored: Bool = true

    var body: some View {
        Image(systemName: type.sfSymbol)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(colored ? MV.Colors.transitColor(for: type) : MV.Colors.textSecondary)
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(TransitType.allCases, id: \.self) { type in
            VStack {
                TransitIcon(type: type)
                Text(type.rawValue)
                    .font(MV.Type.caption)
                    .foregroundStyle(MV.Colors.textSecondary)
            }
        }
    }
    .padding()
    .background(MV.Colors.background)
}
