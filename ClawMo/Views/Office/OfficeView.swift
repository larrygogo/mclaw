import SwiftUI

private let mcColors = Theme.greenPalette
private let mcGreen  = Theme.green
private let mcMint   = Theme.mint
private let mcBg     = Theme.bg

struct OfficeView: View {
    @Environment(AppStore.self) var store
    @Environment(ChatState.self) var chat
    @State private var selectedAgent: AgentInfo?

    var body: some View {
        NavigationStack {
            Group {
                if store.isConnecting {
                    connectingView
                } else if store.isPairingRequired {
                    pairingView
                } else if !store.isConnected {
                    notConnectedView
                } else {
                    officeScene
                }
            }
            .navigationTitle("办公室")
        }
        .sheet(item: $selectedAgent) { agent in
            AgentDetailSheet(agent: agent, state: chat.agentStates[agent.id])
        }
    }

    // MARK: - Office Scene

    var officeScene: some View {
        ScrollView {
            // Status summary
            statusBar
                .padding(.horizontal)
                .padding(.top, 8)

            // Agent cards
            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(store.agentList.enumerated()), id: \.element.id) { i, agent in
                    let state = chat.agentStates[agent.id]
                    AgentCard(agent: agent, state: state, colorIndex: i)
                        .onTapGesture { selectedAgent = agent }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(mcBg)
    }

    var statusBar: some View {
        let working = store.agentList.filter { chat.agentStates[$0.id]?.status == .working }.count
        let total = store.agentList.count

        return HStack(spacing: 12) {
            Circle()
                .fill(mcGreen)
                .frame(width: 6, height: 6)
            Text("\(working)/\(total) 工作中")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("Gateway 已连接")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    var connectingView: some View {
        VStack(spacing: 20) {
            OrbShape(radius: 40, glowColor: mcGreen, isActive: true)
                .frame(width: 100, height: 100)
            Text("连接中...")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(mcMint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(mcBg)
    }

    var pairingView: some View {
        VStack(spacing: 20) {
            OrbShape(radius: 30, glowColor: mcGreen.opacity(0.5), isActive: true)
                .frame(width: 80, height: 80)
            Text("需要设备配对")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(mcGreen)
            Text("请在 Gateway 管理界面批准此设备")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
            if let deviceId = store.pairingDeviceId {
                VStack(spacing: 8) {
                    if let reqId = store.pairingRequestId {
                        infoRow(label: "配对请求 ID", value: reqId)
                    }
                    infoRow(label: "设备 ID", value: deviceId)
                }
            }
            Button {
                Task {
                    if let active = store.gateways.first(where: { $0.id == store.activeGatewayId }) {
                        await store.connect(to: active)
                    }
                }
            } label: {
                Label("重试连接", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(mcGreen)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusXL).stroke(mcGreen.opacity(0.5)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(mcBg)
    }

    func infoRow(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(mcMint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    var notConnectedView: some View {
        VStack(spacing: 20) {
            OrbShape(radius: 30, glowColor: Color(white: 0.3), isActive: false)
                .frame(width: 80, height: 80)
            Text("未连接 Gateway")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            if let err = store.connectionError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Text("前往设置页添加并连接")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(mcBg)
    }
}

// MARK: - Orb Shape

struct OrbShape: View {
    let radius: CGFloat
    let glowColor: Color
    let isActive: Bool

    @State private var phase1 = false
    @State private var phase2 = false

    var body: some View {
        ZStack {
            // Outer soft glow — slow drift
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowColor.opacity(0.25), glowColor.opacity(0.06), .clear],
                            center: .center,
                            startRadius: radius * 0.3,
                            endRadius: radius * 2
                        )
                    )
                    .frame(width: radius * 3.5, height: radius * 3.5)
                    .opacity(phase1 ? 0.9 : 0.5)
                    .animation(
                        .sinusoidal(duration: 4).repeatForever(autoreverses: true),
                        value: phase1
                    )
            }

            // Outer ring
            Circle()
                .stroke(.white.opacity(isActive ? 0.12 : 0.08), lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)

            // Mid fill — gentle size breath
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            glowColor.opacity(isActive ? 0.4 : 0.08),
                            glowColor.opacity(isActive ? 0.15 : 0.03),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius * 0.9
                    )
                )
                .frame(width: radius * 2, height: radius * 2)
                .scaleEffect(isActive ? (phase2 ? 0.75 : 0.6) : 0.3)
                .animation(
                    .sinusoidal(duration: 3).repeatForever(autoreverses: true),
                    value: phase2
                )

            // Inner bright core
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.5), glowColor.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: radius * 0.35
                        )
                    )
                    .frame(width: radius * 0.6, height: radius * 0.6)
                    .opacity(phase1 ? 0.8 : 0.5)
                    .animation(
                        .sinusoidal(duration: 3.5).repeatForever(autoreverses: true),
                        value: phase1
                    )
            }
        }
        .onAppear {
            phase1 = true
            // Offset second phase slightly for organic feel
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                phase2 = true
            }
        }
    }
}

// Smooth sinusoidal-like timing curve
extension Animation {
    static func sinusoidal(duration: Double) -> Animation {
        .timingCurve(0.45, 0.05, 0.55, 0.95, duration: duration)
    }
}

// MARK: - Agent Card

struct AgentCard: View {
    let agent: AgentInfo
    let state: AgentState?
    let colorIndex: Int

    var status: AgentStatus { state?.status ?? .offline }

    var accentColor: Color {
        switch status {
        case .working: mcColors[colorIndex % mcColors.count]
        case .idle: Color(white: 0.35)
        case .waiting: Color(hex: "ffd600")
        case .offline: Color(white: 0.2)
        }
    }

