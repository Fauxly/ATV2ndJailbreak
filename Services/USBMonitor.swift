import Foundation
import IOKit
import IOKit.usb

/// Monitors USB for Apple DFU devices in real-time.
@MainActor
class USBMonitor: ObservableObject {

    // Apple DFU device identifiers
    private static let appleVendorID: Int = 0x05AC
    private static let dfuProductID: Int = 0x1227

    @Published var isDFUConnected = false
    @Published var deviceLabel = "Не подключён"
    @Published var ecid: String = ""
    @Published var serialNumber: String = ""

    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var isMonitoring = false

    // MARK: - Start / Stop

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Check if already connected
        checkDFUNow()

        // Set up IOKit notifications for USB attach/detach
        setupNotifications()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }
    }

    deinit {
        // Clean up on main actor not guaranteed here,
        // but IOKit resources should be released
    }

    // MARK: - One-shot check

    func checkDFUNow() {
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching["idVendor"] = Self.appleVendorID
        matching["idProduct"] = Self.dfuProductID

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == KERN_SUCCESS else {
            isDFUConnected = false
            deviceLabel = "Ошибка USB"
            return
        }

        var found = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            found = true
            readDeviceInfo(service)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)

        isDFUConnected = found
        if !found {
            deviceLabel = "Не подключён"
            ecid = ""
            serialNumber = ""
        }
    }

    // MARK: - IOKit Notifications

    private func setupNotifications() {
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notifyPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        // Match Apple DFU devices
        let matchingAdd = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        matchingAdd[kUSBVendorID] = Self.appleVendorID
        matchingAdd[kUSBProductID] = Self.dfuProductID

        let matchingRemove = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        matchingRemove[kUSBVendorID] = Self.appleVendorID
        matchingRemove[kUSBProductID] = Self.dfuProductID

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Device added
        IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            matchingAdd,
            { refcon, iterator in
                guard let refcon = refcon else { return }
                let monitor = Unmanaged<USBMonitor>.fromOpaque(refcon).takeUnretainedValue()
                // Drain iterator
                var service = IOIteratorNext(iterator)
                while service != 0 {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                Task { @MainActor in
                    monitor.checkDFUNow()
                }
            },
            selfPtr,
            &addedIterator
        )
        // Drain initial iterator
        var s = IOIteratorNext(addedIterator)
        while s != 0 { IOObjectRelease(s); s = IOIteratorNext(addedIterator) }

        // Device removed
        IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            matchingRemove,
            { refcon, iterator in
                guard let refcon = refcon else { return }
                let monitor = Unmanaged<USBMonitor>.fromOpaque(refcon).takeUnretainedValue()
                var service = IOIteratorNext(iterator)
                while service != 0 {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                Task { @MainActor in
                    monitor.checkDFUNow()
                }
            },
            selfPtr,
            &removedIterator
        )
        s = IOIteratorNext(removedIterator)
        while s != 0 { IOObjectRelease(s); s = IOIteratorNext(removedIterator) }
    }

    // MARK: - Read device info

    private func readDeviceInfo(_ service: io_service_t) {
        deviceLabel = "Apple TV (DFU Mode)"

        if let sn = IORegistryEntryCreateCFProperty(service, "USB Serial Number" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            serialNumber = sn
            // ECID is often part of the serial in DFU
            if sn.count > 8 {
                ecid = sn
            }
        }
    }
}
