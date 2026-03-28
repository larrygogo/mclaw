import Foundation

/// Format message timestamp for display in conversation rows
func formatRowTime(_ date: Date) -> String {
    let f = DateFormatter()
    let cal = Calendar.current
    if cal.isDateInToday(date) {
        f.dateFormat = "HH:mm"
    } else if cal.isDateInYesterday(date) {
        f.dateFormat = "昨天"
    } else {
        f.dateFormat = "M/d"
    }
    return f.string(from: date)
}

/// Format message timestamp for display in message bubbles
func formatBubbleTime(_ date: Date) -> String {
    let f = DateFormatter()
    let cal = Calendar.current
    if cal.isDateInToday(date) {
        f.dateFormat = "HH:mm"
    } else if cal.isDateInYesterday(date) {
        f.dateFormat = "昨天 HH:mm"
    } else {
        f.dateFormat = "M/d HH:mm"
    }
    return f.string(from: date)
}

/// Format message timestamp for A2A bubbles (no "昨天" variant)
func formatA2ABubbleTime(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
    return f.string(from: date)
}

/// Format date for section headers between message groups
func formatDateSectionLabel(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "今天" }
    if cal.isDateInYesterday(date) { return "昨天" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh-Hans")
    f.dateFormat = cal.component(.year, from: date) == cal.component(.year, from: Date())
        ? "M月d日 EEEE" : "yyyy年M月d日 EEEE"
    return f.string(from: date)
}
