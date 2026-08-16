// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import Foundation
import Darwin

struct NetworkCandidate: Sendable {
    let address: IPv4Address
    let mask: UInt32
    let interfaceName: String
}

/// 复刻上游 WorkstationNetwork 的局域网主机发现行为。
final class HostDiscovery {
    private let session: URLSession
    private let batchSize: Int
    private let ports: [Int]
    private let probeTimeout: TimeInterval
    private let addressProvider: @Sendable () -> [IPv4Address]
    private let udpAnnounces: @Sendable () -> AsyncStream<UdpAnnounce>

    init(
        session: URLSession? = nil,
        batchSize: Int = 32,
        ports: [Int] = [AddressNormalizer.defaultHttpPort],
        probeTimeout: TimeInterval = 3,
        addressProvider: @escaping @Sendable () -> [IPv4Address] = HostDiscovery.localAddresses,
        udpAnnounces: @escaping @Sendable () -> AsyncStream<UdpAnnounce> = {
            UdpDiscovery.discoverAnnounces()
        }
    ) {
        self.batchSize = max(1, batchSize)
        self.ports = ports.isEmpty ? [AddressNormalizer.defaultHttpPort] : ports
        self.probeTimeout = probeTimeout
        self.addressProvider = addressProvider
        self.udpAnnounces = udpAnnounces

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = probeTimeout
            configuration.timeoutIntervalForResource = probeTimeout
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            // 局域网发现不经过系统代理，直连目标地址。
            configuration.connectionProxyDictionary = [:]
            self.session = URLSession(configuration: configuration)
        }
    }

    /// 先验证上次连接的主机，再扫描本机所在网段；UDP 与 HTTP 两路确认后流式吐出主机。
    func discover(
        lastKnownAddress: String?,
        onProgress: (@Sendable (String) async -> Void)? = nil
    ) -> AsyncStream<DiscoveredHost> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                async let udp: Void = self.discoverUdpHosts(
                    onProgress: onProgress,
                    yield: { host in _ = continuation.yield(host) }
                )
                async let http: Void = self.discoverHttpHosts(
                    lastKnownAddress: lastKnownAddress,
                    onProgress: onProgress,
                    yield: { host in _ = continuation.yield(host) }
                )
                _ = await (udp, http)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func discoverHttpHosts(
        lastKnownAddress: String?,
        onProgress: (@Sendable (String) async -> Void)?,
        yield: @escaping @Sendable (DiscoveredHost) -> Void
    ) async {
        var seenNodeIds = Set<String>()
        var seenAddresses = Set<String>()

        func accept(_ host: DiscoveredHost) {
            guard seenNodeIds.insert(host.nodeId).inserted else { return }
            guard seenAddresses.insert(host.address).inserted else { return }
            yield(host)
        }

        let saved = AddressNormalizer.normalize(lastKnownAddress ?? "")
        if !saved.isEmpty, let host = await probe(saved) {
            accept(host)
        }

        let pending = addressProvider()
            .flatMap { address in ports.map { "\(address):\($0)" } }
            .map { AddressNormalizer.normalize($0) }
            .filter { !$0.isEmpty && !seenAddresses.contains($0) }

        var start = 0
        while start < pending.count {
            let end = min(start + batchSize, pending.count)
            let batch = Array(pending[start..<end])
            if let onProgress, let first = batch.first, let colonIndex = first.firstIndex(of: ":") {
                let ip = first[..<colonIndex]
                let lastDot = ip.lastIndex(of: ".") ?? ip.startIndex
                await onProgress("正在查找 \(ip[..<lastDot]).x")
            }
            await withTaskGroup(of: DiscoveredHost?.self) { group in
                for candidate in batch {
                    group.addTask { await self.probe(candidate) }
                }
                for await result in group {
                    if let host = result {
                        accept(host)
                    }
                }
            }
            start = end
        }
    }

    private func discoverUdpHosts(
        onProgress: (@Sendable (String) async -> Void)?,
        yield: @escaping @Sendable (DiscoveredHost) -> Void
    ) async {
        var seenNodeIds = Set<String>()
        var seenAddresses = Set<String>()

        await onProgress?("正在通过局域网广播查找主机")
        for await announce in udpAnnounces() {
            if let host = await probe("\(announce.sourceIp):\(announce.httpPort)"),
               seenNodeIds.insert(host.nodeId).inserted,
               seenAddresses.insert(host.address).inserted {
                yield(host)
            }
        }
    }

    /// 请求 `GET /api/node-info` 并校验，返回可直接打开网页回放的主机。
    func probe(_ address: String) async -> DiscoveredHost? {
        let normalized = AddressNormalizer.normalize(address)
        guard !normalized.isEmpty,
              let url = URL(string: "http://\(normalized)/api/node-info") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = probeTimeout
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            let node = try JSONDecoder().decode(NodeInfo.self, from: data)
            guard node.isValidHost else { return nil }
            // 地址以「实际请求连接的 IP + node-info 返回的权威 httpPort」为准，
            // 不信任请求时用的候选端口，避免端口不一致/多网卡时把身份和地址混在一起。
            let host = normalized.split(separator: ":").first.map(String.init) ?? normalized
            return DiscoveredHost(
                nodeId: node.nodeId,
                nodeName: node.nodeName,
                address: "http://\(host):\(node.httpPort)",
                capabilitySummary: node.capabilitySummary,
                accessProtected: node.accessProtected
            )
        } catch {
            return nil
        }
    }

    /// 枚举活动 IPv4 网卡并按子网展开成待扫描的完整主机列表：
    /// 排除回环/隧道，私有网段优先，跳过网络号与广播地址。
    @Sendable static func localAddresses() -> [IPv4Address] {
        var candidates: [NetworkCandidate] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(first) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            defer { current = interface.pointee.ifa_next }

            let name = String(cString: interface.pointee.ifa_name)
            let flags = interface.pointee.ifa_flags
            guard (flags & UInt32(IFF_UP)) != 0,
                  (flags & UInt32(IFF_LOOPBACK)) == 0,
                  !name.hasPrefix("utun"),
                  !name.hasPrefix("awdl"),
                  !name.hasPrefix("llw"),
                  let addressPointer = interface.pointee.ifa_addr,
                  addressPointer.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let address = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                IPv4Address(UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
            }
            guard address.isUsableLanAddress else { continue }

            let mask: UInt32
            if let maskPointer = interface.pointee.ifa_netmask {
                mask = maskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
            } else {
                mask = 0xffffff00
            }

            candidates.append(NetworkCandidate(address: address, mask: mask, interfaceName: name))
        }

        return scanAddresses(for: candidates)
    }

    /// 与上游 GetLocalIpv4ScanAddresses 一致：每个网卡候选地址按其掩码展开子网。
    static func scanAddresses(for candidates: [NetworkCandidate]) -> [IPv4Address] {
        candidates
            .sorted {
                if $0.address.isPrivateLanAddress != $1.address.isPrivateLanAddress {
                    return $0.address.isPrivateLanAddress
                }
                if $0.interfaceName != $1.interfaceName {
                    return $0.interfaceName < $1.interfaceName
                }
                return $0.address.value < $1.address.value
            }
            .flatMap { candidate in
                SubnetEnumerator.enumerate(address: candidate.address, mask: candidate.mask)
            }
    }
}
