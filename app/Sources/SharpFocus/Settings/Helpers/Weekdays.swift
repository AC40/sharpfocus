import Foundation

enum Weekdays {
    static var order: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    static func shortName(_ day: Int) -> String {
        Calendar.current.veryShortWeekdaySymbols[day - 1]
    }

    static func summary(_ days: Set<Int>) -> String {
        if days.isEmpty || days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        return order.filter(days.contains).map { Calendar.current.shortWeekdaySymbols[$0 - 1] }
            .joined(separator: " ")
    }
}
