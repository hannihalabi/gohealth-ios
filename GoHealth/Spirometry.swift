import Foundation

struct SpirometrySample {
    struct Measurement: Hashable {
        let start: Date
        let end: Date
        let source: [String?]
        let device: [String?]
    }

    let id: String
    let measurement: Measurement
    let sourceName: String
    let liters: Double
}

struct SpirometryRatio {
    let id: String
    let date: Date
    let sourceName: String
    let percent: Double

    static func history(fev1: [SpirometrySample], fvc: [SpirometrySample]) -> [Self] {
        let expiratoryVolumes = Dictionary(grouping: fev1, by: \.measurement)
        let vitalCapacities = Dictionary(grouping: fvc, by: \.measurement)

        // Never combine independent latest values or guess between repeated maneuvers.
        return expiratoryVolumes.compactMap { measurement, volumes in
            guard volumes.count == 1,
                  let volume = volumes.first,
                  let capacities = vitalCapacities[measurement], capacities.count == 1,
                  let capacity = capacities.first,
                  volume.liters.isFinite, capacity.liters.isFinite,
                  volume.liters > 0, capacity.liters > 0,
                  volume.liters <= capacity.liters else { return nil }
            return Self(id: "\(volume.id)/\(capacity.id)", date: measurement.end,
                        sourceName: volume.sourceName, percent: volume.liters / capacity.liters * 100)
        }
        .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
