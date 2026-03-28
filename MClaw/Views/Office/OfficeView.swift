import SwiftUI

// MARK: - MClaw color palette

private let mcColors: [Color] = [
    Color(hex: "39ff14"),
    Color(hex: "32cd32"),
    Color(hex: "00ff41"),
    Color(hex: "0fff50"),
    Color(hex: "7fff00"),
    Color(hex: "76ff03"),
    Color(hex: "39ff14"),
    Color(hex: "00e676"),
    Color(hex: "69f0ae"),
    Color(hex: "b2ff59"),
]

private let mcGreen  = Color(hex: "39ff14")
private let mcMint   = Color(hex: "b6ffa8")
private let mcBg     = Color(hex: "0a0a0f")

struct OfficeView: View {
    @Environment(AppStore.self) var store
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
            AgentDetailSheet(agent: agent, state: store.agentStates[agent.id])
        }
    }

    // MARK: - Office Scene

    var officeScene: some View {
        ScrollView {
            // Status summary
            statusBar
                .padding(.horizontal)
                .padding(.top, 8)

            // Agent orbs
            let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(Array(store.agentList.enumerated()), id: \.element.id) { i, agent in
                    let state = store.agentStates[agent.id]
                    AgentOrb(agent: agent, state: state, colorIndex: i)
                        .onTapGesture { selectedAgent = agent }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(mcBg)
    }

    var statusBar: some View {
        let working = store.agentList.filter { store.agentStates[$0.id]?.status == .working }.count
        let total = store.agentList.count

        return HStack(spacing: 12) {
            Circle()
                .fill(mcGreen)
                .frame(width: 6, height: 6)
            Text("\(working)/\(total) 工作中")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(mcMint.opacity(0.7))
            Spacer()
            Text("Gateway 已连接")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
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
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(mcGreen.opacity(0.5)))
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
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
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

// MARK: - Agent Orb

struct AgentOrb: View {
    let agent: AgentInfo
    let state: AgentState?
    let colorIndex: Int

    var status: AgentStatus { state?.status ?? .offline }

    var orbColor: Color {
        switch status {
        case .working: mcColors[colorIndex % mcColors.count]
        case .idle: Color(white: 0.25)
        case .waiting: Color(hex: "ffd600")
        case .offline: Color(white: 0.15)
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
        VStack(spacing: 12) {
            // Orb
            ZStack {
                OrbShape(
                    radius: 36,
                    glowColor: orbColor,
                    isActive: status == .working
                )

                // Agent icon
                AvatarIcon(avatar: agent.avatar, color: status == .working ? .white : .white.opacity(0.4), size: 44)
            }
            .frame(width: 120, height: 120)

            // Info
            VStack(spacing: 4) {
                Text(agent.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(status == .working ? orbColor : .white.opacity(0.3))

                if let task = state?.currentTask, !task.isEmpty, status == .working {
                    Text(task)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 140)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Agent Detail Sheet

struct AgentDetailSheet: View {
    let agent: AgentInfo
    let state: AgentState?

    @Environment(\.dismiss) var dismiss

    var status: AgentStatus { state?.status ?? .offline }

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

            // Orb
            ZStack {
                OrbShape(radius: 40, glowColor: statusColor, isActive: status == .working)
                AvatarIcon(avatar: agent.avatar, color: .white, size: 56)
            }
            .frame(width: 120, height: 120)

            // Name & status
            VStack(spacing: 6) {
                Text(agent.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

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
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(mcBg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Avatar Icon (emoji or SF Symbol)

struct AvatarIcon: View {
    let avatar: String
    let color: Color
    let size: CGFloat

    private var isSFSymbol: Bool {
        !avatar.isEmpty && avatar.allSatisfy { $0.isASCII }
    }

    var body: some View {
        if isSFSymbol {
            Image(systemName: avatar)
                .font(.system(size: size * 0.45, weight: .light))
                .foregroundStyle(color)
        } else {
            Text(verbatim: avatar)
                .font(.system(size: size * 0.5))
        }
    }
}
