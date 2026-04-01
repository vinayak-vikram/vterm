import SwiftUI

@MainActor
@Observable
final class PublishViewModel {
    var topic = "/chatter"
    var message = "Hello from iOS!"
    var isRunning = false
    var isWarmingUp = false
    var errorMessage: String?

    private var node: ROSNode?
    private var publisher: ROSStringPublisher?

    func start() {
        guard !isRunning else { return }
        errorMessage = nil
        ROSContext.shared.start()
        let n = ROSNode(name: "vterm_pub_node")
        ROSContext.shared.addNode(n)
        do {
            publisher = try ROSStringPublisher(node: n, topic: topic)
            node = n
            isRunning = true
            isWarmingUp = true
            Task {
                try? await Task.sleep(for: .seconds(1))
                isWarmingUp = false
            }
        } catch {
            ROSContext.shared.removeNode(n)
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        if let n = node { ROSContext.shared.removeNode(n) }
        publisher = nil
        node = nil
        isRunning = false
    }

    func send() {
        publisher?.publish(message)
    }
}

struct PublishView: View {
    @State private var vm = PublishViewModel()

    var body: some View {
        Form {
            Section("Topic") {
                HStack {
                    TextField("/chatter", text: $vm.topic)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(vm.isRunning)
                    Button(vm.isRunning ? "Stop" : "Start") {
                        vm.isRunning ? vm.stop() : vm.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.isRunning ? .red : .accentColor)
                }
            }

            Section("Message") {
                TextField("message", text: $vm.message)
                    .autocorrectionDisabled()
                    .disabled(!vm.isRunning)

                Button(action: vm.send) {
                    if vm.isWarmingUp {
                        Label("Discovering peers…", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Publish", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.isRunning || vm.isWarmingUp)
            }

            if let err = vm.errorMessage {
                Section {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Publish")
    }
}

@MainActor
@Observable
final class SubscribeViewModel {
    var topic = "/chatter"
    var messages: [String] = []
    var isRunning = false
    var errorMessage: String?

    private var node: ROSNode?
    private var subscriber: ROSStringSubscriber?

    func start() {
        guard !isRunning else { return }
        errorMessage = nil
        ROSContext.shared.start()
        let n = ROSNode(name: "vterm_sub_node")
        ROSContext.shared.addNode(n)
        do {
            subscriber = try ROSStringSubscriber(node: n, topic: topic) { [weak self] msg in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    messages.insert(msg, at: 0)
                    if messages.count > 100 { messages = Array(messages.prefix(100)) }
                }
            }
            node = n
            isRunning = true
        } catch {
            ROSContext.shared.removeNode(n)
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        if let n = node { ROSContext.shared.removeNode(n) }
        subscriber = nil
        node = nil
        isRunning = false
    }

    func clear() {
        messages = []
    }
}

struct SubscribeView: View {
    @State private var vm = SubscribeViewModel()

    var body: some View {
        Form {
            Section("Topic") {
                HStack {
                    TextField("/chatter", text: $vm.topic)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(vm.isRunning)
                    Button(vm.isRunning ? "Stop" : "Start") {
                        vm.isRunning ? vm.stop() : vm.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.isRunning ? .red : .accentColor)
                }
            }

            Section {
                if vm.messages.isEmpty {
                    Text(vm.isRunning ? "Waiting for messages…" : "Press Start to subscribe.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(vm.messages.enumerated()), id: \.offset) { _, msg in
                        Text(msg)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            } header: {
                HStack {
                    Text("Messages (\(vm.messages.count))")
                    Spacer()
                    if !vm.messages.isEmpty {
                        Button("Clear", action: vm.clear)
                            .font(.caption)
                    }
                }
            }

            if let err = vm.errorMessage {
                Section {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Subscribe")
    }
}

struct ConfigView: View {
    private let settings = ROSSettings.shared
    @State private var newPeer = ""

    var body: some View {
        Form {
            Section {
                ForEach(settings.peers, id: \.self) { peer in
                    Text(peer).font(.system(.body, design: .monospaced))
                }
                .onDelete { settings.peers.remove(atOffsets: $0) }
            } header: {
                Text("DDS Peers")
            } footer: {
                Text("Unicast peers for DDS discovery. Changes take effect when ROS is next started.")
            }

            Section("Add Peer") {
                HStack {
                    TextField("192.168.x.x or hostname.local", text: $newPeer)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Add") {
                        let p = newPeer.trimmingCharacters(in: .whitespaces)
                        guard !p.isEmpty, !settings.peers.contains(p) else { return }
                        settings.peers.append(p)
                        newPeer = ""
                    }
                    .disabled(newPeer.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("Configuration")
        .toolbar { EditButton() }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { PublishView() }
                .tabItem { Label("Publish", systemImage: "paperplane") }
            NavigationStack { SubscribeView() }
                .tabItem { Label("Subscribe", systemImage: "antenna.radiowaves.left.and.right") }
            NavigationStack { ConfigView() }
                .tabItem { Label("Config", systemImage: "gear") }
        }
    }
}

#Preview {
    ContentView()
}
