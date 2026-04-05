import SwiftUI

struct TypeSegmentedControl: View {
    @Binding var selection: FinancialFlowType

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FinancialFlowType.allCases, id: \.self) { flowType in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = flowType
                    }
                }) {
                    Text(flowType.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .foregroundColor(selection == flowType ? .white : .primary)
                }
                .buttonStyle(.plain)
                .background(selection == flowType ? Color.blue : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .fixedSize(horizontal: true, vertical: false)
    }
}
