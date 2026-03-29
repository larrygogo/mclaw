import Foundation
import UIKit

enum MockDataProvider {

    static let avatars = ["star.fill", "building.columns", "laptopcomputer", "magnifyingglass", "map",
                          "wrench.and.screwdriver", "lightbulb", "target", "flask", "safari"]

    static func load(into store: AppStore) {
        let colors = Theme.agentColors

        store.isMockMode = true
        store.isConnected = true
        store.activeGatewayId = "mock"

        let mockAgents: [(String, String, String?, AgentStatus)] = [
            ("小南",     "star.fill",          "协调团队处理 PR #42",           .working),
            ("筑基",     "building.columns",    nil,                           .idle),
            ("码匠",     "laptopcomputer",      "实现看板拖拽功能...",           .working),
            ("探针",     "magnifyingglass",     "running integration tests",   .working),
            ("寻路",     "map",                 nil,                           .idle),
        ]

        store.agentList = mockAgents.enumerated().map { i, m in
            AgentInfo(id: "agent-\(i)", name: m.0, avatar: m.1, color: colors[i % colors.count])
        }

        for (i, m) in mockAgents.enumerated() {
            let id = "agent-\(i)"
            var state = AgentState(id: id, status: m.3)
            state.currentTask = m.2
            state.lastActivity = Date()
            store.agentStates[id] = state
        }

        let now = Date()
        let sk0 = "agent:agent-0:main"
        let sk2 = "agent:agent-2:main"
        let sk3 = "agent:agent-3:main"
        let a2a_02 = "agent:agent-2:subagent:aaa"
        let a2a_03 = "agent:agent-3:subagent:bbb"
        let a2a_04 = "agent:agent-4:subagent:ccc"

        store.conversations = [
            Conversation(id: "user:agent-0", sessionKey: sk0, sessionKeys: [sk0], agentId: "agent-0",
                         displayName: "小南", avatar: "star.fill", color: colors[0], kind: .user,
                         lastMessageText: "PR #42 已经审查完毕，修复建议已添加。",
                         lastTimestamp: now.addingTimeInterval(-120), historyLoaded: true, fullyLoaded: true),
            Conversation(id: "user:agent-2", sessionKey: sk2, sessionKeys: [sk2], agentId: "agent-2",
                         displayName: "码匠", avatar: "laptopcomputer", color: colors[2], kind: .user,
                         lastMessageText: "看板功能的前端已完成，等待 QA 验收。",
                         lastTimestamp: now.addingTimeInterval(-300), historyLoaded: true, fullyLoaded: true),
            Conversation(id: "user:agent-3", sessionKey: sk3, sessionKeys: [sk3], agentId: "agent-3",
                         displayName: "探针", avatar: "magnifyingglass", color: colors[3], kind: .user,
                         lastMessageText: "58/58 用例全部通过，无回归问题。",
                         lastTimestamp: now.addingTimeInterval(-600), historyLoaded: true, fullyLoaded: true),
            {
                var c = Conversation(id: "a2a:agent-0:agent-2", sessionKey: a2a_02, sessionKeys: [a2a_02], agentId: "agent-2",
                             displayName: "小南", avatar: "star.fill", color: colors[0], kind: .a2a,
                             lastMessageText: "feat/kanban 分支代码已提交。",
                             lastTimestamp: now.addingTimeInterval(-200), historyLoaded: true, fullyLoaded: true)
                c.secondaryName = "码匠"; c.secondaryAvatar = "laptopcomputer"
                return c
            }(),
            {
                var c = Conversation(id: "a2a:agent-0:agent-3", sessionKey: a2a_03, sessionKeys: [a2a_03], agentId: "agent-3",
                             displayName: "小南", avatar: "star.fill", color: colors[0], kind: .a2a,
                             lastMessageText: "集成测试已全部通过。",
                             lastTimestamp: now.addingTimeInterval(-500), historyLoaded: true, fullyLoaded: true)
                c.secondaryName = "探针"; c.secondaryAvatar = "magnifyingglass"
                return c
            }(),
            {
                var c = Conversation(id: "a2a:agent-0:agent-4", sessionKey: a2a_04, sessionKeys: [a2a_04], agentId: "agent-4",
                             displayName: "小南", avatar: "star.fill", color: colors[0], kind: .a2a,
                             lastMessageText: "相关文档和 API 参考已整理完毕。",
                             lastTimestamp: now.addingTimeInterval(-900), historyLoaded: true, fullyLoaded: true)
                c.secondaryName = "寻路"; c.secondaryAvatar = "map"
                return c
            }(),
        ]

        let userTexts = [
            "这个怎么处理？", "进展如何？", "好的", "帮我看一下", "部署了吗",
            "测试通过了吗", "有什么问题吗", "继续", "改一下这里", "收到",
            "再确认一下", "优先级调高", "文档更新了吗", "合并吧", "下一步做什么",
        ]
        let agentTexts = [
            "收到，正在处理中...",
            "已完成。共修改 3 个文件，新增 128 行代码。",
            "发现一个潜在问题：`UserService.login()` 缺少并发锁，建议加 `@MainActor`。",
            "已部署到 staging 环境，地址：`https://staging.example.com`",
            "测试通过 ✅ 58/58 用例，0 失败，覆盖率 87%。",
            "已合并到 main 分支，CI 流水线运行中。",
            "代码审查完毕，LGTM。建议补充边界条件的单测。",
            "数据库迁移脚本已生成：`migrations/20260328_add_kanban.sql`",
            "性能测试结果：P99 延迟从 320ms 降到 85ms，提升 73%。",
            "依赖更新：升级 `swift-nio` 到 2.65.0，修复内存泄漏。",
            "文档已同步到 Notion，看板需求页面已更新。",
            "发现 iOS 端 WebSocket 重连逻辑有 bug，已修复并提 PR。",
            "缓存命中率从 62% 提升到 91%，减少 DB 查询 3200 次/分钟。",
            "安全扫描完成，未发现高危漏洞。2 个中危已修复。",
            "API 限流策略已上线：每用户 100 req/min，超限返回 429。",
        ]

        var allMessages: [ChatMessage] = []
        for i in 0..<1000 {
            let isUser = i % 3 == 0
            let t = now.addingTimeInterval(Double(-100000 + i * 100))
            allMessages.append(ChatMessage(
                id: "bulk-\(i)", sessionKey: sk0, agentId: "agent-0",
                role: isUser ? .user : .agent,
                text: isUser ? userTexts[i % userTexts.count] : agentTexts[i % agentTexts.count],
                timestamp: t, runId: nil
            ))
        }

        // Image messages
        var imgMsg1 = ChatMessage(id: "img-1", sessionKey: sk0, agentId: "agent-0", role: .user,
                    text: "看看这个设计稿", timestamp: now.addingTimeInterval(-500), runId: nil)
        imgMsg1.localImageData = mockImage(color: .systemBlue, size: CGSize(width: 400, height: 300), text: "设计稿 v2")
        allMessages.append(imgMsg1)

        allMessages.append(ChatMessage(id: "img-1-reply", sessionKey: sk0, agentId: "agent-0", role: .agent,
                    text: "收到设计稿。整体布局很清晰，配色方案不错。建议导航栏高度从 64pt 调整到 44pt，更符合 iOS 规范。",
                    timestamp: now.addingTimeInterval(-480), runId: nil))

        var imgMsg2 = ChatMessage(id: "img-2", sessionKey: sk0, agentId: "agent-0", role: .user,
                    text: "", timestamp: now.addingTimeInterval(-300), runId: nil)
        imgMsg2.localImageData = mockImage(color: .systemGreen, size: CGSize(width: 300, height: 400), text: "截图")
        allMessages.append(imgMsg2)

        allMessages.append(ChatMessage(id: "img-2-reply", sessionKey: sk0, agentId: "agent-0", role: .agent,
                    text: "这是测试环境的截图吧？看起来 UI 渲染正常，数据也加载出来了。",
                    timestamp: now.addingTimeInterval(-280), runId: nil))

        var imgMsg3 = ChatMessage(id: "img-3", sessionKey: sk0, agentId: "agent-0", role: .agent,
                    text: "这是修改后的效果", timestamp: now.addingTimeInterval(-200), runId: nil)
        imgMsg3.localImageData = mockImage(color: .systemOrange, size: CGSize(width: 350, height: 250), text: "After")
        allMessages.append(imgMsg3)

        var imgMsg4 = ChatMessage(id: "img-4", sessionKey: sk2, agentId: "agent-2", role: .agent,
                    text: "看板页面完成了", timestamp: now.addingTimeInterval(-250), runId: nil)
        imgMsg4.localImageData = mockImage(color: .systemPurple, size: CGSize(width: 400, height: 500), text: "Kanban Board")
        allMessages.append(imgMsg4)

        allMessages += [
            ChatMessage(id: "m11", sessionKey: sk2, agentId: "agent-2", role: .user,
                        text: "看板功能的需求文档在 shared/design-kanban.md", timestamp: now.addingTimeInterval(-2000), runId: nil),
            ChatMessage(id: "m12", sessionKey: sk2, agentId: "agent-2", role: .agent,
                        text: "收到，已阅读需求文档。计划分三步实现：\n1. 后端 API（GET/PATCH）\n2. 前端三列看板 + 拖拽\n3. 实时轮询同步\n\n预计 30 分钟完成。",
                        timestamp: now.addingTimeInterval(-1900), runId: nil),
            ChatMessage(id: "m13", sessionKey: sk2, agentId: "agent-2", role: .user,
                        text: "走 feat/kanban 分支", timestamp: now.addingTimeInterval(-1800), runId: nil),
            ChatMessage(id: "m14", sessionKey: sk2, agentId: "agent-2", role: .agent,
                        text: "看板功能的前端已完成，等待 QA 验收。\n\n提交了 12 个文件，修改 3 个，共 1229 行代码。",
                        timestamp: now.addingTimeInterval(-300), runId: nil),
            ChatMessage(id: "m15", sessionKey: sk3, agentId: "agent-3", role: .user,
                        text: "跑一下看板功能的集成测试", timestamp: now.addingTimeInterval(-1200), runId: nil),
            ChatMessage(id: "m16", sessionKey: sk3, agentId: "agent-3", role: .agent,
                        text: "58/58 用例全部通过，无回归问题。", timestamp: now.addingTimeInterval(-600), runId: nil),
            ChatMessage(id: "a01", sessionKey: a2a_02, agentId: "agent-2", role: .user,
                        text: "请按照 shared/design-kanban.md 实现看板功能", timestamp: now.addingTimeInterval(-2000), runId: nil),
            ChatMessage(id: "a02", sessionKey: a2a_02, agentId: "agent-2", role: .agent,
                        text: "feat/kanban 分支代码已提交。新增 12 个文件，共 1229 行代码。",
                        timestamp: now.addingTimeInterval(-200), runId: nil),
            ChatMessage(id: "a03", sessionKey: a2a_03, agentId: "agent-3", role: .user,
                        text: "对 feat/kanban 分支执行集成测试", timestamp: now.addingTimeInterval(-1000), runId: nil),
            ChatMessage(id: "a04", sessionKey: a2a_03, agentId: "agent-3", role: .agent,
                        text: "集成测试已全部通过。58/58 用例，0 失败。", timestamp: now.addingTimeInterval(-500), runId: nil),
            ChatMessage(id: "a05", sessionKey: a2a_04, agentId: "agent-4", role: .user,
                        text: "调研主流看板系统的 API 设计", timestamp: now.addingTimeInterval(-3000), runId: nil),
            ChatMessage(id: "a06", sessionKey: a2a_04, agentId: "agent-4", role: .agent,
                        text: "相关文档和 API 参考已整理完毕，输出到 shared/research-kanban-api.md。",
                        timestamp: now.addingTimeInterval(-900), runId: nil),
        ]

        store.messages = allMessages
        store.updateConversationPreviews()

        if store.gateways.isEmpty {
            store.gateways = [GatewayConfig(id: "mock", name: "Demo Gateway", url: "ws://localhost:8080", token: "")]
        }
    }

    static func mockImage(color: UIColor, size: CGSize = CGSize(width: 300, height: 200), text: String = "") -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.8) { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            if !text.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 24),
                    .foregroundColor: UIColor.white
                ]
                let str = text as NSString
                let textSize = str.size(withAttributes: attrs)
                str.draw(at: CGPoint(x: (size.width - textSize.width) / 2,
                                     y: (size.height - textSize.height) / 2), withAttributes: attrs)
            }
        }
    }
}
