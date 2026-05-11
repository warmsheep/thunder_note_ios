import Foundation

/// 消息时间分组与气泡内时间显示的统一工具。
/// 对齐 Android `MessageAdapter` 的「相邻消息时间差 > 5 分钟时显示分组」规则。
public enum MessageTimeFormatter {
    public static let groupingThreshold: TimeInterval = 5 * 60

    /// 解析后端 / pending 写入的时间字符串。优先 ISO 8601，其次 LocalDateTime（无 Z）。
    public static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = iso8601Formatter.date(from: raw) { return date }
        if let date = iso8601FractionalFormatter.date(from: raw) { return date }
        if let date = localDateTimeFormatter.date(from: raw) { return date }
        if let date = localDateTimeWithFractionFormatter.date(from: raw) { return date }
        return nil
    }

    /// 是否需要在 `current` 之前显示一个时间分组标签。
    public static func shouldShowSeparator(previous: Date?, current: Date?) -> Bool {
        guard let current else { return false }
        guard let previous else { return true }
        return current.timeIntervalSince(previous) > groupingThreshold
    }

    public static func separatorLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return "今天 " + timeOnlyFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 " + timeOnlyFormatter.string(from: date)
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return monthDayTimeFormatter.string(from: date)
        }
        return fullDateTimeFormatter.string(from: date)
    }

    public static func bubbleTimeLabel(for date: Date) -> String {
        timeOnlyFormatter.string(from: date)
    }

    // MARK: - Formatters

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let localDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static let localDateTimeWithFractionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let monthDayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    private static let fullDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()
}
