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
    @State private var swipedId: String?
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
                        VStack(spacing: 10) {
                            ForEach(store.gateways) { gw in
                                GatewayRow(
                                    config: gw,
                                    isConnected: store.isConnected && gw.id == store.activeGatewayId,
                                    isConnecting: connectingId == gw.id,
                                    swipedId: $swipedId,
                                    onConnect: { connectTo(gw) },
                                    onDisconnect: { store.disconnect() },
                                    onEdit: { editingGateway = gw },
                                    onDelete: { store.deleteGateway(id: gw.id) }
                                )
                            }
                        }
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
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2), lineWidth: 1))
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
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))

                    sectionHeader(title: "关于", icon: "info.circle")

                    VStack(spacing: 0) {
                        infoRow(label: "版本", value: "1.0.0")
                        divider
                        infoRow(label: "构建", value: "Debug")
                    }
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
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
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
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
    @Binding var swipedId: String?
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    private let actionWidth: CGFloat = 120

    private var isOpen: Bool { swipedId == config.id }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Swipe action buttons (behind the card)
            HStack(spacing: 12) {
                Spacer()
                Button(action: { withAnimation { swipedId = nil; offset = 0 }; onEdit() }) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.12)).frame(width: 40, height: 40)
                        Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                Button(action: { withAnimation { swipedId = nil; offset = 0 }; onDelete() }) {
                    ZStack {
                        Circle().fill(Color.red.opacity(0.7)).frame(width: 40, height: 40)
                        Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 14)

            // Card content (must cover action buttons at offset=0)
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
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "161620"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let translation = value.translation.width
                        if translation < 0 {
                            // Close any other open row first
                            if swipedId != nil && swipedId != config.id {
                                swipedId = nil
                            }
                            offset = max(translation, -actionWidth)
                        } else if isOpen {
                            offset = min(-actionWidth + translation, 0)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            if offset < -actionWidth / 2 {
                                offset = -actionWidth
                                swipedId = config.id
                            } else {
                                offset = 0
                                if swipedId == config.id { swipedId = nil }
                            }
                        }
                    }
            )
            .onTapGesture {
                if isOpen {
                    withAnimation(.easeOut(duration: 0.2)) { offset = 0; swipedId = nil }
                }
            }
            .onChange(of: swipedId) {
                // Another row opened → close this one
                if swipedId != config.id && offset != 0 {
                    withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                }
            }
        }
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
                    let config = GatewayConfig(
                        id: existingId ?? UUID().uuidString,
                        name: name, url: url, token: token
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
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }
}
