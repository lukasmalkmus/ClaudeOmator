import SwiftUI

struct GroupEditorSheet: View {
    @State var group: WorkflowGroup
    let store: WorkflowStore
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Name") {
                    TextField("Group Name", text: $group.name)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 6), spacing: 8) {
                        ForEach(GroupColor.allCases) { color in
                            Button {
                                group.color = color
                            } label: {
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if group.color == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.rawValue)
                            .accessibilityAddTraits(group.color == color ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon") {
                    iconPicker
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", role: .cancel) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    store.updateGroup(group)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(group.name.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 520)
    }

    @ViewBuilder
    private var iconPicker: some View {
        ForEach(SFSymbolCategory.allCases) { category in
            DisclosureGroup(category.rawValue) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8), spacing: 6) {
                    ForEach(category.symbols, id: \.self) { symbol in
                        Button {
                            group.icon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(
                                    group.icon == symbol
                                        ? RoundedRectangle(cornerRadius: 6).fill(group.color.swiftUIColor.opacity(0.2))
                                        : nil
                                )
                                .overlay(
                                    group.icon == symbol
                                        ? RoundedRectangle(cornerRadius: 6).stroke(group.color.swiftUIColor, lineWidth: 2)
                                        : nil
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(group.icon == symbol ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
