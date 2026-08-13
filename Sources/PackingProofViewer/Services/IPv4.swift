// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import Foundation

/// 按主机字节序保存的 IPv4 地址：高位字节是第一个八位组。
struct IPv4Address: Hashable, Sendable, CustomStringConvertible {
    let value: UInt32

    init(_ value: UInt32) {
        self.value = value
    }

    init?(string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            result = (result << 8) | UInt32(octet)
        }
        self.value = result
    }

    var description: String {
        "\((value >> 24) & 0xff).\((value >> 16) & 0xff).\((value >> 8) & 0xff).\(value & 0xff)"
    }

    /// 与上游 IsUsableLanAddress 一致：排除 0.x、APIPA、组播/广播与 RFC 2544 测试段。
    var isUsableLanAddress: Bool {
        let first = Int((value >> 24) & 0xff)
        let second = Int((value >> 16) & 0xff)
        if first == 0 { return false }
        if first == 169 && second == 254 { return false }
        if first >= 224 { return false }
        if first == 255 { return false }
        if first == 198 && (second == 18 || second == 19) { return false }
        return true
    }

    /// RFC 1918 私有网段。
    var isPrivateLanAddress: Bool {
        let first = Int((value >> 24) & 0xff)
        let second = Int((value >> 16) & 0xff)
        return first == 10
            || (first == 172 && second >= 16 && second <= 31)
            || (first == 192 && second == 168)
    }
}

enum SubnetEnumerator {
    static let maxSubnetDiscoveryHosts = 1022

    static func isContiguousMask(_ mask: UInt32) -> Bool {
        let inverted = ~mask
        return (inverted & (inverted &+ 1)) == 0
    }

    /// 与上游 EnumerateSubnetAddresses 一致：跳过网络号与广播地址；
    /// 掩码不连续时按 /24；主机数超过 1022 时退化为 /24。
    static func enumerate(address: IPv4Address, mask: UInt32) -> [IPv4Address] {
        var effectiveMask = isContiguousMask(mask) ? mask : 0xffffff00
        var network = address.value & effectiveMask
        var broadcast = network | ~effectiveMask
        var hostCount: UInt64 = broadcast > network ? UInt64(broadcast &- network &- 1) : 0

        if hostCount > UInt64(maxSubnetDiscoveryHosts) {
            effectiveMask = 0xffffff00
            network = address.value & effectiveMask
            broadcast = network | ~effectiveMask
            hostCount = broadcast > network ? UInt64(broadcast &- network &- 1) : 0
        }

        var result: [IPv4Address] = []
        result.reserveCapacity(Int(hostCount))
        var current = network &+ 1
        while current < broadcast {
            result.append(IPv4Address(current))
            current &+= 1
        }
        return result
    }
}
