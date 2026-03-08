import SwiftUI
import SwiftData

struct WorkoutsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ExerciseCatalog.self) private var exerciseCatalog
    @Environment(SessionManager.self) private var sessionManager
    @Environment(BLEManager.self) private var bleManager
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkoutTemplate.updatedAt, order: .reverse) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var showTemplateEditor = false
    @State private var editingTemplate: WorkoutTemplate?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MusoptiTheme.largePadding) {
                    if sessionManager.isSessionActive {
                        currentSessionCard
                    }

                    freeformButton
                    templatesSection
                }
                .padding(.horizontal, MusoptiTheme.mediumPadding)
                .padding(.top, MusoptiTheme.mediumPadding)
                .padding(.bottom, MusoptiTheme.largePadding)
            }
            .background(MusoptiTheme.surfaceBackground)
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingTemplate = nil
                        showTemplateEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(MusoptiTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showTemplateEditor) {
                TemplateEditorView(template: editingTemplate)
            }
        }
    }

    // MARK: - Current Session

    @ViewBuilder
    private var currentSessionCard: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            HStack {
                Text("Current Session")
                    .font(MusoptiTheme.sectionTitle)
                    .foregroundStyle(MusoptiTheme.textPrimary)
                Spacer()
                Text(sessionManager.activeSession?.templateName ?? "Freeform")
                    .font(MusoptiTheme.caption.weight(.semibold))
                    .foregroundStyle(MusoptiTheme.textSecondary)
            }

            if let currentExercise = sessionManager.currentExercise {
                HStack(spacing: 12) {
                    ExerciseIconView(exercise: currentExercise, size: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentExercise.name)
                            .font(MusoptiTheme.bodyText.weight(.semibold))
                            .foregroundStyle(MusoptiTheme.textPrimary)

                        Text("\(currentExercise.category.displayName) • \(currentExercise.equipmentDisplayName)")
                            .font(MusoptiTheme.caption)
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
            } else {
                Text("No exercise selected yet")
                    .font(MusoptiTheme.bodyText.weight(.semibold))
                    .foregroundStyle(MusoptiTheme.textPrimary)
            }

            HStack(spacing: MusoptiTheme.mediumPadding) {
                Label("\(sessionManager.activeSession?.totalSets ?? 0) sets", systemImage: "repeat")
                Label("\(sessionManager.activeSession?.totalReps ?? 0) reps", systemImage: "number")
                if let session = sessionManager.activeSession,
                   let template = templates.first(where: { $0.id == session.templateID }) {
                    NavigationLink {
                        GuidedWorkoutView(template: template)
                    } label: {
                        Text("Workout Guide")
                            .font(MusoptiTheme.caption.weight(.semibold))
                            .foregroundStyle(MusoptiTheme.accent)
                    }
                }
            }
            .font(MusoptiTheme.caption)
            .foregroundStyle(MusoptiTheme.textSecondary)

            Button {
                router.navigateToSession()
            } label: {
                Text("Open Session")
                    .font(MusoptiTheme.bodyText.weight(.semibold))
                    .foregroundStyle(MusoptiTheme.surfaceBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MusoptiTheme.smallPadding)
                    .background(MusoptiTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    // MARK: - Freeform

    private var freeformButton: some View {
        Button {
            if sessionManager.isSessionActive {
                router.navigateToSession()
            } else {
                sessionManager.startSession(template: nil)
                router.navigateToSession()
            }
        } label: {
            HStack(spacing: MusoptiTheme.smallPadding) {
                Image(systemName: "bolt.fill")
                    .font(.title3)
                Text(sessionManager.isSessionActive ? "Resume Session" : "Start Freeform Session")
                    .font(MusoptiTheme.sectionTitle)
            }
            .foregroundStyle(MusoptiTheme.surfaceBackground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MusoptiTheme.mediumPadding)
            .background(MusoptiTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Templates

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            Text("My Workouts")
                .font(MusoptiTheme.sectionTitle)
                .foregroundStyle(MusoptiTheme.textPrimary)

            if templates.isEmpty {
                emptyTemplatesView
            } else {
                ForEach(templates) { template in
                    TemplateCardView(
                        template: template,
                        startingExercise: startingExercise(for: template),
                        lastUsedAt: lastUsedDate(for: template),
                        onStart: { startTemplate(template) },
                        onOpenGuide: { router.navigateToSession() },
                        onEdit: {
                            editingTemplate = template
                            showTemplateEditor = true
                        },
                        onDelete: { deleteTemplate(template) },
                        isDisabled: sessionManager.isSessionActive && sessionManager.activeSession?.templateID != template.id
                    )
                }
            }
        }
    }

    private var emptyTemplatesView: some View {
        VStack(spacing: MusoptiTheme.smallPadding) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 36))
                .foregroundStyle(MusoptiTheme.textTertiary)
            Text("No workout templates yet")
                .font(MusoptiTheme.bodyText)
                .foregroundStyle(MusoptiTheme.textSecondary)
            Text("Tap + to create one")
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MusoptiTheme.largePadding * 2)
    }

    // MARK: - Actions

    private func startTemplate(_ template: WorkoutTemplate) {
        guard !sessionManager.isSessionActive else {
            router.navigateToSession()
            return
        }

        sessionManager.startSession(template: template)

        if let firstEntry = template.exercises.sorted(by: { $0.order < $1.order }).first,
           let firstExercise = exerciseCatalog.exercise(id: firstEntry.exerciseID) {
            sessionManager.selectExercise(firstExercise)

            let profile = firstExercise.detectionProfile
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

        router.navigateToSession()
    }

    private func deleteTemplate(_ template: WorkoutTemplate) {
        modelContext.delete(template)
        try? modelContext.save()
    }

    private func lastUsedDate(for template: WorkoutTemplate) -> Date? {
        sessions.first(where: { $0.templateID == template.id })?.startedAt
    }

    private func startingExercise(for template: WorkoutTemplate) -> Exercise? {
        guard let firstEntry = template.exercises.sorted(by: { $0.order < $1.order }).first else {
            return nil
        }
        return exerciseCatalog.exercise(id: firstEntry.exerciseID)
    }
}

private struct TemplateCardView: View {
    let template: WorkoutTemplate
    let startingExercise: Exercise?
    let lastUsedAt: Date?
    let onStart: () -> Void
    let onOpenGuide: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(MusoptiTheme.bodyText.weight(.semibold))
                        .foregroundStyle(MusoptiTheme.textPrimary)

                    Text("\(template.exercises.count) exercises • \(totalSets) sets • \(targetReps) target reps")
                        .font(MusoptiTheme.caption)
                        .foregroundStyle(MusoptiTheme.textSecondary)

                    Text(lastUsedAt.map { "Last used \($0.shortRelativeTimestamp)" } ?? "Never used")
                        .font(MusoptiTheme.caption)
                        .foregroundStyle(MusoptiTheme.textTertiary)
                }

                Spacer()

                Button(isDisabled ? "Active" : "Start", action: onStart)
                    .font(MusoptiTheme.bodyText.weight(.semibold))
                    .foregroundStyle(isDisabled ? MusoptiTheme.textSecondary : MusoptiTheme.surfaceBackground)
                    .padding(.horizontal, MusoptiTheme.mediumPadding)
                    .padding(.vertical, MusoptiTheme.smallPadding)
                    .background(isDisabled ? MusoptiTheme.surfaceBackground : MusoptiTheme.accent)
                    .clipShape(Capsule())
                    .disabled(isDisabled)
            }

            if let startingExercise {
                HStack(spacing: 10) {
                    ExerciseIconView(exercise: startingExercise, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Starts with \(startingExercise.name)")
                            .font(MusoptiTheme.caption.weight(.semibold))
                            .foregroundStyle(MusoptiTheme.textPrimary)

                        Text(startingExercise.equipmentDisplayName)
                            .font(MusoptiTheme.caption)
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
            } else if let nextExercise = template.exercises.sorted(by: { $0.order < $1.order }).first {
                Text("Starts with \(nextExercise.exerciseName)")
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(MusoptiTheme.textSecondary)
            }
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
        .contextMenu {
            Button { onOpenGuide() } label: {
                Label("Open Session", systemImage: "figure.run")
            }
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var totalSets: Int {
        template.exercises.reduce(0) { $0 + $1.targetSets }
    }

    private var targetReps: Int {
        template.exercises.reduce(0) { $0 + ($1.targetSets * $1.targetReps) }
    }
}
