import SwiftUI

struct StopAnnotationView: View {
    let stop: Stop
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? MV.Colors.accent : MV.Colors.surface)
                .frame(width: isSelected ? 32 : 20, height: isSelected ? 32 : 20)
                .overlay(
                    Circle()
                        .stroke(isSelected ? MV.Colors.accent : MV.Colors.border, lineWidth: isSelected ? 0 : 1)
                )
                .mvSubtleShadow()

            Image(systemName: "bus.fill")
                .font(.system(size: isSelected ? 14 : 9, weight: .semibold))
                .foregroundStyle(isSelected ? MV.Colors.background : MV.Colors.textSecondary)
        }
        .animation(.snappy, value: isSelected)
        .onTapGesture {
            Haptics.light()
        }
    }
}
