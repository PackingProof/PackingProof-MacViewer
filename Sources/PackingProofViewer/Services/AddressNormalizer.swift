// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import Foundation

/// 复刻上游 `WorkstationNetwork.NormalizeAddress` 与 `ParseHostConnectionInput` 语义。
enum AddressNormalizer {
    static let defaultHttpPort = 5280

    static func normalize(_ input: String, defaultPort: Int = defaultHttpPort) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           let host = url.host, !host.isEmpty {
            let port = url.port ?? defaultPort
            return "\(host):\(port)"
        }

        if text.lowercased().hasPrefix("http://") {
            text.removeFirst("http://".count)
        } else if text.lowercased().hasPrefix("https://") {
            text.removeFirst("https://".count)
        }

        if let suffixIndex = text.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            text = String(text[..<suffixIndex])
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        if text.isEmpty {
            return ""
        }
        return text.contains(":") ? text : "\(text):\(defaultPort)"
    }

    /// 解析手动连接输入；返回值分别为 `host:port` 与访问密钥。
    static func parseConnection(_ input: String) -> (address: String, accessKey: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           let host = url.host, !host.isEmpty {
            let port = url.port ?? defaultHttpPort
            var accessKey = ""
            if let query = url.query {
                for item in query.split(separator: "&", omittingEmptySubsequences: false) {
                    let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    if pair.count == 2,
                       pair[0].removingPercentEncoding?.caseInsensitiveCompare("key") == .orderedSame {
                        accessKey = pair[1].removingPercentEncoding ?? ""
                        break
                    }
                }
            }
            return ("\(host):\(port)", accessKey)
        }
        return (normalize(text), "")
    }
}
