import SwiftUI

enum Clock {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func string(_ minutes: Int) -> String {
        formatter.string(from: date(minutes: minutes))
    }

    static func binding(_ minutes: Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: { date(minutes: minutes) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((c.hour ?? 0) * 60 + (c.minute ?? 0))
            })
    }
}
