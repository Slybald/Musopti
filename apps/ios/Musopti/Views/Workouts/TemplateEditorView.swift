import SwiftUI
import SwiftData

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutTemplate?

    @State private var name: String = ""
    @State private var entries: [WorkoutTemplateEntry] = []
    @State private var showExercisePicker = false

    init(template: WorkoutTemplate? = nil) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _entries = State(initialValue: template?.exercises.sorted(by: { $0.order < $1.order }) ?? [])
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !entries.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MusoptiTheme.surfaceBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MusoptiTheme.largePadding) {
                        nameField
                        exercisesList
                        addExerciseButton
                    }
                    .padding(MusoptiTheme.mediumPadding)
                }
            }
            .navigationTitle(template == nil ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(MusoptiTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(isValid ? MusoptiTheme.accent : MusoptiTheme.textTertiary)
                        .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                TemplateExercisePickerView { exercise in
                    addExercise(exercise)
                }
            }
        }
    }

    // MARK: - Subviews

    private var nameField: some View {
        TextField("Workout name", text: $name)
            .font(MusoptiTheme.sectionTitle)
            .foregroundStyle(MusoptiTheme.textPrimary)
            .padding(MusoptiTheme.mediumPadding)
            .background(MusoptiTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var exercisesList: some View {
        VStack(spacing: MusoptiTheme.smallPadding) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                ExerciseEntryRow(
                    entry: binding(for: index),
                    onDelete: { entries.remove(at: index) }
                )
            }
            .onMove { source, destination in
                entries.move(fromOffsets: source, toOffset: destination)
                reorderEntries()
            }
        }
    }

    private var addExerciseButton: some View {
        Button {
            showExercisePicker = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add Exercise")
            }
            .font(MusoptiTheme.bodyText.weight(.medium))
            .foregroundStyle(MusoptiTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(MusoptiTheme.mediumPadding)
            .background(MusoptiTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
        }
    }

    // MARK: - Helpers

    private func binding(for index: Int) -> Binding<WorkoutTemplateEntry> {
        Binding(
            get: { entries[index] },
            set: { entries[index] = $0 }
        )
    }

    private func addExercise(_ exercise: Exercise) {
        let entry = WorkoutTemplateEntry(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            targetSets: 3,
            targetReps: 10,
            order: entries.count
        )
        entries.append(entry)
    }

    private func reorderEntries() {
        for i in entries.indices {
            entries[i].order = i
        }
    }

    private func save() {
        reorderEntries()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if let existing = template {
            existing.name = trimmedName
            existing.exercises = entries
            existing.updatedAt = .now
        } else {
            let newTemplate = WorkoutTemplate(name: trimmedName, exercises: entries)
            modelContext.insert(newTemplate)
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Exercise Entry Row

private struct ExerciseEntryRow: View {
    @Environment(ExerciseCatalog.self) private var exerciseCatalog
    @Binding var entry: WorkoutTemplateEntry
    let onDelete: () -> Void

    private var linkedExercise: Exercise? {
        exerciseCatalog.exercise(id: entry.exerciseID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            HStack {
                HStack(spacing: 10) {
                    if let linkedExercise {
                        ExerciseIconView(exercise: linkedExercise, size: 40)
                    } else {
                        ExerciseIconView(symbolName: ExerciseCategory.custom.iconName, category: .custom, size: 40)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.exerciseName)
                            .font(MusoptiTheme.bodyText.weight(.semibold))
                            .foregroundStyle(MusoptiTheme.textPrimary)

                        if let linkedExercise {
                            Text(linkedExercise.equipmentDisplayName)
                                .font(MusoptiTheme.caption)
                                .foregroundStyle(MusoptiTheme.textSecondary)
                        }
                    }
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MusoptiTheme.textTertiary)
                }
            }

            HStack(spacing: MusoptiTheme.largePadding) {
                StepperRow(label: "Sets", value: $entry.targetSets, range: 1...10)
                StepperRow(label: "Reps", value: $entry.targetReps, range: 1...30)
            }
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }
}

// MARK: - Stepper Row

private struct StepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: MusoptiTheme.smallPadding) {
            Text(label)
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)

            Button {
                if value > range.lowerBound { value -= 1 }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(value > range.lowerBound ? MusoptiTheme.accent : MusoptiTheme.textTertiary)
            }

            Text("\(value)")
                .font(MusoptiTheme.bodyText.weight(.bold))
                .foregroundStyle(MusoptiTheme.textPrimary)
                .frame(minWidth: 24)

            Button {
                if value < range.upperBound { value += 1 }
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(value < range.upperBound ? MusoptiTheme.accent : MusoptiTheme.textTertiary)
            }
        }
    }
}

// MARK: - Template Exercise Picker

private struct TemplateExercisePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var searchText = ""

    let onSelect: (Exercise) -> Void

    var filteredExercises: [Exercise] {
        if searchText.isEmpty { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var groupedExercises: [(ExerciseCategory, [Exercise])] {
        let grouped = Dictionary(grouping: filteredExercises) { $0.category }
        return ExerciseCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MusoptiTheme.surfaceBackground.ignoresSafeArea()

                List {
                    ForEach(groupedExercises, id: \.0) { category, items in
                        Section {
                            ForEach(items) { exercise in
                                Button {
                                    onSelect(exercise)
                                    dismiss()
                                } label: {
                                    HStack(spacing: MusoptiTheme.smallPadding) {
                                        ExerciseIconView(exercise: exercise, size: 38)
                                        VStack(alignment: .leading) {
                                            Text(exercise.name)
                                                .font(MusoptiTheme.bodyText)
                                                .foregroundStyle(MusoptiTheme.textPrimary)
                                            Text("\(exercise.muscleGroup.capitalized) • \(exercise.equipmentDisplayName)")
                                                .font(MusoptiTheme.caption)
                                                .foregroundStyle(MusoptiTheme.textSecondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text(category.displayName)
                                .foregroundStyle(MusoptiTheme.textSecondary)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(MusoptiTheme.textSecondary)
                }
            }
        }
    }
}
