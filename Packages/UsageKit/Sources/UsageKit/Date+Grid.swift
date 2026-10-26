import Foundation

extension Date {
    public func floored(toEvery seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / seconds).rounded(.down) * seconds)
    }
}
