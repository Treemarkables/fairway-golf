import SwiftUI

struct CourseListView: View {
    @Environment(AppModel.self) private var model
    @State private var isImporting = false
    @State private var newCourseName = ""
    @State private var isNamingCourse = false

    var body: some View {
        NavigationStack {
            List {
                if model.store.courses.isEmpty {
                    ContentUnavailableView {
                        Label("No courses", systemImage: "map")
                    } description: {
                        Text("Import from OpenStreetMap, or create a blank course and mark each green as you play it.")
                    }
                }

                ForEach(model.store.courses) { course in
                    NavigationLink {
                        CourseEditorView(course: course)
                    } label: {
                        CourseRow(course: course)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        model.store.deleteCourse(id: model.store.courses[index].id)
                    }
                }
            }
            .navigationTitle("Courses")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isImporting = true
                        } label: {
                            Label("Import from OpenStreetMap", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            newCourseName = ""
                            isNamingCourse = true
                        } label: {
                            Label("Blank course", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isImporting) {
                CourseImportView()
            }
            .alert("New course", isPresented: $isNamingCourse) {
                TextField("Course name", text: $newCourseName)
                Button("Create") {
                    let name = newCourseName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    model.store.upsert(.blank(name: name))
                    model.pushLibraryToWatch()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Creates 18 blank par-4 holes. Mark each green by standing on it and tapping Mark Green.")
            }
        }
    }
}
