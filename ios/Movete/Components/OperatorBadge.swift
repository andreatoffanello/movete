import SwiftUI

/// Displays an operator logo or name badge.
/// Uses asset catalog images when available, falls back to text badge.
struct OperatorBadge: View {
    let agencyId: String
    var size: CGFloat = 20

    var body: some View {
        if let image = UIImage(named: "Operators/\(assetName)") {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: size)
        } else {
            // Fallback: text badge
            Text(displayName)
                .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MV.Colors.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MV.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    private var assetName: String {
        switch agencyId {
        case "OP1":   return "atac"
        case "OP265": return "troiani"
        case "TUS":   return "tuscia"
        case "BIS":   return "bis"
        case "SAP":   return "sap"
        default:      return agencyId.lowercased()
        }
    }

    private var displayName: String {
        switch agencyId {
        case "OP1":   return "ATAC"
        case "OP265": return "Troiani"
        case "TUS":   return "Tuscia"
        case "BIS":   return "BIS"
        case "SAP":   return "SAP"
        default:      return agencyId
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        OperatorBadge(agencyId: "OP1")
        OperatorBadge(agencyId: "BIS")
        OperatorBadge(agencyId: "OP265")
        OperatorBadge(agencyId: "TUS")
        OperatorBadge(agencyId: "SAP")
    }
    .padding()
    .background(MV.Colors.background)
}
