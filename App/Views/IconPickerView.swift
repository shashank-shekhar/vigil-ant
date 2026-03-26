import SwiftUI

struct IconPickerView: View {
    @Binding var selectedSymbol: String
    @Environment(\.dismiss) private var dismiss

    private let symbols = [
        "icon-bug-ant-outline",
        "icon-cat", "icon-bird", "icon-rabbit", "icon-squirrel",
        "icon-ghost", "icon-skull", "icon-rocket", "icon-flame",
        "icon-star", "icon-heart", "icon-shield", "icon-crown",
        "icon-diamond", "icon-zap", "icon-leaf", "icon-moon", "icon-sun",
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose an Icon")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 6), spacing: 12) {
                ForEach(symbols, id: \.self) { symbol in
                    Button {
                        selectedSymbol = symbol
                        dismiss()
                    } label: {
                        IconImage(name: symbol, size: 20)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedSymbol == symbol ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
    }

}
