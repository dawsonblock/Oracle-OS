import Foundation

public protocol ObservationProvider {
    func observe() -> Observation
}
