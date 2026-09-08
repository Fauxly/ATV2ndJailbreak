import Foundation

// MARK: - Jailbreak Step

enum JailbreakStep: Int, CaseIterable, Identifiable {
    case prepare = 0
    case dfu
    case boot
    case bootstrap
    case packages
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .prepare:    return "Подготовка"
        case .dfu:        return "DFU Mode"
        case .boot:       return "Boot Chain"
        case .bootstrap:  return "Bootstrap"
        case .packages:   return "Пакеты"
        case .done:       return "Готово"
        }
    }

    var subtitle: String {
        switch self {
        case .prepare:    return "Проверка компонентов и USB"
        case .dfu:        return "Введите Apple TV в DFU"
        case .boot:       return "iBSS → PongoOS → KPF"
        case .bootstrap:  return "Установка файловой системы"
        case .packages:   return "Pyra и зависимости"
        case .done:       return "Джейлбрейк завершён"
        }
    }

    var icon: String {
        switch self {
        case .prepare:    return "checklist"
        case .dfu:        return "cable.connector"
        case .boot:       return "cpu"
        case .bootstrap:  return "shippingbox"
        case .packages:   return "square.stack.3d.up"
        case .done:       return "checkmark.seal.fill"
        }
    }
}

// MARK: - Step Status

enum StepStatus: Equatable {
    case pending
    case active
    case running
    case success
    case failure(String)

    var color: String {
        switch self {
        case .pending:  return "secondary"
        case .active:   return "blue"
        case .running:  return "orange"
        case .success:  return "green"
        case .failure:  return "red"
        }
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    enum LogLevel: String {
        case info    = "INFO"
        case success = "OK"
        case warning = "WARN"
        case error   = "ERR"
        case debug   = "DBG"
        case command  = "CMD"
    }
}

// MARK: - Device Info

struct DeviceInfo {
    var isConnected: Bool = false
    var isInDFU: Bool = false
    var productName: String = ""
    var chipID: String = ""
    var ecid: String = ""
    var serialNumber: String = ""
}

// MARK: - SSH Config

struct SSHConfig {
    var host: String = ""
    var port: Int = 44
    var username: String = "root"
    var password: String = "alpine"
    var useKey: Bool = false
    var keyPath: String = ""
}

// MARK: - Components

struct ComponentInfo: Identifiable {
    let id = UUID()
    let name: String
    let filename: String
    var isPresent: Bool = false
    var version: String = ""
    var path: String = ""
}
