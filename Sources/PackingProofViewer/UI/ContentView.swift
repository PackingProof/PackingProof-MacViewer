// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import AppKit
import SwiftUI

@MainActor
final class ViewerModel: ObservableObject {
    @Published var hosts: [DiscoveredHost] = []
    @Published var status = "正在搜索同一网络中的主机"
    @Published var isSearching = false
    @Published var isOpeningWeb = false
    @Published var selectedHostId: String?

    private let discovery: HostDiscovery
    private let enrollment: EnrollmentService
    private let probe: WebAccessProbe
    private let keyStore: any WebAccessKeyStoring
    private let openURL: (URL) -> Bool

    private enum Keys {
        static let address = "LastKnownHostAddress"
        static let nodeId = "LastKnownHostNodeId"
        static let nodeName = "LastKnownHostNodeName"
    }

    init(
        discovery: HostDiscovery = HostDiscovery(),
        enrollment: EnrollmentService = EnrollmentService(),
        probe: WebAccessProbe = WebAccessProbe(),
        keyStore: any WebAccessKeyStoring = FileWebAccessKeyStore(),
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.discovery = discovery
        self.enrollment = enrollment
        self.probe = probe
        self.keyStore = keyStore
        self.openURL = openURL
    }

    var lastKnownAddress: String? {
        UserDefaults.standard.string(forKey: Keys.address)
    }

    var selectedHost: DiscoveredHost? {
        guard let selectedHostId else { return nil }
        return hosts.first { $0.nodeId == selectedHostId }
    }

    func search() async {
        guard !isSearching else { return }
        isSearching = true
        status = lastKnownAddress == nil
            ? "正在搜索同一网络中的主机"
            : "正在验证上次连接的主机"
        defer { isSearching = false }

        let found = await discovery.discover(lastKnownAddress: lastKnownAddress) { text in
            await MainActor.run { self.status = text }
        }
        hosts = found

        if let rememberedNodeId = UserDefaults.standard.string(forKey: Keys.nodeId),
           found.contains(where: { $0.nodeId == rememberedNodeId }) {
            selectedHostId = rememberedNodeId
        }

        if found.isEmpty {
            status = "没有找到主机，请检查两台电脑是否连接同一网络"
        } else if found.count == 1 {
            status = "找到 1 台主机，确认后即可连接"
        } else {
            status = "找到 \(found.count) 台主机，请选择要连接的主机"
        }
    }

    func clearRememberedHost() async {
        if let address = lastKnownAddress {
            keyStore.deleteKey(for: address)
        }
        UserDefaults.standard.removeObject(forKey: Keys.address)
        UserDefaults.standard.removeObject(forKey: Keys.nodeId)
        UserDefaults.standard.removeObject(forKey: Keys.nodeName)
        selectedHostId = nil
        await search()
    }

    func openWebPlayback() async {
        guard !isOpeningWeb else { return }
        guard let host = selectedHost ?? hosts.first else {
            status = "请先选择一台主机"
            return
        }

        isOpeningWeb = true
        defer { isOpeningWeb = false }
        let address = host.address
        switch host.accessProtected {
        case .some(false):
            openBrowser(host.webURL)
        case .some(true):
            await openProtected(address: address)
        case .none:
            await openLegacy(address: address)
        }
    }

