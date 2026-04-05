import SwiftUI

/// A cross-OS consistent text field replacing `.textFieldStyle(.roundedBorder)`
package struct KommitTextField: View {
    package let placeholder: String
    @Binding package var text: String
    
    @FocusState private var isFocused: Bool
    
    package init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }
    
    package var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(Color.primary.opacity(0.3))
                    .font(.system(size: 13))
            }
            
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isFocused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: isFocused ? 2 : 1)
        )
        // Add a slight padding to accommodate the 2px stroke without altering layout size
        .padding(1)
    }
}

/// A custom vertical radio group to replace native `.pickerStyle(.radioGroup)`
package struct KommitRadioGroup<Value: Equatable & Hashable & Identifiable>: View {
    @Binding package var selection: Value
    package let options: [Value]
    package let titleFor: (Value) -> String

    package init(selection: Binding<Value>, options: [Value], titleFor: @escaping (Value) -> String) {
        self._selection = selection
        self.options = options
        self.titleFor = titleFor
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options) { option in
                let isSelected = selection == option
                Button {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        selection = option
                    }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.3), lineWidth: isSelected ? 4 : 1)
                                .frame(width: 14, height: 14)
                        }
                        
                        Text(titleFor(option))
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A unified button style for icon buttons (like +) across the UI.
package struct KommitIconButtonStyle: ButtonStyle {
    package init() {}
    
    package func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
    }
}
