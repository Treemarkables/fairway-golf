import SwiftUI

struct CourseImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [OverpassImporter.SearchResult] = []
    @State private var isSearching = false
    @State private var importingID: String?
    @State private var errorMessage: String?

    private let importer = OverpassImporter()

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }

                if results.isEmpty && !isSearching {
                    Section {
                        ContentUnavailableView {
                            Label("Find a course", systemImage: "magnifyingglass")
                        } description: {
                            Text("Search OpenStreetMap by name, or list the courses near you. Coverage is volunteer-mapped, so some clubs have every green and others have none.")
                        }
                    }
                }

                ForEach(results) { result in
                    Button {
                        Task { await importCourse(result) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name).font(.headline)
                                if let locality = result.locality {
                                    Text(locality)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if importingID == result.id {
                                ProgressView()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(importingID != nil)
                }
            }
            .searchable(text: $query, prompt: "Course name")
            .onSubmit(of: .search) { Task { await search() } }
            .overlay {
                if isSearching { ProgressView("Searching OpenStreetMap…") }
            }
            .navigationTitle("Import course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Near me") { Task { await searchNearby() } }
                        .disabled(model.location.currentLocation == nil)
                }
            }
            .onAppear {
                model.location.requestAuthorization()
                model.location.startTracking()
            }
            .onDisappear {
                if !model.engine.isActive { model.location.stopTracking() }
            }
        }
    }

    private func search() async {
        errorMessage = nil
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await importer.searchCourses(named: query)
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }

    private func searchNearby() async {
        guard let point = model.location.currentLocation else { return }
        errorMessage = nil
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await importer.searchCourses(near: point)
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }

    private func importCourse(_ result: OverpassImporter.SearchResult) async {
        errorMessage = nil
        importingID = result.id
        defer { importingID = nil }
        do {
            let course = try await importer.importCourse(result)
            model.store.upsert(course)
            model.pushLibraryToWatch()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
