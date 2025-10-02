import SwiftUI
import MultipeerConnectivity

struct ContentView: View {
    @StateObject private var manager = MultipeerManager()

    var body: some View {
        VStack(spacing: 12) {
            Text("ScreenMirror — Multipeer")
                .font(.title)

            HStack(spacing: 10) {
                Button(manager.isAdvertising ? "Stop Advertising" : "Start Advertising") {
                    manager.toggleAdvertising()
                }
                Button(manager.isBrowsing ? "Stop Browsing" : "Start Browsing") {
                    manager.toggleBrowsing()
                }
                if manager.captureSender == nil {
                    Button("Start Sending") { manager.startSending() }
                } else {
                    Button("Stop Sending") { manager.stopSending() }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Peers")
                        .font(.headline)
                    List(manager.peers, id: \.id) { peer in
                        HStack {
                            Text(peer.displayName)
                            Spacer()
                            if peer.state == .connected {
                                Text("Connected")
                            } else {
                                Button("Connect") {
                                    manager.invite(peer: peer)
                                }
                            }
                        }
                    }
                    .frame(width: 300, height: 260)
                }

                VStack {
                    Text("Receiver")
                        .font(.headline)
                    if let img = manager.lastImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 480, height: 320)
                            .border(Color.black, width: 1)
                    } else {
                        Text("Waiting for frames...")
                            .frame(width: 480, height: 320)
                            .border(Color.black, width: 1)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 820, minHeight: 520)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
