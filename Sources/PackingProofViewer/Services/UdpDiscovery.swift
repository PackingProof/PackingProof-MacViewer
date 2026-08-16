// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import Darwin
import Foundation

/// UDP 广播发现返回的候选：来源 IP 取自包源地址，端口为 announce 内公布的 httpPort。
struct UdpAnnounce: Sendable {
    let nodeId: String
    let httpPort: Int
    let sourceIp: String
}

enum UdpDiscoveryProtocol {
    static let port: UInt16 = 5281
    static let maxPacketBytes = 512
    static let protocolName = "packingproof"
    static let protocolVersion = 1
    static let actionDiscover = "discover"
    static let actionAnnounce = "announce"

    static func encodeDiscover() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "protocol": protocolName,
            "protocolVersion": protocolVersion,
            "action": actionDiscover
        ])
    }

    static func isDiscover(_ data: Data) -> Bool {
        guard data.count <= maxPacketBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["protocol"] as? String == protocolName,
              object["protocolVersion"] as? Int == protocolVersion,
              object["action"] as? String == actionDiscover else {
            return false
        }
        return true
    }

    static func parseAnnounce(_ data: Data, sourceIp: String) -> UdpAnnounce? {
        guard data.count <= maxPacketBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["protocol"] as? String == protocolName,
              object["protocolVersion"] as? Int == protocolVersion,
              object["action"] as? String == actionAnnounce,
              let nodeId = object["nodeId"] as? String,
              UUID(uuidString: nodeId) != nil,
              let httpPort = object["httpPort"] as? Int,
              (1...65535).contains(httpPort) else {
            return nil
        }
        return UdpAnnounce(nodeId: nodeId, httpPort: httpPort, sourceIp: sourceIp)
    }
}

/// 客户端 UDP 广播探测：绑定临时端口、开启 SO_BROADCAST，
/// 广播 discover 并在约 600ms 内把收到的 announce 流式吐出。
enum UdpDiscovery {
    static let collectTimeout: TimeInterval = 0.6

    static func discoverAnnounces(
        timeout: TimeInterval = collectTimeout
    ) -> AsyncStream<UdpAnnounce> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }

                let fd = socket(AF_INET, SOCK_DGRAM, 0)
                guard fd >= 0 else { return }
                defer { close(fd) }

                var broadcast: Int32 = 1
                setsockopt(
                    fd,
                    SOL_SOCKET,
                    SO_BROADCAST,
                    &broadcast,
                    socklen_t(MemoryLayout<Int32>.size)
                )

                var recvTimeout = timeval(tv_sec: 0, tv_usec: 100_000)
                setsockopt(
                    fd,
                    SOL_SOCKET,
                    SO_RCVTIMEO,
                    &recvTimeout,
                    socklen_t(MemoryLayout<timeval>.size)
                )

                var bindAddress = sockaddr_in()
                bindAddress.sin_family = sa_family_t(AF_INET)
                bindAddress.sin_port = 0
                bindAddress.sin_addr.s_addr = INADDR_ANY
                withUnsafePointer(to: &bindAddress) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
                        _ = bind(fd, socketPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                let request = UdpDiscoveryProtocol.encodeDiscover()
                guard request.count <= UdpDiscoveryProtocol.maxPacketBytes else { return }
                var destination = sockaddr_in()
                destination.sin_family = sa_family_t(AF_INET)
                destination.sin_port = UdpDiscoveryProtocol.port.bigEndian
                destination.sin_addr.s_addr = inet_addr("255.255.255.255")
                request.withUnsafeBytes { rawBuffer in
                    withUnsafePointer(to: &destination) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
                            _ = sendto(
                                fd,
                                rawBuffer.baseAddress,
                                rawBuffer.count,
                                0,
                                socketPointer,
                                socklen_t(MemoryLayout<sockaddr_in>.size)
                            )
                        }
                    }
                }

                var buffer = [UInt8](repeating: 0, count: UdpDiscoveryProtocol.maxPacketBytes)
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline && !Task.isCancelled {
                    var remote = sockaddr_in()
                    var remoteLength = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let received = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                        withUnsafeMutablePointer(to: &remote) { pointer in
                            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
                                recvfrom(
                                    fd,
                                    rawBuffer.baseAddress,
                                    rawBuffer.count,
                                    0,
                                    socketPointer,
                                    &remoteLength
                                )
                            }
                        }
                    }
                    guard received > 0 else { continue }

                    let sourceIp = String(cString: inet_ntoa(remote.sin_addr))
                    if let announce = UdpDiscoveryProtocol.parseAnnounce(
                        Data(buffer[0..<received]),
                        sourceIp: sourceIp
                    ) {
                        continuation.yield(announce)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
