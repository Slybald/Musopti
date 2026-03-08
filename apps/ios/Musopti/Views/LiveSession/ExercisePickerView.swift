import SwiftUI

struct ExercisePickerView: View {
    @Environment(ExerciseCatalog.self) private var exerciseCatalog
    @Environment(SessionManager.self) private var sessionManager
    @Environment(BLEManager.self) private var bleManager

    @State private var selectedCategory: ExerciseCategory?
    @State private var searchText = ""

    private let gridColumns = [
        GridItem(.flexible(), spacing: MusoptiTheme.smallPadding),
        GridItem(.flexible(), spacing: MusoptiTheme.smallPadding),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            HStack {
                Text("Exercise")
                    .font(MusoptiTheme.sectionTitle)
                    .foregroundStyle(MusoptiTheme.textPrimary)
                Spacer()
                if let currentExercise = sessionManager.currentExercise {
                    Text(currentExercise.name)
                        .font(MusoptiTheme.caption)
                        .foregroundStyle(MusoptiTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            searchField
            categoryChips

            if let category = selectedCategory {
                exerciseGrid(for: category)
            }
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
        .onAppear {
            selectedCategory = sessionManager.currentExercise?.category ?? ExerciseCategory.allCases.first
        }
    }

    private var searchField: some View {
        HStack(spacing: MusoptiTheme.smallPadding) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MusoptiTheme.textSecondary)

            TextField("Search chest press, smith, row...", text: $searchText)
                .font(MusoptiTheme.bodyText)
                .foregroundStyle(MusoptiTheme.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MusoptiTheme.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MusoptiTheme.smallPadding) {
                ForEach(ExerciseCategory.allCases) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    } label: {
                        Label(category.displayName, systemImage: category.iconName)
                            .font(MusoptiTheme.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedCategory == category
                                    ? MusoptiTheme.accent
                                    : MusoptiTheme.surfaceBackground
                            )
                            .foregroundStyle(
                                selectedCategory == category
                                    ? Color.black
                                    : MusoptiTheme.textPrimary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func exerciseGrid(for category: ExerciseCategory) -> some View {
        let exercises = exerciseCatalog.exercises(for: category).filter { exercise in
            searchText.isEmpty
                || exercise.name.localizedCaseInsensitiveContains(searchText)
                || exercise.equipmentDisplayName.localizedCaseInsensitiveContains(searchText)
                || exercise.muscleGroup.localizedCaseInsensitiveContains(searchText)
        }

        return Group {
            if exercises.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.grid.2x2")
                        .font(.title3)
                        .foregroundStyle(MusoptiTheme.textTertiary)
                    Text("No matching exercises")
                        .font(MusoptiTheme.bodyText.weight(.semibold))
                        .foregroundStyle(MusoptiTheme.textSecondary)
                    Text("Try another keyword or category.")
                        .font(MusoptiTheme.caption)
                        .foregroundStyle(MusoptiTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, MusoptiTheme.largePadding)
            } else {
                LazyVGrid(columns: gridColumns, spacing: MusoptiTheme.smallPadding) {
                    ForEach(exercises, id: \.id) { exercise in
                        exerciseCard(exercise)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func exerciseCard(_ exercise: Exercise) -> some View {
        let isSelected = sessionManager.currentExercise?.id == exercise.id

        return Button {
            selectExercise(exercise)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    ExerciseIconView(exercise: exercise, size: 46)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(exercise.name)
                            .font(MusoptiTheme.bodyText.weight(.semibold))
                            .foregroundStyle(MusoptiTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(exercise.muscleGroup.capitalized)
                            .font(MusoptiTheme.caption)
                            .foregroundStyle(MusoptiTheme.textSecondary)

                        Text(exercise.equipmentDisplayName)
                            .font(MusoptiTheme.caption)
                            .foregroundStyle(MusoptiTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(MusoptiTheme.surfaceBackground)
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MusoptiTheme.smallPadding)
            .background(MusoptiTheme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius)
                    .stroke(isSelected ? MusoptiTheme.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func selectExercise(_ exercise: Exercise) {
        sessionManager.selectExercise(exercise)

        let profile = exercise.detectionProfile
        let config = MusoptiConfig(
            deviceMode: .detection,
            exerciseType: MusoptiExerciseType(rawValue: profile.firmwareExerciseType) ?? .generic,
            holdTargetMs: profile.holdTargetMs,
            holdToleranceMs: profile.holdToleranceMs,
            minRepDurationMs: profile.minRepDurationMs,
            sampleRateHz: 100
        )
        bleManager.writeConfig(config, verifyReadBack: true)
    }
}
