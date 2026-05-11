import SwiftUI

struct CollectionEditSheet: View {
    public enum Mode: Equatable {
        case create
        case rename(Collection)
    }

    let mode: Mode
    let onSubmit: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var isWorking: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("合集名称", text: $name)
                        .accessibilityIdentifier("collectionEditNameField")
                }
            }
            .navigationTitle(isEditing ? "编辑合集" : "新建合集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "保存" : "创建") {
                        Task {
                            isWorking = true
                            await onSubmit(name)
                            isWorking = false
                            dismiss()
                        }
                    }
                    .disabled(isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("collectionEditSubmitButton")
                }
            }
            .onAppear {
                if case .rename(let collection) = mode {
                    name = collection.name ?? ""
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .rename = mode { return true }
        return false
    }
}

extension CollectionEditSheet.Mode: Identifiable {
    public var id: String {
        switch self {
        case .create: return "create"
        case .rename(let collection): return "rename-\(collection.id)"
        }
    }
}
