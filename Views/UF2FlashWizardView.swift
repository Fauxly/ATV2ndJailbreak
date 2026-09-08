import SwiftUI

struct UF2FlashWizardView: View {
    @State private var flashStep: UF2Step = .idle
    @State private var driveCheckTimer: Timer?
    @State private var flashSuccess = false

    enum UF2Step: Int, CaseIterable {
        case idle = 0
        case holdBootsel
        case connectUSB
        case waitDrive
        case flash
        case done
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "memorychip")
                        .foregroundColor(.cyan)
                        .font(.system(size: 13))
                    Text("Прошивка usbliter8")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    if flashStep != .idle {
                        Button("Сбросить") {
                            resetWizard()
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }

                // Step content
                switch flashStep {
                case .idle:
                    idleView
                case .holdBootsel:
                    holdBootselView
                case .connectUSB:
                    connectUSBView
                case .waitDrive:
                    waitDriveView
                case .flash:
                    flashView
                case .done:
                    doneView
                }
            }
            .padding(4)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waveshare RP2350 USB-A нужно прошить один раз. После этого плата готова к работе.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button {
                withAnimation { flashStep = .holdBootsel }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("Начать прошивку")
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Step 1: Hold BOOTSEL

    private var holdBootselView: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepHeader(number: 1, total: 4, text: "Зажмите кнопку BOOTSEL")

            HStack(spacing: 12) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Найдите маленькую кнопку BOOTSEL на плате Waveshare RP2350.")
                        .font(.system(size: 12))
                    Text("Зажмите и держите её — не отпускайте!")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                }
            }

            Button {
                withAnimation { flashStep = .connectUSB }
            } label: {
                Text("Держу кнопку →")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
        }
    }

    // MARK: - Step 2: Connect USB

    private var connectUSBView: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepHeader(number: 2, total: 4, text: "Подключите плату к Mac")

            HStack(spacing: 12) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 28))
                    .foregroundColor(.cyan)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Не отпуская BOOTSEL, подключите RP2350 к Mac по USB.")
                        .font(.system(size: 12))
                    Text("После подключения — отпустите кнопку.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.cyan)
                }
            }

            Button {
                withAnimation { flashStep = .waitDrive }
                startDriveCheck()
            } label: {
                Text("Подключил, отпустил →")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.cyan)
        }
    }

    // MARK: - Step 3: Wait for RPI-RP2 drive

    private var waitDriveView: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepHeader(number: 3, total: 4, text: "Ожидание диска RPI-RP2")

            HStack(spacing: 12) {
                if FileManager.default.fileExists(atPath: "/Volumes/RPI-RP2") {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Диск RPI-RP2 обнаружен!")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                        Text("Плата готова к прошивке.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ожидание диска RPI-RP2 в Finder…")
                            .font(.system(size: 12))
                        Text("Если диск не появляется — повторите с шага 1.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if FileManager.default.fileExists(atPath: "/Volumes/RPI-RP2") {
                Button {
                    withAnimation { flashStep = .flash }
                } label: {
                    Text("Прошить →")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
            }
        }
    }

    // MARK: - Step 4: Flash

    private var flashView: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepHeader(number: 4, total: 4, text: "Прошивка")

            HStack(spacing: 12) {
                Image(systemName: "arrow.down.to.line.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.cyan)

                Text("Нажмите кнопку, чтобы скопировать usbliter8.uf2 на плату. Плата перезагрузится автоматически.")
                    .font(.system(size: 12))
            }

            Button {
                performFlash()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                    Text("Прошить usbliter8.uf2")
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.cyan)
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 4) {
                    if flashSuccess {
                        Text("Прошивка завершена!")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                        Text("Waveshare RP2350 готов к работе. Прошивать больше не нужно.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Ошибка прошивки")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red)
                        Text("Проверьте подключение и попробуйте снова.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func stepHeader(number: Int, total: Int, text: String) -> some View {
        HStack(spacing: 8) {
            Text("\(number)/\(total)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.cyan.opacity(0.12))
                .cornerRadius(4)

            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
    }

    private func startDriveCheck() {
        driveCheckTimer?.invalidate()
        driveCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if FileManager.default.fileExists(atPath: "/Volumes/RPI-RP2") {
                driveCheckTimer?.invalidate()
                withAnimation { flashStep = .flash }
            }
        }
    }

    private func resetWizard() {
        driveCheckTimer?.invalidate()
        withAnimation { flashStep = .idle }
        flashSuccess = false
    }

    private func performFlash() {
        guard let source = Bundle.main.url(forResource: "usbliter8", withExtension: "uf2") else {
            flashSuccess = false
            withAnimation { flashStep = .done }
            return
        }

        let dest = URL(fileURLWithPath: "/Volumes/RPI-RP2/usbliter8.uf2")

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            flashSuccess = true
        } catch {
            flashSuccess = false
            print("UF2 flash error: \(error)")
        }

        withAnimation { flashStep = .done }
    }
}
