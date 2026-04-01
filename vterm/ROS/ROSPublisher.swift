import Foundation

/// A publisher that sends `std_msgs/msg/String` messages on a ROS2 topic.
///
/// Example:
/// ```swift
/// let pub = ROSStringPublisher(node: node, topic: "/chatter")
/// pub.publish("Hello from iOS!")
/// ```
final class ROSStringPublisher {

    // private state
    private let handle: OpaquePointer

    // MARK: initialiser

    // Parameters:
    //   node:     the node that owns this publisher
    //   topic:    ROS topic name (e.g. "/chatter")
    //   qosDepth: keep-last queue depth. Defaults to 10
    //      ^will probably add reliable/best effort stuff in the future
    init(node: ROSNode, topic: String, qosDepth: Int32 = 10) {
        guard let raw = rosios_create_publisher_string(
            UnsafeMutableRawPointer(node.handle),
            topic,
            qosDepth
        ) else {
            fatalError("ROSStringPublisher: failed to create publisher on '\(topic)'")
        }
        handle = OpaquePointer(raw)
    }

    deinit {
        rosios_destroy_publisher(UnsafeMutableRawPointer(handle))
    }

    // public api

    // publish a plain-text message (will extend)
    func publish(_ message: String) {
        rosios_publish_string(UnsafeMutableRawPointer(handle), message)
    }
}