    /// 返回 nil 表示连接成功，否则返回错误文案。
    func connectManually(_ input: String) async -> String? {
        let parsed = AddressNormalizer.parseConnection(input)
        guard !parsed.address.isEmpty else {
            return "请输入主机地址或连接链接"
        }
        status = "正在连接 \(parsed.address)…"
        guard let host = await discovery.probe(parsed.address) else {
            status = "无法连接该主机，请检查地址与网络"
            return "无法连接该主机，请检查地址与网络"
        }
        remember(host)
        if !parsed.accessKey.isEmpty {
            keyStore.save(parsed.accessKey, for: host.address)
        }
        if let index = hosts.firstIndex(where: { $0.nodeId == host.nodeId }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        selectedHostId = host.nodeId
        status = "已连接：\(host.nodeName)（\(host.address)）"
        return nil
    }

    private func remember(_ host: DiscoveredHost) {
        UserDefaults.standard.set(host.address, forKey: Keys.address)
        UserDefaults.standard.set(host.nodeId, forKey: Keys.nodeId)
        UserDefaults.standard.set(host.nodeName, forKey: Keys.nodeName)
    }

    private func openBrowser(_ url: URL?) {
        guard let url, openURL(url) else {
            status = "打开网页回放失败"
            return
        }
        status = "已在浏览器中打开网页回放"
    }

    /// 受保护主机：有 key 先预检；401 则清除旧 key、自动申请一次并再次预检；
    /// 只有预检通过才打开浏览器，申请成功不直接信任返回链接。
    private func openProtected(address: String) async {
        if let key = keyStore.key(for: address), !key.isEmpty {
            let result = await probe.probe(address: address, key: key)
            switch result {
            case .authorized:
                openBrowser(URL(string: WebAccessProbe.buildWebAccessURL(address: address, key: key)))
                return
            case .failed:
                status = "无法连接保存主机网页，请检查网络后重试"
                return
            case .unauthorized:
                keyStore.deleteKey(for: address)
            }
        }

        status = "正在请求保存主机允许连接"
        do {
            let webAccessUrl = try await enrollment.enroll(address: address)
            let parsed = AddressNormalizer.parseConnection(webAccessUrl)
            guard !parsed.accessKey.isEmpty else {
                status = EnrollmentError.missingWebAccessUrl.message
                return
            }
            let result = await probe.probe(address: address, key: parsed.accessKey)
            guard result == .authorized else {
                status = "网页访问验证失败，请在保存主机上确认后重试"
                return
            }
            keyStore.save(parsed.accessKey, for: address)
            openBrowser(URL(string: WebAccessProbe.buildWebAccessURL(address: address, key: parsed.accessKey)))
        } catch let error as EnrollmentError {
            status = "未取得网页访问权限：\(error.message)"
        } catch {
            status = "未取得网页访问权限，请稍后重试"
        }
    }

    /// 旧主机不返回 accessProtected：先裸地址预检，再尝试已存 key；
    /// 都失败时提示升级或粘贴链接，绝不无认证拉起浏览器。
    private func openLegacy(address: String) async {
        let bare = await probe.probe(address: address, key: nil)
        switch bare {
        case .authorized:
            openBrowser(URL(string: WebAccessProbe.buildWebAccessURL(address: address, key: nil)))
            return
        case .failed:
            status = "无法连接保存主机网页，请检查网络后重试"
            return
        case .unauthorized:
            break
        }

        if let key = keyStore.key(for: address), !key.isEmpty {
            let keyed = await probe.probe(address: address, key: key)
            if keyed == .authorized {
                openBrowser(URL(string: WebAccessProbe.buildWebAccessURL(address: address, key: key)))
                return
            }
        }

        status = "保存主机版本过旧或已开启访问保护，请更新保存主机，或使用“手动连接”粘贴完整链接"
    }
}

struct ContentView: View {
    @StateObject private var model = ViewerModel()
    @State private var showManualConnection = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            hostList
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await model.search() }
        .sheet(isPresented: $showManualConnection) {
            ManualConnectionView { input in
                await model.connectManually(input)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("PackingProof 查看端")
                    .font(.headline)
                Text("只连接主机查看")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(model.hosts.isEmpty ? Color.secondary.opacity(0.45) : AppTheme.successGreen)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private static var appIcon: NSImage {
        NSApp.applicationIconImage
            ?? NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)
            ?? NSImage()
    }

    private var hostList: some View {
        Group {
            if model.hosts.isEmpty {
                VStack(spacing: 8) {
                    if model.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: AppTheme.Symbol.noHost)
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                        Text("未找到主机")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.hosts) { host in
                            HostCard(
                                host: host,
                                isSelected: host.nodeId == model.selectedHostId
                            ) {
                                model.selectedHostId = host.nodeId
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                if model.isSearching || model.isOpeningWeb {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    Task { await model.search() }
                } label: {
                    Label("重新搜索", systemImage: AppTheme.Symbol.search)
                }
                .disabled(model.isSearching)

                Button {
                    showManualConnection = true
                } label: {
                    Label("手动连接", systemImage: AppTheme.Symbol.manualConnect)
                }

                Button {
                    Task { await model.clearRememberedHost() }
                } label: {
                    Label("更换主机", systemImage: AppTheme.Symbol.changeHost)
                }

                Spacer()

                Button {
                    Task { await model.openWebPlayback() }
                } label: {
                    Label("打开网页回放", systemImage: AppTheme.Symbol.play)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentBlue)
                .disabled(model.selectedHost == nil || model.isOpeningWeb)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct HostCard: View {
    let host: DiscoveredHost
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(host.nodeName)
                    .font(.callout.weight(.semibold))
                Text(host.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if !host.capabilitySummary.isEmpty {
                Text(host.capabilitySummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                    ? AppTheme.accentBlue.opacity(0.12)
                    : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isSelected ? AppTheme.accentBlue : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: action)
    }
}

private struct ManualConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var errorText: String?
    @State private var isConnecting = false

    let onConnect: (String) async -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("手动连接主机")
                .font(.headline)

            TextField("例如 192.168.1.5:5280 或带 key 的完整链接", text: $input)
                .textFieldStyle(.roundedBorder)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.errorRed)
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button {
                    connect()
                } label: {
                    Label("连接", systemImage: AppTheme.Symbol.manualConnect)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentBlue)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
            }
        }
        .padding(20)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        errorText = nil
        let value = input
        Task {
            let error = await onConnect(value)
            if let error {
                errorText = error
                isConnecting = false
            } else {
                dismiss()
            }
        }
    }
}
