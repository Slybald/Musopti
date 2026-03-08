import SwiftUI

struct RepCounterView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        VStack(spacing: 4) {
            Text("\(sessionManager.currentSetReps)")
                .font(MusoptiTheme.repCounter)
                .foregroundStyle(MusoptiTheme.textPrimary)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.4, bounce: 0.3), value: sessionManager.currentSetReps)

            Text("reps")
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
                .textCase(.uppercase)

            Text("Set \(currentSetNumber)")
                .font(MusoptiTheme.bodyText)
                .foregroundStyle(MusoptiTheme.textSecondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MusoptiTheme.largePadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var currentSetNumber: Int {
        guard let session = sessionManager.activeSession,
              let exercise = sessionManager.currentExercise else {
            return 1
        }
        let completedSets = session.exercises
            .first(where: { $0.exerciseID == exercise.id })?
            .sets.count ?? 0
        return completedSets + 1
    }
}
