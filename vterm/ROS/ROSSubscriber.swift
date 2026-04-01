import Foundation

enum ROSError: Error, LocalizedError {
    case nodeCreationFailed(String)
    case publisherCreationFailed(String)
    case subscriberCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .nodeCreationFailed(let name):       return "Failed to create ROS node '\(name)'"
        case .publisherCreationFailed(let topic): return "Failed to create publisher on '\(topic)'"
        case .subscriberCreationFailed(let topic): return "Failed to create subscriber on '\(topic)'"
        }
    }
}

// closure box; keeps the Swift closure alive on the heap so it can be
// referenced safely from the C callback

private final class ClosureBox {
    let closure: (String) -> Void
    init(_ closure: @escaping (String) -> Void) {
        self.closure = closure
    }
}

// bridges the C callback into the Swift closure
// `userdata` is an Unmanaged<ClosureBox> raw pointer

private func stringCallbackTrampoline(
    msg: UnsafePointer<CChar>?,
    userdata: UnsafeMutableRawPointer?
) {
    guard let msg, let userdata else { return }
    let box = Unmanaged<ClosureBox>.fromOpaque(userdata).takeUnretainedValue()
    let str = String(cString: msg)
    box.closure(str)
}

// string subscriber

/// A subscriber that receives `std_msgs/msg/String` messages from a ROS2 topic.
///
/// The supplied closure is called on the executor thread for every incoming
/// message. If you update UI state inside the closure, dispatch to the main
/// actor explicitly:
///
/// ```swift
/// let sub = ROSStringSubscriber(node: node, topic: "/chatter") { msg in
///     Task { @MainActor in
///         messages.append(msg)
///     }
/// }
/// ```
final class ROSStringSubscriber {

    // private state

    private let handle: OpaquePointer

    // retains the closure box for the lifetime of this subscriber
    private let callbackBox: ClosureBox

    // MARK: initialiser

    // parameters:
    //   node: the node that owns this subscription
    //   topic: ROS topic name (e.g. "/chatter")
    //   qosDepth: keep-last queue depth (defaults to 10)
    //   callback: called on every received message; the string argument is only valid for the duration of the call
    init(
        node: ROSNode,
        topic: String,
        qosDepth: Int32 = 10,
        callback: @escaping (String) -> Void
    ) throws {
        let box = ClosureBox(callback)
        self.callbackBox = box

        // +1 retain: the C layer holds an unmanaged pointer to the box
        // we release it in deinit
        let rawBox = Unmanaged.passRetained(box).toOpaque()

        guard let raw = rosios_create_subscription_string(
            UnsafeMutableRawPointer(node.handle),
            topic,
            qosDepth,
            stringCallbackTrampoline,
            rawBox
        ) else {
            Unmanaged.passUnretained(box).release()
            throw ROSError.subscriberCreationFailed(topic)
        }
        handle = OpaquePointer(raw)
    }

    deinit {
        rosios_destroy_subscription(UnsafeMutableRawPointer(handle))
        // balance the +1 retain we took in init when passing rawBox to the C layer.
        Unmanaged.passUnretained(callbackBox).release()
    }
}
