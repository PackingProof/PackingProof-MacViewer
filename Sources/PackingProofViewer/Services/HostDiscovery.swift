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

    init(
        session: URLSession? = nil,
        batchSize: Int = 32,
        ports: [Int] = [AddressNormalizer.defaultHttpPort],
        probeTimeout: TimeInterval = 3,
        addressProvider: @escaping @Sendable () -> [IPv4Address] = HostDiscovery.localAddresses
    ) {
        self.batchSize = max(1, batchSize)
        self.ports = ports.isEmpty ? [AddressNormalizer.defaultHttpPort] : ports
        self.probeTimeout = probeTimeout
        self.addressProvider = addressProvider

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

    /// 先验证上次连接的主机，再扫描本机所在网段；按 nodeId 去重。
    func discover(
        lastKnownAddress: String?,
        onProgress: (@Sendable (String) async -> Void)? = nil
    ) async -> [DiscoveredHost] {
        var hosts: [DiscoveredHost] = []
        var seenNodeIds = Set<String>()
        var seenAddresses = Set<String>()

        func accept(_ host: DiscoveredHost) {
            guard seenNodeIds.insert(host.nodeId).inserted else { return }
            guard seenAddresses.insert(host.address).inserted else { return }
            hosts.append(host)
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

        return hosts
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
            return DiscoveredHost(
                nodeId: node.nodeId,
                nodeName: node.nodeName,
                address: "http://\(normalized)",
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
