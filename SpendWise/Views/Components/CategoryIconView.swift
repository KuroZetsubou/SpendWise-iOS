import SwiftUI

struct CategoryIconView: View {
    let categoryName: String
    var size: CGFloat = 36
    var showBackground: Bool = true

    private var icon: String {
        AppCategory.categoryIcons[categoryName] ?? "tag"
    }

    private var color: Color {
        Color(hex: AppCategory.categoryColors[categoryName] ?? "#6B7280")
    }

    var body: some View {
        ZStack {
            if showBackground {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: size, height: size)
            }
            Image(systemName: icon)
                .font(.system(size: size * 0.45))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack {
        HStack {
            CategoryIconView(categoryName: "Cibo & Bevande")
            CategoryIconView(categoryName: "Casa")
            CategoryIconView(categoryName: "Trasporti")
            CategoryIconView(categoryName: "Salute")
            CategoryIconView(categoryName: "Entrate")
        }
    }
    .padding()
}
