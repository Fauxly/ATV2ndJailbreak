import SwiftUI

struct StepDetailView: View {
    @EnvironmentObject var vm: JailbreakViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Step header
                HStack(spacing: 12) {
                    Image(systemName: vm.currentStep.icon)
                        .font(.system(size: 24))
                        .foregroundColor(.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.currentStep.title)
                            .font(.system(size: 18, weight: .semibold))
                        Text(vm.currentStep.subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Spacer()

                    // Run single step button
                    if vm.currentStep != .done {
                        Button {
                            Task { await vm.runSingleStep(vm.currentStep) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                                Text("Выполнить")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                            )
                            .foregroundColor(.cyan)
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.isRunning)
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                // Step-specific content
                stepContent
            }
            .padding(20)
        }
        .background(Color(.controlBackgroundColor))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch vm.currentStep {
        case .prepare:
            PrepareStepView()
        case .dfu:
            DFUStepView()
        case .boot:
            BootStepView()
        case .bootstrap:
            BootstrapStepView()
        case .packages:
            PackagesStepView()
        case .done:
            DoneStepView()
        }
    }
}

// MARK: - Prepare Step

struct PrepareStepView: View {
    @EnvironmentObject var vm: JailbreakViewModel
    @EnvironmentObject var compMgr: ComponentManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Components table
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Компоненты")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        Spacer()

                        // Download all missing
                        let missingCount = compMgr.components.filter { $0.status == .missing && $0.remoteURL != nil }.count
                        if missingCount > 0 {
                            Button {
                                Task { await compMgr.downloadAllMissing() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Скачать (\(missingCount))")
                                }
                                .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(compMgr.isDownloading)
                        }
                    }

                    ForEach(compMgr.components) { comp in
                        HStack(spacing: 8) {
                            // Status icon
                            Image(systemName: statusIcon(comp.status))
                                .foregroundColor(statusColor(comp.status))
                                .font(.system(size: 13))

                            Text(comp.name)
                                .font(.system(size: 12))

                            Spacer()

                            // Size
                            if comp.isReady {
                                Text(comp.size)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            // Status badge
                            Text(comp.statusLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(statusColor(comp.status))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(statusColor(comp.status).opacity(0.12))
                                .cornerRadius(4)

                            // Actions for missing components
                            if comp.status == .missing {
                                if comp.remoteURL != nil {
                                    Button {
                                        Task { await compMgr.downloadComponent(id: comp.id) }
                                    } label: {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Скачать")
                                }

                                Button {
                                    importFile(for: comp.id)
                                } label: {
                                    Image(systemName: "folder")
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                                .help("Выбрать файл")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(4)
            }

            HStack {
                Button {
                    compMgr.scanAll()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Перепроверить")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                if compMgr.allReady {
                    Label("Всё готово", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
            }

            // usbliter8 flash section
            UF2FlashWizardView()
        }
    }

    private func importFile(for id: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        if panel.runModal() == .OK, let url = panel.url {
            try? compMgr.importFile(for: id, from: url)
        }
    }

    private func statusIcon(_ s: ComponentManager.Component.Status) -> String {
        switch s {
        case .bundled:      return "shippingbox.fill"
        case .cached:       return "checkmark.circle.fill"
        case .downloading:  return "arrow.down.circle"
        case .missing:      return "xmark.circle"
        case .error:        return "exclamationmark.triangle"
        case .unknown:      return "questionmark.circle"
        }
    }

    private func statusColor(_ s: ComponentManager.Component.Status) -> Color {
        switch s {
        case .bundled:      return .blue
        case .cached:       return .green
        case .downloading:  return .orange
        case .missing:      return .red
        case .error:        return .red
        case .unknown:      return .gray
        }
    }
}

// MARK: - DFU Step

struct DFUStepView: View {
    @EnvironmentObject var vm: JailbreakViewModel
    @EnvironmentObject var usbMonitor: USBMonitor
    @EnvironmentObject var compMgr: ComponentManager
    @State private var autoStartTriggered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoCard(
                icon: "cable.connector",
                title: "Подключите Apple TV",
                lines: [
                    "1. Подключите DCSD кабель → ввод в DFU",
                    "2. Отсоедините DCSD от Apple TV",
                    "3. Подключите Waveshare RP2350 (usbliter8)",
                    "4. Прошивка начнётся автоматически",
                ]
            )

            // Live USB status card
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(usbMonitor.isDFUConnected ? .green : .red.opacity(0.4))
                                .frame(width: 12, height: 12)

                            if !usbMonitor.isDFUConnected {
                                Circle()
                                    .stroke(.red.opacity(0.3), lineWidth: 2)
                                    .frame(width: 20, height: 20)
                                    .scaleEffect(1.3)
                                    .opacity(0.5)
                                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: usbMonitor.isDFUConnected)
                            }
                        }
                        .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(usbMonitor.deviceLabel)
                                .font(.system(size: 13, weight: .medium))

                            if usbMonitor.isDFUConnected {
                                Text("VID: 05AC  PID: 1227 — Готов к прошивке")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.green)
                            } else {
                                Text("Ожидание USB DFU устройства…")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Text(usbMonitor.isDFUConnected ? "DFU" : "—")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(usbMonitor.isDFUConnected ? .green : .gray)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                (usbMonitor.isDFUConnected ? Color.green : Color.gray)
                                    .opacity(0.12)
                            )
                            .cornerRadius(4)
                    }

                    if !usbMonitor.ecid.isEmpty {
                        HStack(spacing: 4) {
                            Text("ECID:")
                                .foregroundColor(.secondary)
                            Text(usbMonitor.ecid)
                        }
                        .font(.system(size: 10, design: .monospaced))
                    }
                }
                .padding(4)
            }
            .onAppear {
                usbMonitor.startMonitoring()
            }
            .onChange(of: usbMonitor.isDFUConnected) {
                if usbMonitor.isDFUConnected && !autoStartTriggered {
                    autoStartTriggered = true
                    vm.device.isInDFU = true
                    vm.log("DFU обнаружен — запуск boot chain…", level: .success)
                    vm.completeStep(.dfu)
                    Task {
                        await vm.runBootChain()
                    }
                }
            }

