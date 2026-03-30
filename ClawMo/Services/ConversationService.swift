import Foundation

final class ConversationService {

    // MARK: - Build conversations from sessions

    static func buildConversations(from sessions: [[String: Any]], agents: [AgentInfo]) -> [Conversation] {
        struct GroupInfo {
            let agent: AgentInfo
            var keys: [String]
            var latestUpdatedAt: Date
        }
        struct A2AGroupInfo {
            let parentAgent: AgentInfo
            let childAgent: AgentInfo
            var keys: [String]
            var latestUpdatedAt: Date
        }

        var userGroups: [String: GroupInfo] = [:]
        var a2aGroups: [String: A2AGroupInfo] = [:]

        for session in sessions {
            guard let key = session["key"] as? String else { continue }

            // Heartbeat filter
            let displayName = session["displayName"] as? String ?? ""
            let lastTo = session["lastTo"] as? String ?? ""
            let deliveryTo = (session["deliveryContext"] as? [String: Any])?["to"] as? String ?? ""
            let originProvider = (session["origin"] as? [String: Any])?["provider"] as? String ?? ""
            if displayName == "heartbeat" || lastTo == "heartbeat"
                || deliveryTo == "heartbeat" || originProvider == "heartbeat" { continue }

            guard let agentId = MessageService.agentIdFromSessionKey(key),
                  let agentInfo = agents.first(where: { $0.id == agentId }) else { continue }

            let updatedAt = (session["updatedAt"] as? Double)
                .map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
            let isA2A = key.contains(":subagent:")

            if isA2A {
                let parentKey = session["spawnedBy"] as? String ?? session["parentSessionKey"] as? String ?? ""
                let parentAgentId = MessageService.agentIdFromSessionKey(parentKey) ?? "main"
                let parentAgent = agents.first(where: { $0.id == parentAgentId }) ?? agentInfo
                let pairKey = [parentAgentId, agentId].sorted().joined(separator: ":")
                if var existing = a2aGroups[pairKey] {
                    existing.keys.append(key)
                    if updatedAt > existing.latestUpdatedAt {
                        existing.latestUpdatedAt = updatedAt
                    }
                    a2aGroups[pairKey] = existing
                } else {
                    a2aGroups[pairKey] = A2AGroupInfo(parentAgent: parentAgent, childAgent: agentInfo,
                                                      keys: [key], latestUpdatedAt: updatedAt)
                }
            } else {
                if var existing = userGroups[agentId] {
                    existing.keys.append(key)
                    if updatedAt > existing.latestUpdatedAt {
                        existing.latestUpdatedAt = updatedAt
                    }
                    userGroups[agentId] = existing
                } else {
                    userGroups[agentId] = GroupInfo(agent: agentInfo, keys: [key], latestUpdatedAt: updatedAt)
                }
            }
        }

        var result: [Conversation] = []

        for (agentId, group) in userGroups {
            var conv = Conversation(
                id: "user:\(agentId)", sessionKey: group.keys.first ?? "",
                sessionKeys: group.keys, agentId: agentId,
                displayName: group.agent.name, avatar: group.agent.avatar,
                color: group.agent.color, kind: .user
            )
            conv.lastTimestamp = group.latestUpdatedAt
            result.append(conv)
        }

        for (pairKey, group) in a2aGroups {
            var conv = Conversation(
                id: "a2a:\(pairKey)", sessionKey: group.keys.first ?? "",
                sessionKeys: group.keys, agentId: group.childAgent.id,
                displayName: group.parentAgent.name, avatar: group.parentAgent.avatar,
                color: group.parentAgent.color, kind: .a2a
            )
            conv.secondaryAgentId = group.childAgent.id
            conv.secondaryName = group.childAgent.name
            conv.secondaryAvatar = group.childAgent.avatar
            conv.lastTimestamp = group.latestUpdatedAt
            result.append(conv)
        }

        return result
    }

    // MARK: - Build agent list

    static func buildAgentList(_ raw: [[String: Any]]) -> [AgentInfo] {
        let avatars = MockDataProvider.avatars
        return raw.enumerated().map { i, a in
            let id = a["agentId"] as? String ?? a["id"] as? String ?? UUID().uuidString
            let serverAvatar = a["avatar"] as? String ?? a["emoji"] as? String ?? a["icon"] as? String ?? ""
            let avatar = serverAvatar.isEmpty ? avatars[i % avatars.count] : serverAvatar
            let serverColor = a["color"] as? String ?? ""
            let color = serverColor.isEmpty ? "#94a3b8" : serverColor
            return AgentInfo(id: id, name: a["name"] as? String ?? "Agent", avatar: avatar, color: color)
        }
    }
}
