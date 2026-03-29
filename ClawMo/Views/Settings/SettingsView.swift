import SwiftUI

private let mcGreen = Theme.green
private let mcMint  = Theme.mint
private let mcBg    = Theme.bg

struct SettingsView: View {
    @Environment(AppStore.self) var store
    @State private var showAddSheet = false
    @State private var editingGateway: GatewayConfig?
    @State private var connectingId: String?
    @State private var errorMessage: String?
    @State private var duplicateWarning = false
    @State private var showClearConfirm = false
    @State private var cacheSize: String = "计算中..."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    sectionHeader(title: "GATEWAY 连接", icon: "antenna.radiowaves.left.and.right")

                    if store.gateways.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(store.gateways) { gw in
                                GatewayRow(
                                    config: gw,
                                    isConnected: store.isConnected && gw.id == store.activeGatewayId,
                                    isConnecting: connectingId == gw.id,
                                    onConnect: { connectTo(gw) },
                                    onDisconnect: { store.disconnect() }
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        store.deleteGateway(id: gw.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    Button {
                                        editingGateway = gw
                                    } label: {
                                        Image(systemName: "square.and.pencil")
                                    }
                                    .tint(mcGreen)
                                }
                                .listRowBackground(Color.white.opacity(0.04))
                                .listRowSeparatorTint(.white.opacity(0.04))
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .frame(height: max(CGFloat(store.gateways.count) * 60, 60))
                    }

                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.orange.opacity(0.8))
                            Spacer()
                            Button { errorMessage = nil } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusM))
                                            }

                    sectionHeader(title: "数据", icon: "externaldrive")

                    VStack(spacing: 0) {
                        infoRow(label: "消息缓存", value: cacheSize)
                        divider
                        Button {
                            showClearConfirm = true
                        } label: {
                            HStack {
                                Text("清理缓存")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.red.opacity(0.8))
                                Spacer()
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red.opacity(0.5))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.radiusM))
                    
                    sectionHeader(title: "关于", icon: "info.circle")

                    VStack(spacing: 0) {
                        infoRow(label: "版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                        #if DEBUG
                        divider
                        infoRow(label: "构建", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
                        #endif
                    }
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.radiusM))
                                    }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .background(mcBg)
            .navigationTitle("设置")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus.circle").foregroundStyle(mcGreen)
                    }
                }
            }
            .navigationDestination(isPresented: $showAddSheet) {
                GatewayEditSheet(mode: .add) { config in
                    if store.gateways.contains(where: { $0.url == config.url && $0.token == config.token }) {
                        duplicateWarning = true
                    } else {
                        store.addGateway(config)
                    }
                }
            }
            .navigationDestination(item: $editingGateway) { gw in
                GatewayEditSheet(mode: .edit(gw)) { updated in
                    if let i = store.gateways.firstIndex(where: { $0.id == updated.id }) {
                        store.gateways[i] = updated
                        store.saveGateways()
                    }
                }
            }
            .onAppear { cacheSize = store.getCacheSize() }
            .alert("确认清理", isPresented: $showClearConfirm) {
                Button("清理", role: .destructive) {
                    store.clearCache()
                    cacheSize = store.getCacheSize()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除所有本地缓存的消息记录，不影响服务器数据。")
            }
            .alert("重复配置", isPresented: $duplicateWarning) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("已存在相同 URL 和 Token 的 Gateway 配置")
            }
        }
    }

    private func connectTo(_ gw: GatewayConfig) {
        Task {
            connectingId = gw.id
            errorMessage = nil
            await store.connect(to: gw)
            connectingId = nil
            if let err = store.connectionError {
                errorMessage = err
                // Auto dismiss after 3 seconds
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if errorMessage == err { errorMessage = nil }
                }
            }
        }
    }

    func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(mcGreen.opacity(0.6))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
        }
        .padding(.top, 8)
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.12))
            Text("暂无配置")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
            Text("点击右上角 + 添加 Gateway")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: Theme.radiusM))
            }

    func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.leading, 14)
    }
}

// MARK: - Gateway Row (swipe actions)

struct GatewayRow: View {
    let config: GatewayConfig
    let isConnected: Bool
    let isConnecting: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: isConnected ? onDisconnect : onConnect) {
                ZStack {
                    Circle()
                        .fill(isConnected ? mcGreen.opacity(0.15) : Color.white.opacity(0.05))
                        .frame(width: 36, height: 36)
                    if isConnecting {
                        ProgressView().controlSize(.small).tint(mcGreen)
                    } else {
                        Image(systemName: isConnected ? "powerplug.fill" : "powerplug")
                            .font(.system(size: 14))
                            .foregroundStyle(isConnected ? mcGreen : .white.opacity(0.3))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(config.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    if isConnected {
                        Text("已连接")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(mcGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(mcGreen.opacity(0.15), in: Capsule())
                    }
                }
                Text(config.url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
    }
}

// MARK: - Gateway Edit Sheet (add / edit)

struct GatewayEditSheet: View {
    enum Mode: Identifiable {
        case add
        case edit(GatewayConfig)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let c): return c.id
            }
        }
    }

    let mode: Mode
    let onSave: (GatewayConfig) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var token = ""
    @State private var urlError = ""

    private var isEdit: Bool {
        if case .edit = mode { return true } else { return false }
    }

    private var existingId: String? {
        if case .edit(let c) = mode { return c.id } else { return nil }
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                sectionLabel("基本信息")
                inputField(title: "名称", placeholder: "如：我的团队", text: $name)
                inputField(title: "Gateway URL", placeholder: "ws://...", text: $url)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: url) { urlError = "" }
                if !urlError.isEmpty {
                    Text(urlError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                }
            }

            VStack(spacing: 16) {
                sectionLabel("认证")
                inputField(title: "Token", placeholder: "可选", text: $token)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .background(mcBg)
        .navigationTitle(isEdit ? "编辑 Gateway" : "添加 Gateway")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEdit ? "保存" : "添加") {
                    let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let parsed = URL(string: trimmedUrl),
                          let scheme = parsed.scheme?.lowercased(),
                          (scheme == "ws" || scheme == "wss"),
                          parsed.host != nil else {
                        urlError = "请输入有效的 WebSocket 地址 (ws:// 或 wss://)"
                        return
                    }
                    urlError = ""
                    let config = GatewayConfig(
                        id: existingId ?? UUID().uuidString,
                        name: name, url: trimmedUrl, token: token
                    )
                    onSave(config)
                    dismiss()
                }
                .foregroundStyle(name.isEmpty || url.isEmpty ? .white.opacity(0.2) : mcGreen)
                .disabled(name.isEmpty || url.isEmpty)
            }
        }
        .onAppear {
            if case .edit(let c) = mode {
                name = c.name
                url = c.url
                token = c.token
            }
        }
    }

    func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
        }
    }

    func inputField(title: String, placeholder: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 14))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.radiusM))
                    }
    }
}
