import SwiftUI
import SwiftData

struct CustomExerciseEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Exercise> { !$0.isBuiltIn },
           sort: \Exercise.name)
    private var customExercises: [Exercise]

    @State private var showAddSheet = false
    @State private var editingExercise: Exercise?

    var body: some View {
        Group {
            if customExercises.isEmpty {
                ContentUnavailableView {
                    Label("No Custom Exercises", systemImage: "figure.strengthtraining.traditional")
                } description: {
                    Text("Create custom exercises with personalized detection profiles.")
                } actions: {
                    Button("Add Exercise") {
                        showAddSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MusoptiTheme.accent)
                }
            } else {
                List {
                    ForEach(customExercises) { exercise in
                        Button {
                            editingExercise = exercise
                        } label: {
                            ExerciseRow(exercise: exercise)
                        }
                        .listRowBackground(MusoptiTheme.cardBackground)
                    }
                    .onDelete(perform: deleteExercises)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Custom Exercises")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .tint(MusoptiTheme.accent)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ExerciseFormView(mode: .add) { name, category, equipment, profile in
                addExercise(name: name, category: category, equipment: equipment, profile: profile)
            }
        }
        .sheet(item: $editingExercise) { exercise in
            ExerciseFormView(
                mode: .edit(exercise)
            ) { name, category, equipment, profile in
                updateExercise(exercise, name: name, category: category, equipment: equipment, profile: profile)
            }
        }
    }

    private func deleteExercises(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(customExercises[index])
        }
        try? modelContext.save()
    }

    private func addExercise(name: String, category: ExerciseCategory, equipment: String, profile: DetectionProfile) {
        let exercise = Exercise(
            name: name,
            category: category,
            muscleGroup: category.displayName,
            equipmentType: equipment,
            isBuiltIn: false,
            iconName: Exercise.defaultIconName(for: category),
            detectionProfile: profile
        )
        modelContext.insert(exercise)
        try? modelContext.save()
    }

    private func updateExercise(_ exercise: Exercise, name: String, category: ExerciseCategory, equipment: String, profile: DetectionProfile) {
        exercise.name = name
        exercise.category = category
        exercise.equipmentType = equipment
        exercise.iconName = Exercise.defaultIconName(for: category)
        exercise.detectionProfile = profile
        try? modelContext.save()
    }
}

// MARK: - Exercise Row

private struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack {
            ExerciseIconView(exercise: exercise, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(MusoptiTheme.phaseLabel)
                    .foregroundStyle(MusoptiTheme.textPrimary)
                HStack(spacing: 8) {
                    Text(exercise.category.displayName)
                    if !exercise.equipmentType.isEmpty {
                        Text("·")
                        Text(exercise.equipmentDisplayName)
                    }
                }
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(MusoptiTheme.textTertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Exercise Form

enum ExerciseFormMode: Identifiable {
    case add
    case edit(Exercise)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let ex): return ex.id.uuidString
        }
    }
}

private struct ExerciseFormView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: ExerciseFormMode
    let onSave: (String, ExerciseCategory, String, DetectionProfile) -> Void

    @State private var name: String = ""
    @State private var category: ExerciseCategory = .custom
    @State private var equipmentType: String = ""
    @State private var requireHold: Bool = false
    @State private var holdTargetMs: Double = 3000
    @State private var holdToleranceMs: Double = 200
    @State private var minRepDurationMs: Double = 600

    private let equipmentOptions = ["Barbell", "Dumbbell", "Machine", "Smith Machine", "Cable", "Bodyweight", "Kettlebell", "Other"]

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Exercise Name", text: $name)

                    Picker("Category", selection: $category) {
                        ForEach(ExerciseCategory.allCases) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }

                    Picker("Equipment", selection: $equipmentType) {
                        Text("None").tag("")
                        ForEach(equipmentOptions, id: \.self) { eq in
                            Text(eq).tag(eq)
                        }
                    }
                }

                Section("Detection Profile") {
                    Toggle("Require Hold", isOn: $requireHold)

                    if requireHold {
                        VStack(alignment: .leading) {
                            Text("Hold Target: \(Int(holdTargetMs))ms")
                                .font(MusoptiTheme.caption)
                            Slider(value: $holdTargetMs, in: 500...10000, step: 100)
                                .tint(MusoptiTheme.accent)
                        }

                        VStack(alignment: .leading) {
                            Text("Hold Tolerance: \(Int(holdToleranceMs))ms")
                                .font(MusoptiTheme.caption)
                            Slider(value: $holdToleranceMs, in: 50...1000, step: 50)
                                .tint(MusoptiTheme.accent)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Min Rep Duration: \(Int(minRepDurationMs))ms")
                            .font(MusoptiTheme.caption)
                        Slider(value: $minRepDurationMs, in: 200...5000, step: 100)
                            .tint(MusoptiTheme.accent)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Exercise" : "New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let profile = DetectionProfile(
                            firmwareExerciseType: UInt8(MusoptiExerciseType.custom.rawValue),
                            requireHold: requireHold,
                            holdTargetMs: UInt16(holdTargetMs),
                            holdToleranceMs: UInt16(holdToleranceMs),
                            minRepDurationMs: UInt16(minRepDurationMs)
                        )
                        onSave(name, category, equipmentType, profile)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(MusoptiTheme.accent)
                }
            }
            .onAppear {
                if case .edit(let exercise) = mode {
                    name = exercise.name
                    category = exercise.category
                    equipmentType = exercise.equipmentType
                    requireHold = exercise.detectionProfile.requireHold
                    holdTargetMs = Double(exercise.detectionProfile.holdTargetMs)
                    holdToleranceMs = Double(exercise.detectionProfile.holdToleranceMs)
                    minRepDurationMs = Double(exercise.detectionProfile.minRepDurationMs)
                }
            }
        }
    }
}
