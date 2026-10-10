import Foundation

public extension Date {
    func timeOfDay(in timeZoneIdentifier: String) -> String {
        formatted(Date.FormatStyle(timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current).hour().minute())
    }
}
