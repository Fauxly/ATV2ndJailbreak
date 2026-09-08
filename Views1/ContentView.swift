import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: JailbreakViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Title bar area
            TitleBarView()

            Divider()

            // Main content
            HStack(spacing: 0) {
                // Left: Steps sidebar
                StepsSidebarView()
                    .frame(width: 220)

                Divider()

                // Center: Active step detail
                VStack(spacing: 0) {
                    StepDetailView()
                        .frame(maxHeight: .infinity)

                    if vm.showLogPanel {
                        Divider()

                        LogPanelView()
                            .frame(height: 180)
                    }
                }
            }
        }
    }
}

// MARK: - Title Bar

struct TitleBarView: View {
    @EnvironmentObject var vm: JailbreakViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Draggable area for custom title bar
            Color.clear
                .frame(width: 72, height: 1)

            Image(systemName: "tv")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.cyan)

            Text("ATV2nd Jailbreak")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)

            Text("AppleTV11,1 · A12")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            Spacer()

            // Progress indicator
            if vm.isRunning {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.cyan)
            }

            Text("\(Int(vm.overallProgress * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.7))

            // Toggle log panel
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.showLogPanel.toggle()
                }
            } label: {
                Image(systemName: vm.showLogPanel ? "rectangle.bottomhalf.filled" : "rectangle.bottomhalf.inset.filled")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Показать/скрыть лог")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview {
    ContentView()
        .environmentObject(JailbreakViewModel())
}
