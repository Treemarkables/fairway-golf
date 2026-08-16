import SwiftUI

struct BagEditorView: View {
    @Environment(AppModel.self) private var model
    @State private var bag: Bag = .standard
    @State private var isAddingClub = false

    var body: some View {
        List {
            Section {
                // Sorted for display, but edited through the unsorted store, so a
                // toggle always writes back to the right club.
                ForEach(bag.clubs.sorted { $0.sortOrder < $1.sortOrder }) { club in
                    if let index = bag.clubs.firstIndex(where: { $0.id == club.id }) {
                        Toggle(isOn: $bag.clubs[index].isInBag) {
                            HStack {
                                Text(club.abbreviation)
                                    .font(.headline.monospaced())
                                    .frame(width: 40, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(club.name)
                                    Text(club.kind.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    let ordered = bag.clubs.sorted { $0.sortOrder < $1.sortOrder }
                    let doomed = offsets.map { ordered[$0].id }
                    bag.clubs.removeAll { doomed.contains($0.id) }
                }
            } header: {
                Text("Clubs")
            } footer: {
                Text("Turn a club off to hide it from the watch picker without losing its history. The order here is the order the Digital Crown scrolls through.")
            }

            Section {
                Button {
                    isAddingClub = true
                } label: {
                    Label("Add a club", systemImage: "plus")
                }
                Button("Reset to a standard set", role: .destructive) {
                    bag = .standard
                }
            }
        }
        .navigationTitle("My bag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    model.store.updateBag(bag)
                    model.pushLibraryToWatch()
                }
            }
        }
        .onAppear { bag = model.store.bag }
        .sheet(isPresented: $isAddingClub) {
            AddClubView { club in
                bag.clubs.append(club)
            }
        }
    }
}

struct AddClubView: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (Club) -> Void

    @State private var abbreviation = ""
    @State private var name = ""
    @State private var kind: ClubKind = .iron
    @State private var sortOrder = 50

    var body: some View {
        NavigationStack {
            Form {
                TextField("Short label (e.g. 7i)", text: $abbreviation)
                TextField("Name (e.g. 7 Iron)", text: $name)
                Picker("Type", selection: $kind) {
                    ForEach(ClubKind.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper("Order \(sortOrder)", value: $sortOrder, in: 0...99)
            }
            .navigationTitle("Add club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onAdd(
                            Club(
                                abbreviation: abbreviation.isEmpty ? "??" : abbreviation,
                                name: name.isEmpty ? abbreviation : name,
                                kind: kind,
                                sortOrder: sortOrder
                            )
                        )
                        dismiss()
                    }
                    .disabled(abbreviation.isEmpty && name.isEmpty)
                }
            }
        }
    }
}
