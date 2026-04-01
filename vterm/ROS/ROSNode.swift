import Foundation

/// A wrapper around a native rclcpp node (rosios_node_t).
///
/// The node is created on initialisation and destroyed on deinit.
/// After creation, add the node to the shared context so its
/// callbacks are dispatched by the executor:
///
/// ```swift
/// let node = ROSNode(name: "my_node")
/// ROSContext.shared.addNode(node)
/// ```
final class ROSNode {

    // the underlying opaque rclcpp node handle
    let handle: OpaquePointer

    // the node name as supplied at initialisation
    let name: String

    // the namespace as supplied at initialisation (defaults to "/")
    let namespace_: String

    // MARK: initialiser

    // parameters:
    //   name: ROS node name
    //   namespace: ROS node namespace, defaults to "/"
    init(name: String, namespace: String = "/") {
        self.name = name
        self.namespace_ = namespace

        guard let raw = rosios_create_node(name, namespace) else {
            fatalError("ROSNode: failed to create node '\(name)' in namespace '\(namespace)'")
        }
        handle = OpaquePointer(raw)
    }

    deinit {
        rosios_destroy_node(UnsafeMutableRawPointer(handle))
    }
}
