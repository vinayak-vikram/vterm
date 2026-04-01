import Foundation

/// Persisted app-level settings for the ROS/DDS stack.
@Observable
final class ROSSettings {
    static let shared = ROSSettings()

    /// Unicast peer addresses used for CycloneDDS discovery.
    /// Persisted to UserDefaults; changes take effect on the next ROS start.
    var peers: [String] {
        didSet { UserDefaults.standard.set(peers, forKey: "ros.peers") }
    }

    private init() {
        peers = UserDefaults.standard.stringArray(forKey: "ros.peers") ?? []
    }
}
