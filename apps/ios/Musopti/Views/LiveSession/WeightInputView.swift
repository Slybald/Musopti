import SwiftUI

struct WeightInputView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(SessionManager.self) private var sessionManager
    @State private var showWeightSheet = false
    @State private var weightInput: Double = 0

    var body: some View {
        Button {
            if let weightKg = sessionManager.currentWeightKg {
                weightInput = preferences.weightUnit == .kg ? weightKg : weightKg * 2.20462
            } else {
                weightInput = 0
            }
            showWeightSheet = true
        } label: {
            HStack {
                Text("Weight")
                    .font(MusoptiTheme.bodyText)
                    .foregroundStyle(MusoptiTheme.textPrimary)

                Spacer()

                HStack(spacing: 4) {
                    Text(weightText)
                        .font(MusoptiTheme.bodyText)
                        .foregroundStyle(MusoptiTheme.textPrimary)
                    Text(preferences.weightUnit.rawValue)
                        .font(MusoptiTheme.caption)
                        .foregroundStyle(MusoptiTheme.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(MusoptiTheme.textTertiary)
            }
            .padding(MusoptiTheme.mediumPadding)
            .background(MusoptiTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showWeightSheet) {
            weightSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(MusoptiTheme.cardBackground)
        }
    }

    private var weightText: String {
        if let kg = sessionManager.currentWeightKg {
            switch preferences.weightUnit {
            case .kg:
                return String(format: "%.1f", kg)
            case .lbs:
                return String(format: "%.1f", kg * 2.20462)
            }
        }
        return "--"
    }

    private var weightSheet: some View {
        NavigationStack {
            VStack(spacing: MusoptiTheme.largePadding) {
                Text(String(format: "%.1f %@", weightInput, preferences.weightUnit.rawValue))
                    .font(MusoptiTheme.repCounterSmall)
                    .foregroundStyle(MusoptiTheme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.3), value: weightInput)

                HStack(spacing: MusoptiTheme.mediumPadding) {
                    stepperButton(systemName: "minus", delta: largeStep * -1)
                    stepperButton(systemName: "minus", delta: smallStep * -1, small: true)
                    stepperButton(systemName: "plus", delta: smallStep, small: true)
                    stepperButton(systemName: "plus", delta: largeStep)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MusoptiTheme.cardBackground)
            .navigationTitle("Set Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let weightKg = preferences.weightUnit == .kg
                            ? weightInput
                            : weightInput / 2.20462
                        sessionManager.setWeight(weightKg)
                        showWeightSheet = false
                    }
                    .foregroundStyle(MusoptiTheme.accent)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showWeightSheet = false
                    }
                    .foregroundStyle(MusoptiTheme.textSecondary)
                }
            }
        }
    }

    private var smallStep: Double {
        preferences.weightUnit == .kg ? 0.5 : 1
    }

    private var largeStep: Double {
        preferences.weightUnit == .kg ? 2.5 : 5
    }

    private func stepperButton(
        systemName: String,
        delta: Double,
        small: Bool = false
    ) -> some View {
        Button {
            let newValue = weightInput + delta
            if newValue >= 0 {
                weightInput = newValue
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemName)
                    .font(.system(size: small ? 16 : 20, weight: .semibold))
                Text(String(format: "%.1f", abs(delta)))
                    .font(MusoptiTheme.caption)
            }
            .foregroundStyle(MusoptiTheme.textPrimary)
            .frame(width: small ? 56 : 72, height: 64)
            .background(MusoptiTheme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
