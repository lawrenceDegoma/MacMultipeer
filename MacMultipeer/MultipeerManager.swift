import Foundation
import MultipeerConnectivity
import Combine
import AppKit

class Peer: Identifiable {
    let id = UUID()
    let peer: MCPeerID
    var displayName: String { peer.displayName }
    var state: MCSessionState = .notConnected

    init(peer: MCPeerID) { self.peer = peer }
}

class MultipeerManager: NSObject, ObservableObject {
    private let serviceType = "screenshare"
    private let myPeerId = MCPeerID(displayName: Host.current().localizedName ?? "mac")
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var session: MCSession!

    @Published var peers: [Peer] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false
    @Published var lastImage: NSImage? = nil

    var captureSender: CaptureSender?

    override init() {
        super.init()
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    func startSending() {
        // start capture and forward frames via sendFrame closure
        guard captureSender == nil else { return }
        captureSender = CaptureSender(onFrame: { [weak self] data in
            self?.sendFrame(data)
        })
        captureSender?.start()
    }

    func stopSending() {
        captureSender?.stop()
        captureSender = nil
    }

    private func sendFrame(_ data: Data) {
        guard session.connectedPeers.count > 0 else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.session.send(data, toPeers: self.session.connectedPeers, with: .reliable)
            } catch {
                print("Failed to send frame:", error)
            }
        }
    }

    func toggleAdvertising() {
        if isAdvertising {
            advertiser?.stopAdvertisingPeer()
            advertiser = nil
            isAdvertising = false
        } else {
            advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
            advertiser?.delegate = self
            advertiser?.startAdvertisingPeer()
            isAdvertising = true
        }
    }

    func toggleBrowsing() {
        if isBrowsing {
            browser?.stopBrowsingForPeers()
            browser = nil
            isBrowsing = false
        } else {
            browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
            browser?.delegate = self
            browser?.startBrowsingForPeers()
            isBrowsing = true
        }
    }

    func invite(peer: Peer) {
        guard let browser = browser else { return }
        browser.invitePeer(peer.peer, to: session, withContext: nil, timeout: 30)
    }
}

// MARK: MCNearbyServiceAdvertiserDelegate
extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            // Auto-accept for now
            invitationHandler(true, self.session)
        }
    }
}

// MARK: MCNearbyServiceBrowserDelegate
extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            if !self.peers.contains(where: { $0.peer == peerID }) {
                self.peers.append(Peer(peer: peerID))
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.peers.removeAll { $0.peer == peerID }
        }
    }
}

// MARK: MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            if let p = self.peers.first(where: { $0.peer == peerID }) {
                p.state = state
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // handle incoming data (e.g., frames)
        DispatchQueue.main.async {
            if let img = NSImage(data: data) {
                self.lastImage = img
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
