public enum FailureClass: String, Codable, Sendable {

    case elementNotFound
    case elementAmbiguous
    case wrongFocus
    case actionFailed
    case navigationFailed
    case modalBlocking
    case verificationFailed
    case staleObservation
}
