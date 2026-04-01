import Foundation
import Darwin

/// Singleton that owns the rclcpp context and executor lifecycle.
final class ROSContext {
    static let shared = ROSContext()

    private var executor: OpaquePointer?
    private var executorThread: Thread?
    private var isRunning = false
    private let lock = NSLock()

    private init() {}

    deinit { stop() }

    // MARK: - Public API

    func start(args: [String] = []) {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }

        // Configure CycloneDDS for unicast peer discovery before rclcpp::init.
        // iOS blocks multicast sockets, so we specify peers explicitly.
        // We bind to the WiFi IP directly (not just the interface name) so
        // CycloneDDS advertises the correct locator in SPDP — otherwise the
        // Mac may reply to a cellular/VPN address and SEDP matching never forms.
        if ProcessInfo.processInfo.environment["CYCLONEDDS_URI"] == nil {
            let wifiIP = Self.wifiIPAddress() ?? "auto"
            let xml = "<CycloneDDS><Domain>" +
                      "<General>" +
                      "<NetworkInterfaceAddress>\(wifiIP)</NetworkInterfaceAddress>" +
                      "<AllowMulticast>false</AllowMulticast>" +
                      "</General>" +
                      "<Discovery><Peers>" +
                      "<Peer address=\"192.168.0.138\"/>" +
                      "</Peers></Discovery>" +
                      "</Domain></CycloneDDS>"
            setenv("CYCLONEDDS_URI", xml, 0)
            print("[ROSContext] CYCLONEDDS_URI set (WiFi IP: \(wifiIP))")
        }

        let cArgs = args.map { strdup($0) }
        defer { cArgs.forEach { free($0) } }

        var argv: [UnsafePointer<CChar>?] = cArgs.map { UnsafePointer($0) }
        let argc = Int32(argv.count)
        argv.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress?.withMemoryRebound(to: UnsafePointer<CChar>?.self,
                                               capacity: Int(argc)) { ptr in
                rosios_init(argc, ptr)
            }
        }

        guard let exec = rosios_create_executor() else {
            fatalError("ROSContext: failed to create executor")
        }
        executor = OpaquePointer(exec)
        isRunning = true

        let t = Thread { [weak self] in
            guard let self, let e = self.executor else { return }
            rosios_spin(UnsafeMutableRawPointer(e))
        }
        t.name = "ROS2-Executor"
        t.qualityOfService = .userInteractive
        t.start()
        executorThread = t
    }

    func addNode(_ node: ROSNode) {
        guard let exec = executor else { return }
        rosios_executor_add_node(UnsafeMutableRawPointer(exec),
                                 UnsafeMutableRawPointer(node.handle))
    }

    func removeNode(_ node: ROSNode) {
        guard let exec = executor else { return }
        rosios_executor_remove_node(UnsafeMutableRawPointer(exec),
                                    UnsafeMutableRawPointer(node.handle))
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning else { return }
        isRunning = false

        if let exec = executor {
            rosios_spin_stop(UnsafeMutableRawPointer(exec))
            Thread.sleep(forTimeInterval: 0.15)
            rosios_destroy_executor(UnsafeMutableRawPointer(exec))
            executor = nil
        }
        rosios_shutdown()
    }

    // MARK: - Helpers

    /// Returns the IPv4 address of the WiFi interface (en0), or nil if not connected.
    private static func wifiIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let ifa = current.pointee
            guard String(cString: ifa.ifa_name) == "en0",
                  ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(ifa.ifa_addr,
                        socklen_t(ifa.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST)
            return String(cString: hostname)
        }
        return nil
    }
}
