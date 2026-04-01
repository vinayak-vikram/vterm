import Testing
import Foundation
@testable import vterm

// Integration tests for the ROS2 stack embedded in vterm.
//
// All tests run on device/simulator against the real rclcpp/CycloneDDS stack.
// Unicast peer discovery is configured automatically in ROSContext.start() —
// no environment variables needed.
//
// CROSS-MACHINE TESTS:
//   Before running tests 7 & 8, on your Mac run:
//     ros && ros2 topic pub /test_from_mac std_msgs/msg/String \
//       "{data: 'ping_from_mac'}" -r 2
//   And to verify test 8:
//     ros && ros2 topic echo /test_from_ios

private struct TimeoutError: Error {}

@Suite("ROS2 Integration Tests")
struct ROSTests {

    init() {
        ROSContext.shared.start()
    }

    // MARK: - 1. Context

    @Test func contextOK() {
        #expect(rosios_ok())
    }

    // MARK: - 2. Node

    @Test func nodeCreation() {
        let node = ROSNode(name: "t_node_\(uid())")
        ROSContext.shared.addNode(node)
        #expect(!node.name.isEmpty)
    }

    // MARK: - 3. Publisher

    @Test func publisherCreation() throws {
        let node = ROSNode(name: "t_pub_\(uid())")
        ROSContext.shared.addNode(node)
        let pub = try ROSStringPublisher(node: node, topic: "/t_pub_\(uid())")
        _ = pub
    }

    // MARK: - 4. Subscriber

    @Test func subscriberCreation() throws {
        let node = ROSNode(name: "t_sub_\(uid())")
        ROSContext.shared.addNode(node)
        let sub = try ROSStringSubscriber(node: node, topic: "/t_sub_\(uid())") { _ in }
        _ = sub
    }

    // MARK: - 5. Same-process loopback

    // Publishes a message and expects to receive it back on the same topic
    // within the same process. Exercises the full pub → DDS → sub path.

    @Test func selfLoopback() async throws {
        let topic = "/t_loop_\(uid())"
        let payload = "loopback_\(uid())"

        let (stream, continuation) = AsyncStream<String>.makeStream()

        let node = ROSNode(name: "t_loop_\(uid())")
        ROSContext.shared.addNode(node)

        let pub = try ROSStringPublisher(node: node, topic: topic)
        var sub: ROSStringSubscriber?
        sub = try ROSStringSubscriber(node: node, topic: topic) { msg in
            continuation.yield(msg)
            _ = sub
        }

        // brief pause for DDS endpoint registration
        try await Task.sleep(for: .milliseconds(300))
        pub.publish(payload)

        let received = try await withTimeout(seconds: 5) {
            for await msg in stream where msg == payload { return msg }
            return nil
        }
        #expect(received == payload)
    }

    // MARK: - 6. Multiple messages

    @Test func multipleMessages() async throws {
        let count = 5
        let topic = "/t_multi_\(uid())"
        let (stream, continuation) = AsyncStream<String>.makeStream()

        let node = ROSNode(name: "t_multi_\(uid())")
        ROSContext.shared.addNode(node)

        let pub = try ROSStringPublisher(node: node, topic: topic)
        var sub: ROSStringSubscriber?
        sub = try ROSStringSubscriber(node: node, topic: topic) { msg in
            continuation.yield(msg)
            _ = sub
        }

        try await Task.sleep(for: .milliseconds(300))
        for i in 0..<count {
            pub.publish("msg_\(i)")
            try await Task.sleep(for: .milliseconds(50))
        }

        var received: [String] = []
        let _ = try await withTimeout(seconds: 5) { () -> Bool? in
            for await msg in stream {
                received.append(msg)
                if received.count >= count { return true }
            }
            return nil
        }

        #expect(received.count == count)
    }

    // MARK: - 7. Cross-machine: receive from Mac
    //
    // Mac must be publishing on /test_from_mac before this test runs.
    // Skips (does not fail) if no message arrives within 10 s.

    @Test func receiveFromMac() async throws {
        let (stream, continuation) = AsyncStream<String>.makeStream()

        let node = ROSNode(name: "t_rx_mac_\(uid())")
        ROSContext.shared.addNode(node)

        var sub: ROSStringSubscriber?
        sub = try ROSStringSubscriber(node: node, topic: "/test_from_mac") { msg in
            continuation.yield(msg)
            _ = sub
        }

        let received = try await withTimeout(seconds: 10) { () -> String? in
            for await msg in stream { return msg }
            return nil
        }

        if received == nil {
            throw XCTSkipWrapper(
                "No message on /test_from_mac within 10 s — " +
                "on Mac run: ros && ros2 topic pub /test_from_mac " +
                "std_msgs/msg/String \"{data: 'ping'}\" -r 2"
            )
        }

        #expect(!(received?.isEmpty ?? true))
    }

    // MARK: - 8. Cross-machine: publish to Mac
    //
    // Verify on Mac with: ros && ros2 topic echo /test_from_ios

    @Test func publishToMac() async throws {
        let node = ROSNode(name: "t_tx_mac_\(uid())")
        ROSContext.shared.addNode(node)
        let pub = try ROSStringPublisher(node: node, topic: "/test_from_ios")

        // allow DDS peer discovery
        try await Task.sleep(for: .seconds(1))

        for i in 1...5 {
            pub.publish("hello_from_ios_\(i)")
            try await Task.sleep(for: .milliseconds(200))
        }

        #expect(rosios_ok())
    }

    // MARK: - Helpers

    private func uid() -> Int { Int.random(in: 100_000...999_999) }

    /// Races `body` against a timeout. Returns nil on timeout.
    private func withTimeout<T: Sendable>(
        seconds: Double,
        body: @escaping @Sendable () async -> T?
    ) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let result = try await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }
}

// Swift Testing doesn't have XCTSkip, so we use a custom error that prints
// a clear message in the test output.
private struct XCTSkipWrapper: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}
