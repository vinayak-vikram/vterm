import Foundation

/// Singleton that owns the rclcpp context and executor lifecycle.
///
/// Usage:
/// ```swift
/// ROSContext.shared.start()   // initialise ROS and begin spinning
/// ROSContext.shared.addNode(myNode)
/// ROSContext.shared.stop()    // graceful shutdown
/// ```
final class ROSContext {
    // shared instance
    static let shared = ROSContext()

    // private state
    private var executor: OpaquePointer?
    private var executorThread: Thread?
    private var isRunning = false
    private let lock = NSLock()

    private init() {}

    deinit {
        stop()
    }

    // PUBLIC API

    // initialise rclcpp and start the executor on a background thread.
    // safe to call multiple times (subsequent calls are no-ops)
    func start(args: [String] = []) {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }

        // Configure CycloneDDS for unicast peer discovery before rclcpp::init.
        // iOS blocks multicast sockets, so we list known peers explicitly.
        // The Mac's default multicast config is fully interoperable with this —
        // it responds to unicast SPDP packets normally.
        // Add peers here as "<Peer address="hostname.local"/>" entries.
        if ProcessInfo.processInfo.environment["CYCLONEDDS_URI"] == nil {
            let xml = """
            <CycloneDDS><Domain>\
            <Discovery><Peers>\
            <Peer address="192.168.0.138"/>\
            </Peers></Discovery>\
            <General><AllowMulticast>false</AllowMulticast></General>\
            </Domain></CycloneDDS>
            """
            setenv("CYCLONEDDS_URI", xml, 0)
        }

        // need to convert swift strings to C strings for rclcpp::init.
        let cArgs = args.map { strdup($0) }
        defer { cArgs.forEach { free($0) } }

        // build a mutable pointer-to-pointer that rclcpp expects.
        var argv: [UnsafePointer<CChar>?] = cArgs.map { UnsafePointer($0) }
        let argc = Int32(argv.count)

        argv.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress?.withMemoryRebound(to: UnsafePointer<CChar>?.self,
                                               capacity: Int(argc)) { ptr in
                rosios_init(argc, ptr)
            }
        }

        // create executor AFTER rclcpp::init — SingleThreadedExecutor needs
        // a valid rclcpp context or its constructor throws
        guard let exec = rosios_create_executor() else {
            fatalError("ROSContext: failed to create executor (rclcpp not initialised?)")
        }
        executor = OpaquePointer(exec)

        isRunning = true

        // put executor in designated background thread
        let t = Thread { [weak self] in
            guard let self, let e = self.executor else { return }
            rosios_spin(UnsafeMutableRawPointer(e))
        }
        t.name = "ROS2-Executor"
        t.qualityOfService = .userInteractive
        t.start()
        executorThread = t
    }

    // add a node to executor
    func addNode(_ node: ROSNode) {
        guard let exec = executor else { return }
        rosios_executor_add_node(
            UnsafeMutableRawPointer(exec),
            UnsafeMutableRawPointer(node.handle)
        )
    }

    // stop the executor and shut down rclcpp
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
}
