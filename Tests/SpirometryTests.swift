import Foundation

// Run with swiftc GoHealth/Spirometry.swift Tests/SpirometryTests.swift -o /tmp/spirometry-tests
@main
enum SpirometryTests {
    static func main() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        func sample(_ id: String, _ liters: Double, date: Date = date,
                    source: String = "spirometer", device: String = "device-1",
                    startOffset: TimeInterval = 0) -> SpirometrySample {
            .init(id: id,
                  measurement: .init(start: date.addingTimeInterval(startOffset), end: date,
                                     source: [source, "1.0"], device: [device]),
                  sourceName: source, liters: liters)
        }
        func ratios(_ fev1: [SpirometrySample], _ fvc: [SpirometrySample]) -> [SpirometryRatio] {
            SpirometryRatio.history(fev1: fev1, fvc: fvc)
        }
        let volume = sample("fev1", 3.2)
        let capacity = sample("fvc", 4)
        let valid = ratios([volume], [capacity])
        precondition(valid.count == 1 && abs(valid[0].percent - 80) < 0.0001)
        precondition(valid[0].date == date && valid[0].sourceName == "spirometer")
        precondition(ratios([], [capacity]).isEmpty)
        precondition(ratios([volume], []).isEmpty)
        precondition(ratios([volume], [sample("fvc", 4, date: date.addingTimeInterval(1))]).isEmpty)
        precondition(ratios([volume], [sample("fvc", 4, startOffset: -1)]).isEmpty)
        precondition(ratios([volume], [sample("fvc", 4, source: "other-app")]).isEmpty)
        precondition(ratios([volume], [sample("fvc", 4, device: "device-2")]).isEmpty)
        precondition(ratios([volume, sample("repeat", 3.1)], [capacity]).isEmpty)
        precondition(ratios([volume], [capacity, sample("repeat", 4.1)]).isEmpty)
        for invalid in [0.0, -1.0, Double.nan, Double.infinity] {
            precondition(ratios([sample("fev1", invalid)], [capacity]).isEmpty)
            precondition(ratios([volume], [sample("fvc", invalid)]).isEmpty)
        }
        precondition(ratios([sample("fev1", 4.1)], [capacity]).isEmpty)
        let older = date.addingTimeInterval(-86400)
        let history = ratios([sample("old-fev1", 3, date: older), volume],
                             [capacity, sample("old-fvc", 4, date: older)])
        precondition(history.map(\.percent) == [80, 75])
        let remaining = ratios([volume, sample("ambiguous", 3.1), sample("old-fev1", 3, date: older)],
                               [capacity, sample("old-fvc", 4, date: older)])
        precondition(remaining.count == 1 && remaining[0].percent == 75)
        print("Spirometry tests passed: matching, ambiguity, invalid values and history order.")
    }
}
