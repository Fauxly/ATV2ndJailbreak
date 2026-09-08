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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Directory picker
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Папка проекта")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    HStack {
                        Text(vm.toolsDirectory)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button("Обзор…") {
                            vm.browseDirectory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(4)
            }

            // Components table
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Компоненты")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    ForEach(vm.components) { comp in
                        HStack(spacing: 8) {
                            Image(systemName: comp.isPresent ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundColor(comp.isPresent ? .green : .red.opacity(0.6))
                                .font(.system(size: 13))

                            Text(comp.name)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))

                            Spacer()

                            Text(comp.filename)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(4)
            }

            Button {
                vm.checkComponents()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Перепроверить")
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - DFU Step

struct DFUStepView: View {
    @EnvironmentObject var vm: JailbreakViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoCard(
                icon: "cable.connector",
                title: "Подключите Apple TV",
                lines: [
                    "1. Подключите DCSD кабель к Apple TV (Lightning)",
                    "2. Используйте Foxlink X892 адаптер (скрытый порт под Ethernet)",
                    "3. Подключите Waveshare RP2350 USB-A с usbliter8",
                    "4. Apple TV должен перейти в DFU автоматически",
                ]
            )

            HStack(spacing: 12) {
                // Device status
                HStack(spacing: 8) {
                    Circle()
                        .fill(vm.device.isInDFU ? .green : .red.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(vm.device.isInDFU ? "DFU обнаружен" : "DFU не найден")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Button {
                    Task { await vm.detectDFU() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("Найти DFU")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vm.isRunning)
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
