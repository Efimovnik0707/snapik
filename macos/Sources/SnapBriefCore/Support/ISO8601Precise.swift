import Foundation

/// Port of System.Text.Json's default `DateTimeOffset` representation, which for values created
/// via `DateTimeOffset.UtcNow` / `TimeSpan.Zero` offsets (the only construction pattern used by
/// this app) renders as the round-trip ("O") format with an explicit `+00:00` offset, e.g.
/// `"2026-09-08T20:00:01.0000000+00:00"` (7 fractional digits = 100ns ticks).
///
/// Calendar math is implemented from scratch (Howard Hinnant's `civil_from_days` /
/// `days_from_civil` algorithms) instead of `Calendar`/`TimeZone`, so encoding/decoding does not
/// depend on ICU/timezone-database support, which is not guaranteed on Windows Swift Foundation.
enum ISO8601Precise {
    /// Days since 1970-01-01 -> (year, month, day), proleptic Gregorian calendar.
    private static func civilFromDays(_ z0: Int) -> (year: Int, month: Int, day: Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp + (mp < 10 ? 3 : -9)
        return (y + (m <= 2 ? 1 : 0), m, d)
    }

    /// (year, month, day) -> days since 1970-01-01, proleptic Gregorian calendar.
    private static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    private struct Components {
        var year: Int
        var month: Int
        var day: Int
        var hour: Int
        var minute: Int
        var second: Int
        /// 100ns ticks within the second (0...9_999_999), mirroring .NET's fractional precision.
        var ticks: Int
    }

    private static func components(of date: Date) -> Components {
        let totalSeconds = date.timeIntervalSince1970
        let days = Int(floor(totalSeconds / 86400.0))
        var secondsInDay = totalSeconds - Double(days) * 86400.0
        if secondsInDay < 0 { secondsInDay += 86400.0 }
        let (y, m, d) = civilFromDays(days)
        let hour = Int(secondsInDay / 3600.0)
        let minute = Int((secondsInDay.truncatingRemainder(dividingBy: 3600.0)) / 60.0)
        let secondValue = secondsInDay.truncatingRemainder(dividingBy: 60.0)
        let second = Int(secondValue)
        let fractional = secondValue - Double(second)
        let ticks = min(9_999_999, max(0, Int((fractional * 10_000_000.0).rounded(.towardZero))))
        return Components(year: y, month: m, day: d, hour: hour, minute: minute, second: second, ticks: ticks)
    }

    private static func date(from c: Components) -> Date {
        let days = daysFromCivil(c.year, c.month, c.day)
        let seconds = Double(days) * 86400.0 + Double(c.hour) * 3600.0 + Double(c.minute) * 60.0
            + Double(c.second) + Double(c.ticks) / 10_000_000.0
        return Date(timeIntervalSince1970: seconds)
    }

    /// Builds a UTC `Date` from calendar components. Exposed publicly (as `SnapBriefDate.utc`) so
    /// callers/tests can construct precise instants (mirroring `new DateTimeOffset(y, m, d, h, mi,
    /// s, TimeSpan.Zero)`) without depending on `Calendar`/`TimeZone`.
    static func makeUTC(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, nanosecond: Int = 0) -> Date {
        date(from: Components(year: year, month: month, day: day, hour: hour, minute: minute, second: second, ticks: nanosecond / 100))
    }

    /// Formats `date` as `"yyyy-MM-ddTHH:mm:ss.fffffff+00:00"`. Values are always treated as UTC,
    /// matching the app's exclusive use of `DateTimeOffset.UtcNow`/zero-offset instants.
    static func format(_ date: Date) -> String {
        let c = components(of: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%07d+00:00",
            c.year, c.month, c.day, c.hour, c.minute, c.second, c.ticks)
    }

    /// Parses `"yyyy-MM-ddTHH:mm:ss[.fffffff](Z|+HH:mm|-HH:mm)"`. Any explicit offset is applied
    /// (converted into the resulting instant); a missing offset is treated as UTC.
    static func parse(_ string: String) -> Date? {
        var body = string
        var offsetSeconds = 0

        if body.hasSuffix("Z") {
            body.removeLast()
        } else if let signIndex = body.lastIndex(where: { $0 == "+" || $0 == "-" }), signIndex > body.startIndex,
            body.distance(from: body.startIndex, to: signIndex) >= 10
        {
            let offsetPart = String(body[signIndex...])
            body = String(body[body.startIndex..<signIndex])
            let sign: Int = offsetPart.hasPrefix("-") ? -1 : 1
            let digits = offsetPart.dropFirst()
            let parts = digits.split(separator: ":")
            guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
            offsetSeconds = sign * (hours * 3600 + minutes * 60)
        }

        let dateAndTime = body.split(separator: "T", maxSplits: 1)
        guard dateAndTime.count == 2 else { return nil }
        let dateParts = dateAndTime[0].split(separator: "-")
        guard dateParts.count == 3, let year = Int(dateParts[0]), let month = Int(dateParts[1]),
            let day = Int(dateParts[2])
        else { return nil }

        let timeAndFraction = dateAndTime[1].split(separator: ".", maxSplits: 1)
        let timeParts = timeAndFraction[0].split(separator: ":")
        guard timeParts.count == 3, let hour = Int(timeParts[0]), let minute = Int(timeParts[1]),
            let second = Int(timeParts[2])
        else { return nil }

        var ticks = 0
        if timeAndFraction.count == 2 {
            var fractionDigits = String(timeAndFraction[1])
            if fractionDigits.count > 7 {
                fractionDigits = String(fractionDigits.prefix(7))
            } else {
                fractionDigits.append(String(repeating: "0", count: 7 - fractionDigits.count))
            }
            ticks = Int(fractionDigits) ?? 0
        }

        let components = Components(year: year, month: month, day: day, hour: hour, minute: minute, second: second, ticks: ticks)
        let localInstant = date(from: components)
        return localInstant.addingTimeInterval(-Double(offsetSeconds))
    }
}
