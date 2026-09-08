import Foundation

/// Manages jailbreak components: bundled in .app + downloadable updates.
@MainActor
class ComponentManager: ObservableObject {

    // MARK: - Types

    struct Component: Identifiable {
        let id: String
        let name: String
        let filename: String
        let remoteURL: String?
        var status: Status = .unknown
        var localPath: String = ""
        var size: String = ""

        enum Status: Equatable {
            case unknown
            case bundled
            case cached
            case downloading(Double)
            case missing
            case error(String)
        }

        var isReady: Bool {
            status == .bundled || status == .cached
        }

        var statusLabel: String {
            switch status {
            case .unknown:            return "—"
            case .bundled:            return "Встроен"
            case .cached:             return "Загружен"
            case .downloading(let p): return "\(Int(p * 100))%"
            case .missing:            return "Отсутствует"
            case .error(let e):       return e
            }
        }
    }

    // MARK: - State

    @Published var components: [Component] = []
    @Published var isDownloading = false

    /// External artifacts directory (~/atv2nd-jailbreak/artifacts/)
    var artifactsDirectory: String = "" {
        didSet { scanAll() }
    }

    /// External debs directory (~/atv2nd-jailbreak/debs/)
    var debsDirectory: String = "" {
        didSet { scanAll() }
    }

    private var cacheDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("ATV2ndJailbreak/Components", isDirectory: true)
    }

    // MARK: - Init

    init() {
        defineComponents()
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func defineComponents() {
        components = [
            Component(id: "ibss",      name: "iBSS (patched)",      filename: "ibss.yolodfu.bin",
                      remoteURL: nil),
            Component(id: "pongo",     name: "PongoOS Container",   filename: "pongo-container.bin",
                      remoteURL: nil),
            Component(id: "kpf",       name: "KPF Module",          filename: "checkra1n-kpf-pongo",
                      remoteURL: nil),
            Component(id: "ramdisk",   name: "Ramdisk",             filename: "ramdisk.dmg",
                      remoteURL: nil),
            Component(id: "binpack",   name: "Binpack",             filename: "binpack.dmg",
                      remoteURL: nil),
            Component(id: "bootstrap", name: "Bootstrap",           filename: "bootstrap-ssh-iphoneos-arm64.tar.zst",
                      remoteURL: "https://apt.procurs.us/bootstraps/1900/bootstrap-ssh-iphoneos-arm64.tar.zst"),
        ]
    }

    // MARK: - Scan

    func scanAll() {
        let fm = FileManager.default

        for i in components.indices {
            let c = components[i]

            // 1) Check artifacts directory
            if !artifactsDirectory.isEmpty {
                let artPath = artifactsDirectory + "/" + c.filename
                if fm.fileExists(atPath: artPath) {
                    components[i].status = .cached
                    components[i].localPath = artPath
                    components[i].size = formatSize(artPath)
                    continue
                }
            }

            // 2) Check cache (downloaded)
            let cachedPath = cacheDir.appendingPathComponent(c.filename).path
            if fm.fileExists(atPath: cachedPath) {
                components[i].status = .cached
                components[i].localPath = cachedPath
                components[i].size = formatSize(cachedPath)
                continue
            }

            // 3) Check app bundle
            if let bundled = Bundle.main.url(forResource: c.filename, withExtension: nil)
                ?? Bundle.main.url(forResource: (c.filename as NSString).deletingPathExtension,
                                   withExtension: (c.filename as NSString).pathExtension),
               fm.fileExists(atPath: bundled.path) {
                components[i].status = .bundled
                components[i].localPath = bundled.path
                components[i].size = formatSize(bundled.path)
                continue
            }

            // 4) Not found
            components[i].status = .missing
            components[i].localPath = ""
        }
    }

    // MARK: - Access

    func path(for id: String) -> String? {
        components.first(where: { $0.id == id && $0.isReady })?.localPath
    }

    var allReady: Bool {
        // Bootstrap is optional (downloaded on-demand during setup)
        components.filter { $0.id != "bootstrap" }.allSatisfy(\.isReady)
    }

    // MARK: - Download

    func downloadComponent(id: String) async {
        guard let idx = components.firstIndex(where: { $0.id == id }),
              let urlStr = components[idx].remoteURL,
              let url = URL(string: urlStr) else { return }

        components[idx].status = .downloading(0)
        isDownloading = true

        let dest = cacheDir.appendingPathComponent(components[idx].filename)

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.moveItem(at: tempURL, to: dest)

            components[idx].status = .cached
            components[idx].localPath = dest.path
            components[idx].size = formatSize(dest.path)
        } catch {
            components[idx].status = .error(error.localizedDescription)
        }

        isDownloading = components.contains {
            if case .downloading = $0.status { return true }
            return false
        }
    }

    func downloadAllMissing() async {
        for comp in components where comp.status == .missing && comp.remoteURL != nil {
            await downloadComponent(id: comp.id)
        }
    }

    // MARK: - Import from Finder

    func importFile(for id: String, from sourceURL: URL) throws {
        guard let idx = components.firstIndex(where: { $0.id == id }) else { return }
        let dest = cacheDir.appendingPathComponent(components[idx].filename)
        let fm = FileManager.default

        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: sourceURL, to: dest)

        components[idx].status = .cached
        components[idx].localPath = dest.path
        components[idx].size = formatSize(dest.path)
    }

    // MARK: - Helpers

    private func formatSize(_ path: String) -> String {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let bytes = a[.size] as? Int64 else { return "?" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