    var statusLabel: String {
        switch status {
        case .working: "工作中"
        case .idle: "空闲"
        case .waiting: "等待中"
        case .offline: "离线"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Avatar with glow
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surface3)
                    .frame(width: 46, height: 46)
                AvatarIcon(avatar: agent.avatar, color: status == .working ? accentColor : .white.opacity(0.4), size: 46, agentId: agent.id)
            }

            // Name + status
            VStack(spacing: 4) {
                Text(UserDefaults.standard.string(forKey: "agent_name_\(agent.id)") ?? agent.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 5, height: 5)
                    Text(statusLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(accentColor)
                }

                if let error = state?.lastError {
                    Text(error)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                } else {
                    let task = (status == .working ? state?.currentTask : nil) ?? " "
                    Text(task)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .opacity(task == " " ? 0 : 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
    }
}

// MARK: - Agent Detail Sheet

struct AgentDetailSheet: View {
    let agent: AgentInfo
    let state: AgentState?

    @Environment(\.dismiss) var dismiss
    @Environment(AppStore.self) var store
    @State private var showIconPicker = false
    @State private var isEditingName = false
    @State private var editedName = ""

    var status: AgentStatus { state?.status ?? .offline }

    var displayName: String {
        UserDefaults.standard.string(forKey: "agent_name_\(agent.id)") ?? agent.name
    }

    var statusColor: Color {
        switch status {
        case .working: mcGreen
        case .idle: .gray
        case .waiting: .orange
        case .offline: Color(white: 0.3)
        }
    }

    var statusLabel: String {
        switch status {
        case .working: "工作中"
        case .idle: "空闲"
        case .waiting: "等待中"
        case .offline: "离线"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Drag indicator
            Capsule()
                .fill(.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            // Avatar
            Button {
                showIconPicker = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Theme.surface3)
                            .frame(width: 80, height: 80)
                        AvatarIcon(avatar: agent.avatar, color: Color(hex: agent.color), size: 80, agentId: agent.id)
                    }
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textSecondary)
                        .background(Circle().fill(mcBg).frame(width: 20, height: 20))
                }
            }
            .buttonStyle(.plain)

            // Name & status
            VStack(spacing: 6) {
                if isEditingName {
                    HStack(spacing: 8) {
                        TextField("名称", text: $editedName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .onSubmit { saveName() }
                        Button {
                            saveName()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(mcGreen)
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    Button {
                        editedName = displayName
                        isEditingName = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(displayName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(statusColor)
                }
            }

            // Current task
            if let task = state?.currentTask, !task.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前任务")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(task)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.radiusM))
                }
                .padding(.horizontal, 20)
            }

            // Chat button
            Button {
                let convId = "user:\(agent.id)"
                store.pendingAgent = agent
                store.unhideConversation(convId)
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.3))
                    store.selectedTab = 1
                    try? await Task.sleep(for: .seconds(0.1))
                    store.pendingConversationId = convId
                }
            } label: {
                Text("发消息")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(mcGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(mcGreen.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(mcBg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showIconPicker) {
            IconPickerSheet(agentId: agent.id)
        }
    }

    private func saveName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == agent.name {
            UserDefaults.standard.removeObject(forKey: "agent_name_\(agent.id)")
        } else {
            UserDefaults.standard.set(trimmed, forKey: "agent_name_\(agent.id)")
        }
        NotificationCenter.default.post(name: .agentAvatarChanged, object: nil)
        isEditingName = false
    }
}

// MARK: - Icon Picker

struct IconPickerSheet: View {
    let agentId: String
    @Environment(\.dismiss) private var dismiss

    private let icons: [(String, [String])] = [
        ("常用", ["star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill",
                  "moon.fill", "sun.max.fill", "cloud.fill", "snowflake", "drop.fill"]),
        ("工具", ["wrench.and.screwdriver", "hammer.fill", "gearshape.fill", "terminal.fill",
                  "laptopcomputer", "desktopcomputer", "keyboard", "printer.fill",
                  "externaldrive.fill", "cpu.fill"]),
        ("通讯", ["message.fill", "envelope.fill", "phone.fill", "video.fill",
                  "antenna.radiowaves.left.and.right", "wifi", "globe",
                  "paperplane.fill", "megaphone.fill", "bell.fill"]),
        ("人物", ["person.fill", "person.2.fill", "person.3.fill", "figure.stand",
                  "brain.head.profile", "eyes", "hand.raised.fill",
                  "figure.walk", "figure.run", "figure.mind.and.body"]),
        ("符号", ["magnifyingglass", "doc.fill", "folder.fill", "book.fill",
                  "bookmark.fill", "tag.fill", "flag.fill", "mappin",
                  "building.columns", "map"]),
        ("动物", ["pawprint.fill", "hare.fill", "tortoise.fill", "bird.fill",
                  "fish.fill", "ant.fill", "ladybug.fill", "cat.fill",
                  "dog.fill", "lizard.fill"]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Reset button
                    Button {
                        UserDefaults.standard.removeObject(forKey: "agent_avatar_\(agentId)")
                        NotificationCenter.default.post(name: .agentAvatarChanged, object: nil)
                        dismiss()
                    } label: {
                        Text("恢复默认")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 16)

                    ForEach(icons, id: \.0) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.0)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 16)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                                ForEach(section.1, id: \.self) { icon in
                                    Button {
                                        UserDefaults.standard.set(icon, forKey: "agent_avatar_\(agentId)")
                                        NotificationCenter.default.post(name: .agentAvatarChanged, object: nil)
                                        dismiss()
                                    } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Theme.surface2)
                                                .frame(width: 56, height: 56)
                                            Image(systemName: icon)
                                                .font(.system(size: 24))
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Theme.bg)
            .navigationTitle("选择图标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.bg)
    }
}
