import Foundation
import Network
import os.log

// MARK: - Local Network Sync (Bonjour)
//
// Real-time timer state sync between Mac and iPhone on the same WiFi network.
// Uses Network Framework with Bonjour service discovery (_flodoro._tcp).
//
// How it works:
// 1. Each device advertises a Bonjour service: "_flodoro._tcp"
// 2. Each device also browses for other FloDoro instances
// 3. On discovery, devices auto-connect and exchange timer state
// 4. No pairing UI needed — fully automatic
//
// Latency: <1 second (local network, direct TCP connection)
//
// This supplements CloudKit (Layer 1, ~15s) with near-instant local sync.
// When devices are NOT on the same network, CloudKit handles everything.
//
// Architecture:
//   Mac ◄──[Network Framework / Bonjour]──► iPhone
//   iPhone then relays to Watch via WatchSyncManager (Watch Connectivity)

@MainActor
final class LocalNetworkSync: ObservableObject {
    static let shared = LocalNetworkSync()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.flodoro",
        category: "local-sync"
    )

    private static let serviceType = "_flodoro._tcp"

    /// Number of connected peers
    @Published private(set) var connectedPeerCount: Int = 0

    /// Whether local sync is active (listening + browsing)
    @Published private(set) var isActive: Bool = false

    /// Callback for incoming timer state from a peer
    var onTimerStateReceived: ((TimerStateMessage) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.flodoro.local-sync", qos: .userInteractive)

    private init() {}

    // MARK: - Start / Stop

    /// Begin advertising and browsing for FloDoro peers on the local network.
    func start() {
        guard !isActive else { return }
        startListener()
        startBrowser()
        isActive = true
        Self.logger.info("Local network sync started")
    }

    /// Stop all local network sync activity.
    func stop() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        connectedPeerCount = 0
        isActive = false
        Self.logger.info("Local network sync stopped")
    }

    // MARK: - Broadcast Timer State

    /// Send current timer state to all connected peers.
    func broadcastTimerState(_ state: TimerStateMessage) {
        guard !connections.isEmpty else { return }

        guard let data = try? JSONEncoder().encode(state) else {
            Self.logger.warning("Failed to encode timer state for broadcast")
            return
        }

        // Prefix with 4-byte length header for framing
        var length = UInt32(data.count).bigEndian
        var framedData = Data(bytes: &length, count: 4)
        framedData.append(data)

        for connection in connections where connection.state == .ready {
            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    Self.logger.warning("Broadcast send error: \(error.localizedDescription)")
                }
            })
        }
    }

    // MARK: - Listener (Advertise)

    private func startListener() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true

            listener = try NWListener(using: params)
            listener?.service = NWListener.Service(
                name: "FloDoro-\(DeviceIdentifier.shortID)",
                type: Self.serviceType
            )

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }

            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Self.logger.info("Listener ready — advertising FloDoro service")
                case .failed(let error):
                    Self.logger.error("Listener failed: \(error.localizedDescription)")
                default:
                    break
                }
            }

            listener?.start(queue: queue)
        } catch {
            Self.logger.error("Failed to start listener: \(error.localizedDescription)")
        }
    }

    // MARK: - Browser (Discover)

    private func startBrowser() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: params
        )

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                for change in changes {
                    switch change {
                    case .added(let result):
                        // Don't connect to ourselves
                        if case .service(let name, _, _, _) = result.endpoint,
                           name.contains(DeviceIdentifier.shortID) {
                            continue
                        }
                        self?.connectToPeer(result)
                    case .removed:
                        // Connection cleanup happens in state handler
                        break
                    default:
                        break
                    }
                }
            }
        }

        browser?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Self.logger.info("Browser ready — scanning for FloDoro peers")
            case .failed(let error):
                Self.logger.error("Browser failed: \(error.localizedDescription)")
            default:
                break
            }
        }

        browser?.start(queue: queue)
    }

    // MARK: - Connection Handling

    private func connectToPeer(_ result: NWBrowser.Result) {
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        setupConnection(connection)
        connection.start(queue: queue)
        Self.logger.info("Connecting to peer: \(result.endpoint.debugDescription)")
    }

    private func handleNewConnection(_ connection: NWConnection) {
        setupConnection(connection)
        connection.start(queue: queue)
        Self.logger.info("Accepted incoming connection")
    }

    private func setupConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.connections.append(connection)
                    self?.connectedPeerCount = self?.connections.count ?? 0
                    Self.logger.info("Peer connected (total: \(self?.connectedPeerCount ?? 0))")
                    self?.receiveData(on: connection)

                case .failed, .cancelled:
                    self?.connections.removeAll { $0 === connection }
                    self?.connectedPeerCount = self?.connections.count ?? 0
                    Self.logger.info("Peer disconnected (total: \(self?.connectedPeerCount ?? 0))")

                default:
                    break
                }
            }
        }
    }

    // MARK: - Data Reception

    private func receiveData(on connection: NWConnection) {
        // Read 4-byte length header first
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let data = data, data.count == 4 else {
                if let error = error {
                    Self.logger.warning("Receive header error: \(error.localizedDescription)")
                }
                return
            }

            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            // Now read the message body
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { body, _, _, error in
                if let body = body {
                    Task { @MainActor in
                        self?.handleReceivedData(body)
                    }
                }
                if let error = error {
                    Self.logger.warning("Receive body error: \(error.localizedDescription)")
                    return
                }

                // Continue listening for more messages
                Task { @MainActor in
                    self?.receiveData(on: connection)
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        do {
            let state = try JSONDecoder().decode(TimerStateMessage.self, from: data)
            onTimerStateReceived?(state)
        } catch {
            Self.logger.warning("Failed to decode received data: \(error.localizedDescription)")
        }
    }
}