            // Manual button as fallback
            if usbMonitor.isDFUConnected && autoStartTriggered {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Boot chain запускается…")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Boot Step

struct BootStepView: View {
    @EnvironmentObject var vm: JailbreakViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoCard(
                icon: "cpu",
                title: "Boot Chain",
                lines: [
                    "iBSS (patched) → USB exploit → PongoOS",
                    "KPF патчит ядро → palera1n Loader",
                    "Результат: YOLO:checkra1n на USB",
                ]
            )

            if case .running = vm.stepStatuses[.boot] {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.orange)
                    Text("Boot chain выполняется…")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Bootstrap Step

struct BootstrapStepView: View {
    @EnvironmentObject var vm: JailbreakViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoCard(
                icon: "shippingbox",
                title: "Bootstrap",
                lines: [
                    "Источник: apt.procurs.us/bootstraps/1900/",
                    "Устанавливается через SSH в preboot",
                    "Rootless: /var/jb/ → preboot symlink",
                ]
            )

            // SSH config
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SSH Настройки")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Хост")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                            TextField("IP адрес", text: $vm.sshConfig.host)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 140)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Порт")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                            TextField("44", value: $vm.sshConfig.port, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 60)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Пользователь")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                            TextField("root", text: $vm.sshConfig.username)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 80)
                        }
                    }

                    Toggle("Использовать SSH ключ", isOn: $vm.sshConfig.useKey)
                        .font(.system(size: 12))
                        .toggleStyle(.checkbox)

                    if vm.sshConfig.useKey {
                        HStack {
                            TextField("Путь к ключу", text: $vm.sshConfig.keyPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))

                            Button("…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.allowedContentTypes = [.data]
                                if panel.runModal() == .OK, let url = panel.url {
                                    vm.sshConfig.keyPath = url.path
                                }
                            }
                            .frame(width: 28)
                        }
                    }
                }
                .padding(4)
            }
        }
    }
}

// MARK: - Packages Step

struct PackagesStepView: View {
    @EnvironmentObject var vm: JailbreakViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoCard(
                icon: "square.stack.3d.up",
                title: "Пакеты",
                lines: [
                    "Pyra (com.fauxly.pyra) → /var/jb/Applications/",
                    "Architecture: iphoneos-arm64",
                    "Устанавливается через dpkg + ручное копирование",
                ]
            )

            if case .running = vm.stepStatuses[.packages] {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.orange)
                    Text("Установка пакетов…")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Done Step

struct DoneStepView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Джейлбрейк завершён!")
                .font(.system(size: 20, weight: .semibold))

            Text("Apple TV 4K 2nd Gen готов к работе.\nPyra установлена и доступна.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Reusable Info Card

struct InfoCard: View {
    let icon: String
    let title: String
    let lines: [String]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundColor(.cyan.opacity(0.7))
                        .font(.system(size: 13))
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(4)
        }
    }
}
