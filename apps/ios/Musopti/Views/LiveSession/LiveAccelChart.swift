import SwiftUI
import Charts

struct LiveAccelChart: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        let samples = sessionManager.liveAccelHistory
        let now = Date.now
        let windowStart = now.addingTimeInterval(-5)

        VStack {
            if samples.isEmpty {
                emptyChart
            } else {
                Chart {
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Magnitude", Double(sample.magnitude))
                        )
                        .foregroundStyle(MusoptiTheme.accent)
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(phaseTransitions(in: samples)) { sample in
                        PointMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Magnitude", Double(sample.magnitude))
                        )
                        .foregroundStyle(MusoptiTheme.phaseColor(for: sample.phase))
                        .symbolSize(30)
                    }
                }
                .chartXScale(domain: windowStart ... now)
                .chartYScale(domain: 0.0 ... 1.0)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                            .foregroundStyle(MusoptiTheme.textTertiary)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(MusoptiTheme.surfaceBackground.opacity(0.5))
                }
            }
        }
        .frame(height: 200)
        .padding(MusoptiTheme.smallPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var emptyChart: some View {
        VStack(spacing: MusoptiTheme.smallPadding) {
            Image(systemName: "waveform.path")
                .font(.system(size: 32))
                .foregroundStyle(MusoptiTheme.textTertiary)
            Text("Waiting for data...")
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func phaseTransitions(in samples: [AccelSample]) -> [AccelSample] {
        guard samples.count > 1 else { return [] }
        var transitions: [AccelSample] = []
        for i in 1..<samples.count {
            if samples[i].phase != samples[i - 1].phase {
                transitions.append(samples[i])
            }
        }
        return transitions
    }
}
