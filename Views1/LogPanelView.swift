import SwiftUI

struct LogPanelView: View {
    @EnvironmentObject var vm: JailbreakViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Log header
            HStack {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))

                Text("Лог")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                Text("\(vm.logs.count) записей")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))

                Button {
                    vm.clearLogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Очистить лог")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.windowBackgroundColor))

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(vm.logs) { entry in
                            LogLineView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .onChange(of: vm.logs.count) {
                    if let last = vm.logs.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(.textBackgroundColor))
            .font(.system(size: 11, design: .monospaced))
        }
    }
}

// MARK: - Log Line

struct LogLineView: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Timestamp
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .foregroundColor(.white.opacity(0.2))
                .frame(width: 55, alignment: .leading)

            // Level badge
            Text(entry.level.rawValue)
                .foregroundColor(levelColor)
                .frame(width: 32, alignment: .center)

            // Message
            Text(entry.message)
                .foregroundColor(messageColor)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
    }

    private var levelColor: Color {
        switch entry.level {
        case .info:    return .cyan.opacity(0.6)
        case .success: return .green
        case .warning: return .yellow
        case .error:   return .red
        case .debug:   return .white.opacity(0.25)
        case .command: return .purple.opacity(0.8)
        }
    }

    private var messageColor: Color {
        switch entry.level {
        case .error:   return .red.opacity(0.9)
        case .success: return .green.opacity(0.9)
        case .debug:   return .white.opacity(0.4)
        default:       return .white.opacity(0.7)
        }
    }
}
