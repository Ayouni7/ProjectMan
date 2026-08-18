import SwiftUI

enum Palette {
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let paper = Color(red: 0.97, green: 0.95, blue: 0.93)
    static let coral = Color(red: 0.89, green: 0.24, blue: 0.16)
    static let teal = Color(red: 0.11, green: 0.47, blue: 0.45)
    static let sand = Color(red: 0.93, green: 0.89, blue: 0.82)
    static let mist = Color(red: 0.88, green: 0.90, blue: 0.89)
}

struct StatusBadge: View {
    var status: TaskStatus

    var color: Color {
        switch status {
        case .todo: .secondary
        case .inProgress: Palette.teal
        case .done: .green
        case .blocked: Palette.coral
        case .dropped: .secondary
        }
    }

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct CaptureStatusBadge: View {
    var status: CaptureStatus

    var color: Color {
        switch status {
        case .queued: .secondary
        case .processing: Palette.teal
        case .review: .orange
        case .filed: .green
        case .failed: Palette.coral
        }
    }

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct MetricCard: View {
    var title: String
    var value: String
    var subtitle: String? = nil
    var tint: Color = Palette.teal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Text(value)
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}

struct LevelMeter: View {
    var level: Float

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<16, id: \.self) { index in
                let threshold = Float(index) / 16
                Capsule()
                    .fill(level > threshold ? Palette.coral : Palette.mist)
                    .frame(width: 6, height: 8 + CGFloat(index) * 2.2)
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityLabel("Audio level")
    }
}

struct RecordButton: View {
    var isRecording: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Palette.coral.opacity(isRecording ? 0.18 : 0.12))
                    .frame(width: 168, height: 168)
                Circle()
                    .stroke(Palette.coral.opacity(0.35), lineWidth: 3)
                    .frame(width: 148, height: 148)
                RoundedRectangle(cornerRadius: isRecording ? 10 : 40, style: .continuous)
                    .fill(Palette.coral)
                    .frame(width: isRecording ? 42 : 78, height: isRecording ? 42 : 78)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .animation(.spring(duration: 0.28), value: isRecording)
    }
}

extension Date {
    var shortStamp: String {
        formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

extension Double {
    var percentLabel: String {
        "\(Int((self * 100).rounded()))%"
    }
}
