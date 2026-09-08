import SwiftUI

struct StepsSidebarView: View {
    @EnvironmentObject var vm: JailbreakViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Steps list
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(JailbreakStep.allCases) { step in
                        StepRowView(
                            step: step,
                            status: vm.stepStatuses[step] ?? .pending,
                            isSelected: vm.currentStep == step
                        )
                        .onTapGesture {
                            vm.currentStep = step
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer()

            // Bottom: Start button
            VStack(spacing: 8) {
                Divider()
                    .background(Color.white.opacity(0.1))

                Button {
                    Task { await vm.startJailbreak() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: vm.isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 12))
                        Text(vm.isRunning ? "Выполняется…" : "Запустить всё")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(vm.isRunning ? Color.orange : Color.cyan)
                    )
                    .foregroundColor(.black)
                }
                .buttonStyle(.plain)
                .disabled(vm.isRunning)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }
}

// MARK: - Step Row

struct StepRowView: View {
    let step: JailbreakStep
    let status: StepStatus
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                statusIcon
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))

                Text(step.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.06) : .clear)
        )
        .padding(.horizontal, 6)
    }

    private var statusColor: Color {
        switch status {
        case .pending:    return .gray
        case .active:     return .cyan
        case .running:    return .orange
        case .success:    return .green
        case .failure:    return .red
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
        case .active:
            Image(systemName: step.icon)
        case .running:
            ProgressView()
                .scaleEffect(0.5)
                .tint(.orange)
        case .success:
            Image(systemName: "checkmark")
        case .failure:
            Image(systemName: "xmark")
        }
    }
}
