import Foundation
import SwiftUI
import Combine

@MainActor
class JailbreakViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentStep: JailbreakStep = .prepare
    @Published var stepStatuses: [JailbreakStep: StepStatus] = {
        var d = [JailbreakStep: StepStatus]()
        for s in JailbreakStep.allCases { d[s] = .pending }
        return d
    }()

    @Published var logs: [LogEntry] = []
    @Published var device = DeviceInfo()
    @Published var sshConfig = SSHConfig()
    @Published var components: [ComponentInfo] = []
    @Published var isRunning = false
    @Published var overallProgress: Double = 0
    @Published var showLogPanel = true

    // MARK: - Paths

    @Published var toolsDirectory: String = ""
    @Published var componentsDirectory: String = ""

    private var processRunner = ProcessRunner()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("atv2nd-jailbreak")
            .path
        toolsDirectory = defaultPath
        componentsDirectory = defaultPath + "/components"

        initComponents()
    }

    private func initComponents() {
        components = [
            ComponentInfo(name: "usbliter8 Firmware", filename: "usbliter8.uf2"),
            ComponentInfo(name: "iBSS (patched)", filename: "iBSS.patched"),
            ComponentInfo(name: "PongoOS", filename: "Pongo.bin"),
            ComponentInfo(name: "KPF Module", filename: "checkra1n-kpf-pongo"),
            ComponentInfo(name: "palera1n Loader", filename: "ramdisk.dmg"),
            ComponentInfo(name: "Bootstrap", filename: "bootstrap-ssh-iphoneos-arm64.tar.zst"),
            ComponentInfo(name: "Pyra.deb", filename: "com.fauxly.pyra.deb"),
        ]
    }

    // MARK: - Logging

    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        logs.append(entry)
    }

    func clearLogs() {
        logs.removeAll()
    }

    // MARK: - Step Navigation

    func setStep(_ step: JailbreakStep) {
        currentStep = step
        stepStatuses[step] = .active
    }

    func completeStep(_ step: JailbreakStep) {
        stepStatuses[step] = .success
        overallProgress = Double(step.rawValue + 1) / Double(JailbreakStep.allCases.count)
        if let next = JailbreakStep(rawValue: step.rawValue + 1) {
            setStep(next)
        }
    }

    func failStep(_ step: JailbreakStep, error: String) {
        stepStatuses[step] = .failure(error)
        isRunning = false
        log(error, level: .error)
    }

    // MARK: - Prepare: Check Components

    func checkComponents() {
        log("Проверка компонентов…", level: .info)
        let fm = FileManager.default

        for i in components.indices {
            let path = componentsDirectory + "/" + components[i].filename
            components[i].isPresent = fm.fileExists(atPath: path)
            components[i].path = path
            let status = components[i].isPresent ? "✓" : "✗"
            let level: LogEntry.LogLevel = components[i].isPresent ? .success : .warning
            log("  \(status) \(components[i].name)", level: level)
        }

        let allPresent = components.allSatisfy { $0.isPresent }
        if allPresent {
            log("Все компоненты найдены", level: .success)
        } else {
            log("Некоторые компоненты отсутствуют", level: .warning)
        }
    }

    // MARK: - Browse for Directory

    func browseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        panel.message = "Выберите папку atv2nd-jailbreak"

        if panel.runModal() == .OK, let url = panel.url {
            toolsDirectory = url.path
            componentsDirectory = url.path + "/components"
            log("Папка проекта: \(toolsDirectory)", level: .info)
            checkComponents()
        }
    }

    // MARK: - Run Shell Command

    func runCommand(_ command: String, label: String? = nil) async throws -> String {
        let displayLabel = label ?? command.prefix(60).description
        log("▶ \(displayLabel)", level: .command)

        return try await withCheckedThrowingContinuation { continuation in
            processRunner.run(
                command: command,
                currentDirectory: toolsDirectory,
                onOutput: { [weak self] line in
                    Task { @MainActor in
                        self?.log("  \(line)", level: .debug)
                    }
                },
                onComplete: { result in
                    switch result {
                    case .success(let output):
                        continuation.resume(returning: output)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            )
        }
    }

    // MARK: - Full Jailbreak Flow

    func startJailbreak() async {
        guard !isRunning else { return }
        isRunning = true
        clearLogs()
        log("═══ ATV2nd Jailbreak ═══", level: .info)
        log("Цель: AppleTV11,1 (A12 / T8020)", level: .info)

        // Step 1: Prepare
        setStep(.prepare)
        stepStatuses[.prepare] = .running
        checkComponents()
        let allPresent = components.allSatisfy { $0.isPresent }
        if !allPresent {
            failStep(.prepare, error: "Не все компоненты найдены. Проверьте папку.")
            return
        }
        completeStep(.prepare)

        // Step 2: DFU — user must do manually
        setStep(.dfu)
        stepStatuses[.dfu] = .active
        log("Переведите Apple TV в DFU через DCSD кабель", level: .warning)
        log("Ожидание DFU устройства…", level: .info)
        // DFU detection runs via polling — user clicks "Detect DFU" or it auto-detects
    }

    func detectDFU() async {
        stepStatuses[.dfu] = .running
        log("Поиск DFU устройства…", level: .info)

        do {
            let output = try await runCommand(
                "python3 -c \"import usb.core; d = usb.core.find(idVendor=0x05AC, idProduct=0x1227); print('FOUND' if d else 'NONE')\"",
                label: "Detect DFU device"
            )
            if output.contains("FOUND") {
                device.isInDFU = true
                device.isConnected = true
                log("DFU устройство найдено!", level: .success)
                completeStep(.dfu)
                await runBootChain()
            } else {
                log("DFU устройство не найдено. Убедитесь что Apple TV в DFU.", level: .warning)
                stepStatuses[.dfu] = .active
            }
        } catch {
            log("Ошибка поиска USB: \(error.localizedDescription)", level: .error)
            stepStatuses[.dfu] = .active
        }
    }

    // MARK: - Boot Chain

    func runBootChain() async {
        setStep(.boot)
        stepStatuses[.boot] = .running
        log("Запуск boot chain…", level: .info)

        do {
            // Run boot.sh from the project directory
            let _ = try await runCommand("bash boot.sh", label: "boot.sh — DFU → PongoOS → KPF")
            log("Boot chain завершён. Ожидание YOLO:checkra1n", level: .success)
            completeStep(.boot)
            await runBootstrap()
        } catch {
            failStep(.boot, error: "Boot chain ошибка: \(error.localizedDescription)")
        }
    }

    // MARK: - Bootstrap

    func runBootstrap() async {
        setStep(.bootstrap)
        stepStatuses[.bootstrap] = .running
        log("Ожидание SSH на \(sshConfig.host):\(sshConfig.port)…", level: .info)

        do {
            // Wait for SSH
            let sshAvailable = try await waitForSSH()
            guard sshAvailable else {
                failStep(.bootstrap, error: "SSH таймаут. Проверьте подключение.")
                return
            }

            log("SSH доступен!", level: .success)

            // Run bootstrap installation
            let sshCmd = buildSSHCommand("bash /var/root/install_bootstrap.sh")
            let _ = try await runCommand(sshCmd, label: "Установка bootstrap")

            log("Bootstrap установлен", level: .success)
            completeStep(.bootstrap)
            await runPackageInstall()
        } catch {
            failStep(.bootstrap, error: "Bootstrap ошибка: \(error.localizedDescription)")
        }
    }

    // MARK: - Package Install

    func runPackageInstall() async {
        setStep(.packages)
        stepStatuses[.packages] = .running
        log("Установка пакетов…", level: .info)

        do {
            // Copy and install Pyra
            let scpCmd = "scp -P \(sshConfig.port) -o StrictHostKeyChecking=no " +
                "\(componentsDirectory)/com.fauxly.pyra.deb " +
                "\(sshConfig.username)@\(sshConfig.host):/tmp/"
            let _ = try await runCommand(scpCmd, label: "Копирование Pyra.deb")

            let installCmd = buildSSHCommand(
                "dpkg -i /tmp/com.fauxly.pyra.deb || " +
                "cd /tmp && dpkg-deb -x com.fauxly.pyra.deb /var/jb/ && " +
                "cp -R /var/jb/Applications/Pyra.app /var/jb/Applications/ && " +
                "uicache -p /var/jb/Applications/Pyra.app"
            )
            let _ = try await runCommand(installCmd, label: "Установка Pyra")

            log("Pyra установлена!", level: .success)
            completeStep(.packages)

            // Done!
            setStep(.done)
            stepStatuses[.done] = .success
            overallProgress = 1.0
            isRunning = false
            log("═══ Джейлбрейк завершён! ═══", level: .success)
        } catch {
            failStep(.packages, error: "Установка пакетов: \(error.localizedDescription)")
        }
    }

    // MARK: - SSH Helpers

    private func buildSSHCommand(_ remoteCmd: String) -> String {
        var ssh = "ssh -o StrictHostKeyChecking=no -p \(sshConfig.port) "
        if sshConfig.useKey && !sshConfig.keyPath.isEmpty {
            ssh += "-i \(sshConfig.keyPath) "
        }
        ssh += "\(sshConfig.username)@\(sshConfig.host) "
        ssh += "'\(remoteCmd)'"
        return ssh
    }

    private func waitForSSH() async throws -> Bool {
        for attempt in 1...30 {
            log("  SSH попытка \(attempt)/30…", level: .debug)
            do {
                let result = try await runCommand(
                    "nc -z -w 2 \(sshConfig.host) \(sshConfig.port) && echo OK || echo FAIL",
                    label: "SSH probe #\(attempt)"
                )
                if result.contains("OK") { return true }
            } catch { /* keep trying */ }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return false
    }

    // MARK: - Manual Step Execution

    func runSingleStep(_ step: JailbreakStep) async {
        switch step {
        case .prepare:
            setStep(.prepare)
            stepStatuses[.prepare] = .running
            checkComponents()
            completeStep(.prepare)
        case .dfu:
            await detectDFU()
        case .boot:
            await runBootChain()
        case .bootstrap:
            await runBootstrap()
        case .packages:
            await runPackageInstall()
        case .done:
            break
        }
    }
}
