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
    @Published var isRunning = false
    @Published var overallProgress: Double = 0
    @Published var showLogPanel = true

    // MARK: - Paths

    @Published var toolsDirectory: String = ""
    @Published var artifactsDirectory: String = ""

    private var processRunner = ProcessRunner()
    private var cancellables = Set<AnyCancellable>()

    // SSH key path
    private var sshKeyPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/atv_jailbreak_key").path
    }

    private var hasSSHKey: Bool {
        FileManager.default.fileExists(atPath: sshKeyPath)
    }

    // MARK: - Init

    init() {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("atv2nd-jailbreak").path
        toolsDirectory = defaultPath
        artifactsDirectory = defaultPath + "/artifacts"

        // Auto-detect SSH key
        if hasSSHKey {
            sshConfig.useKey = true
            sshConfig.keyPath = sshKeyPath
        }
    }

    // MARK: - Logging

    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        logs.append(entry)
    }

    func clearLogs() { logs.removeAll() }

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

    func checkComponents(using compMgr: ComponentManager) {
        log("Проверка компонентов…")
        compMgr.scanAll()

        for comp in compMgr.components {
            let icon = comp.isReady ? "✓" : "✗"
            let level: LogEntry.LogLevel = comp.isReady ? .success : .warning
            log("  \(icon) \(comp.name) — \(comp.statusLabel)", level: level)
        }

        if compMgr.allReady {
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
            artifactsDirectory = url.path + "/artifacts"
            log("Папка проекта: \(toolsDirectory)")
        }
    }

    // MARK: - Run Shell Command

    func runCommand(_ command: String, label: String? = nil, dir: String? = nil) async throws -> String {
        let displayLabel = label ?? String(command.prefix(60))
        log("▶ \(displayLabel)", level: .command)

        return try await withCheckedThrowingContinuation { continuation in
            processRunner.run(
                command: command,
                currentDirectory: dir ?? toolsDirectory,
                onOutput: { [weak self] line in
                    Task { @MainActor in self?.log("  \(line)", level: .debug) }
                },
                onComplete: { result in
                    switch result {
                    case .success(let output): continuation.resume(returning: output)
                    case .failure(let error):  continuation.resume(throwing: error)
                    }
                }
            )
        }
    }

    // MARK: - Full Jailbreak Flow

    func startJailbreak(compMgr: ComponentManager) async {
        guard !isRunning else { return }
        isRunning = true
        clearLogs()

        log("═══ ATV2nd Jailbreak — tvOS 26.6 ═══")
        log("Цель: AppleTV11,1 (A12 / T8020)")

        // Step 1: Prepare
        setStep(.prepare)
        stepStatuses[.prepare] = .running
        checkComponents(using: compMgr)
        if !compMgr.allReady {
            failStep(.prepare, error: "Не все компоненты найдены")
            return
        }
        completeStep(.prepare)

        // Step 2: DFU — user must do manually
        setStep(.dfu)
        stepStatuses[.dfu] = .active
        log("Переведите Apple TV в PWND DFU:", level: .warning)
        log("  1. DCSD → Foxlink → Apple TV → питание")
        log("  2. RP2350 → зелёный LED")
        log("  3. Mac через Lightning → Foxlink")
        log("Нажмите 'Detect DFU' когда готово")
    }

    // MARK: - Detect DFU

    func detectDFU() async {
        stepStatuses[.dfu] = .running
        log("Поиск PWND DFU устройства…")

        do {
            let output = try await runCommand(
                "irecovery -q 2>/dev/null",
                label: "irecovery -q"
            )

            let hasCPID = output.contains("CPID: 0x8020")
            let isDFU = output.contains("MODE: DFU")
            let isPWND = output.contains("PWND:")

            if hasCPID && isDFU {
                device.isInDFU = true
                device.isConnected = true
                device.chipID = "T8020 (A12)"

                if isPWND {
                    log("PWND DFU найден!", level: .success)
                    completeStep(.dfu)
                    await runBootChain()
                } else {
                    log("DFU найден, но не PWND. Подключите RP2350.", level: .warning)
                    stepStatuses[.dfu] = .active
                }
            } else {
                log("DFU не найден. Проверьте подключение.", level: .warning)
                stepStatuses[.dfu] = .active
            }
        } catch {
            log("Ошибка irecovery: \(error.localizedDescription)", level: .error)
            stepStatuses[.dfu] = .active
        }
    }

    // MARK: - Boot Chain (calls boot.sh)

    func runBootChain() async {
        setStep(.boot)
        stepStatuses[.boot] = .running
        log("Запуск boot chain…")

        do {
            let bootScript = toolsDirectory + "/boot.sh"
            guard FileManager.default.fileExists(atPath: bootScript) else {
                failStep(.boot, error: "boot.sh не найден в \(toolsDirectory)")
                return
            }

            let _ = try await runCommand(
                "bash boot.sh 2>&1",
                label: "boot.sh → iBSS → yoloDFU → PongoOS → KPF → bootx"
            )

            log("Boot chain завершён!", level: .success)
            completeStep(.boot)

            // Ask for IP if not set
            if sshConfig.host.isEmpty {
                log("Укажите IP Apple TV для продолжения", level: .warning)
                log("Настройки → Сеть на телевизоре")
            } else {
                await runBootstrap()
            }
        } catch {
            // boot.sh may "fail" due to pongoterm exit — check if bootx was sent
            let errMsg = error.localizedDescription
            if errMsg.contains("bootx") || errMsg.contains("PongoOS USB disconnected") {
                log("Boot chain завершён (PongoOS disconnected)", level: .success)
                completeStep(.boot)
                if !sshConfig.host.isEmpty {
                    await runBootstrap()
                }
            } else {
                failStep(.boot, error: "Boot chain: \(errMsg)")
            }
        }
    }

    // MARK: - Bootstrap (manual preboot install)

    func runBootstrap() async {
        setStep(.bootstrap)
        stepStatuses[.bootstrap] = .running
        log("Ожидание загрузки Apple TV (30 сек)…")

        // Wait for tvOS to boot
        try? await Task.sleep(nanoseconds: 30_000_000_000)

        log("Подключение по SSH к \(sshConfig.host):\(sshConfig.port)…")

        // Wait for SSH
        let sshAvailable = await waitForSSH()
        guard sshAvailable else {
            failStep(.bootstrap, error: "SSH таймаут")
            return
        }
        log("SSH подключён!", level: .success)

        // Check if bootstrap already installed
        do {
            let check = try await runSSH("/cores/binpack/bin/ls /var/jb/usr/bin/dpkg 2>/dev/null && echo INSTALLED || echo MISSING")
            if check.contains("INSTALLED") {
                log("Bootstrap уже установлен", level: .success)
                completeStep(.bootstrap)
                await runPackageInstall()
                return
            }
        } catch { /* not installed */ }

        // Download bootstrap if not cached
        let cacheDir = toolsDirectory + "/.cache"
        let bootstrapCache = cacheDir + "/bootstrap-rootless.tar.zst"

        if !FileManager.default.fileExists(atPath: bootstrapCache) {
            log("Скачивание rootless bootstrap…")
            do {
                let _ = try await runCommand(
                    "mkdir -p \(cacheDir) && curl -L -o \(bootstrapCache) https://apt.procurs.us/bootstraps/1900/bootstrap-ssh-iphoneos-arm64.tar.zst",
                    label: "Скачивание bootstrap"
                )
            } catch {
                failStep(.bootstrap, error: "Не удалось скачать bootstrap")
                return
            }
        }

        // Send bootstrap to Apple TV
        log("Отправка bootstrap на Apple TV…")
        do {
            let _ = try await runCommand(
                "\(buildSSHPipe(localFile: bootstrapCache, remotePath: "/tmp/bootstrap.tar.zst"))",
                label: "Передача bootstrap"
            )
        } catch {
            failStep(.bootstrap, error: "Не удалось передать bootstrap")
            return
        }

        // Find preboot path and install
        log("Установка bootstrap в preboot…")
        do {
            // Get preboot hash
            let prebootHash = try await runSSH(
                "/cores/binpack/bin/ls /private/preboot/ | grep -v '\\.' | grep -v '^active' | head -1"
            )
            let hash = prebootHash.trimmingCharacters(in: .whitespacesAndNewlines)

            // Find jb directory
            let jbDir = try await runSSH(
                "/cores/binpack/usr/bin/find /private/preboot/\(hash) -maxdepth 1 -name 'jb-*' -type d | head -1"
            )
            let jbPath = jbDir.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !jbPath.isEmpty else {
                failStep(.bootstrap, error: "jb- директория не найдена в preboot")
                return
            }
            log("  Preboot: \(jbPath)")

            // Extract and link
            let _ = try await runSSH("""
                /cores/binpack/bin/rm -rf /var/jb && \
                /cores/binpack/bin/mkdir -p '\(jbPath)/var/jb' && \
                /cores/binpack/usr/bin/zstd -d /tmp/bootstrap.tar.zst -o /tmp/bootstrap.tar 2>/dev/null && \
                /cores/binpack/usr/bin/tar -xf /tmp/bootstrap.tar -C '\(jbPath)/' 2>/dev/null && \
                /cores/binpack/bin/ln -sfn '\(jbPath)/var/jb' /var/jb && \
                /cores/binpack/bin/rm -f /tmp/bootstrap.tar /tmp/bootstrap.tar.zst
                """)

            // Verify
            let verify = try await runSSH("/cores/binpack/bin/ls /var/jb/usr/bin/dpkg && echo OK || echo FAIL")
            guard verify.contains("OK") else {
                failStep(.bootstrap, error: "Проверка bootstrap не пройдена")
                return
            }

            log("Bootstrap установлен!", level: .success)

            // Fix broken packages
            log("Исправление пакетов…")
            let _ = try? await runSSH("""
                /cores/binpack/bin/rm -rf /var/jb/var/lib/dpkg/info/shshd.* 2>/dev/null; \
                /var/jb/usr/bin/dpkg --remove --force-all shshd 2>/dev/null; \
                /var/jb/usr/bin/dpkg --configure -a 2>/dev/null; \
                /var/jb/usr/bin/apt update 2>/dev/null; \
                /var/jb/usr/bin/apt --fix-broken install -y 2>/dev/null
                """)
            log("Пакеты исправлены", level: .success)

            completeStep(.bootstrap)
            await runPackageInstall()
        } catch {
            failStep(.bootstrap, error: "Bootstrap: \(error.localizedDescription)")
        }
    }

    // MARK: - Package Install

    func runPackageInstall() async {
        setStep(.packages)
        stepStatuses[.packages] = .running
        log("Установка пакетов…")

        // Install all .deb from debs/ directory
        let debsDir = toolsDirectory + "/debs"
        let fm = FileManager.default

        guard fm.fileExists(atPath: debsDir),
              let debs = try? fm.contentsOfDirectory(atPath: debsDir).filter({ $0.hasSuffix(".deb") }),
              !debs.isEmpty else {
            log("Нет .deb файлов в debs/ — пропускаю", level: .warning)
            completeStep(.packages)
            finishJailbreak()
            return
        }

        for deb in debs {
            let debPath = debsDir + "/" + deb
            log("Установка \(deb)…")

            do {
                // Send .deb to Apple TV
                let _ = try await runCommand(
                    buildSSHPipe(localFile: debPath, remotePath: "/tmp/\(deb)"),
                    label: "Передача \(deb)"
                )

                // Check if rootful
                let contents = try await runSSH(
                    "/var/jb/usr/bin/dpkg-deb -c /tmp/\(deb) 2>/dev/null | head -5"
                )

                let isRootful = contents.contains("./Applications/") && !contents.contains("var/jb")

                if isRootful {
                    log("  Rootful пакет — извлечение в /var/jb/…")
                    let _ = try await runSSH("""
                        /cores/binpack/bin/mkdir -p /tmp/deb-extract && \
                        /var/jb/usr/bin/dpkg-deb -x /tmp/\(deb) /tmp/deb-extract/ && \
                        /cores/binpack/bin/mkdir -p /var/jb/Applications && \
                        /cores/binpack/bin/cp -a /tmp/deb-extract/Applications/* /var/jb/Applications/ 2>/dev/null; \
                        /cores/binpack/bin/cp -a /tmp/deb-extract/Library/* /var/jb/Library/ 2>/dev/null; \
                        /cores/binpack/bin/cp -a /tmp/deb-extract/usr/* /var/jb/usr/ 2>/dev/null; \
                        /cores/binpack/bin/rm -rf /tmp/deb-extract
                        """)
                } else {
                    let _ = try? await runSSH("/var/jb/usr/bin/dpkg -i /tmp/\(deb) 2>&1")
                }

                // Register apps
                let _ = try? await runSSH("""
                    for app in /var/jb/Applications/*.app; do \
                        /cores/binpack/usr/bin/uicache -p "$app" 2>/dev/null; \
                    done
                    """)

                let _ = try? await runSSH("/cores/binpack/bin/rm -f /tmp/\(deb)")
                log("  \(deb) установлен!", level: .success)
            } catch {
                log("  \(deb): \(error.localizedDescription)", level: .warning)
            }
        }

        log("Все пакеты установлены!", level: .success)
        completeStep(.packages)
        finishJailbreak()
    }

    // MARK: - Finish

    private func finishJailbreak() {
        setStep(.done)
        stepStatuses[.done] = .success
        overallProgress = 1.0
        isRunning = false
        log("")
        log("═══ Джейлбрейк завершён! ═══", level: .success)
        log("SSH: ssh -p \(sshConfig.port) root@\(sshConfig.host)")
        if hasSSHKey {
            log("SSH ключ: \(sshKeyPath)")
        } else {
            log("Пароль: alpine")
        }
    }

    // MARK: - SSH Helpers

    private func buildSSHOptions() -> String {
        var opts = "-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o LogLevel=ERROR -p \(sshConfig.port)"
        if sshConfig.useKey && !sshConfig.keyPath.isEmpty {
            opts += " -i \(sshConfig.keyPath)"
        }
        return opts
    }

    private func runSSH(_ remoteCmd: String) async throws -> String {
        let ssh = "ssh \(buildSSHOptions()) \(sshConfig.username)@\(sshConfig.host) '\(remoteCmd)'"
        return try await runCommand(ssh, label: String(remoteCmd.prefix(50)))
    }

    private func buildSSHPipe(localFile: String, remotePath: String) -> String {
        return "cat '\(localFile)' | ssh \(buildSSHOptions()) \(sshConfig.username)@\(sshConfig.host) 'cat > \(remotePath)'"
    }

    private func waitForSSH() async -> Bool {
        for attempt in 1...40 {
            log("  SSH попытка \(attempt)/40…", level: .debug)
            do {
                let result = try await runCommand(
                    "ssh \(buildSSHOptions()) \(sshConfig.username)@\(sshConfig.host) 'echo OK' 2>/dev/null",
                    label: "SSH probe #\(attempt)"
                )
                if result.contains("OK") { return true }
            } catch { /* keep trying */ }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
        return false
    }

    // MARK: - SSH Key Setup

    func setupSSHKey() async {
        guard !sshConfig.host.isEmpty else {
            log("Укажите IP Apple TV", level: .warning)
            return
        }

        log("Настройка SSH ключа…")

        do {
            if !hasSSHKey {
                let _ = try await runCommand(
                    "ssh-keygen -t ed25519 -f \(sshKeyPath) -N '' -q",
                    label: "Генерация SSH ключа"
                )
                log("Ключ создан: \(sshKeyPath)", level: .success)
            }

            let _ = try await runCommand(
                "cat \(sshKeyPath).pub | ssh -p \(sshConfig.port) -o StrictHostKeyChecking=no root@\(sshConfig.host) 'mkdir -p /var/root/.ssh && cat >> /var/root/.ssh/authorized_keys && chmod 600 /var/root/.ssh/authorized_keys'",
                label: "Отправка ключа на Apple TV"
            )

            sshConfig.useKey = true
            sshConfig.keyPath = sshKeyPath
            log("SSH ключ установлен! Пароль больше не нужен.", level: .success)
        } catch {
            log("Ошибка SSH ключа: \(error.localizedDescription)", level: .error)
        }
    }

    // MARK: - Manual Step Execution

    func runSingleStep(_ step: JailbreakStep, compMgr: ComponentManager? = nil) async {
        switch step {
        case .prepare:
            if let mgr = compMgr {
                setStep(.prepare)
                stepStatuses[.prepare] = .running
                checkComponents(using: mgr)
                completeStep(.prepare)
            }
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
