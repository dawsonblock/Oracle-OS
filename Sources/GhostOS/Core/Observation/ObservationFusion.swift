import Foundation

public struct ObservationFusion {

    public static func fuse(
        ax: [UnifiedElement],
        cdp: [UnifiedElement],
        vision: [UnifiedElement]
    ) -> [UnifiedElement] {

        var result: [UnifiedElement] = []

        result.append(contentsOf: ax)
        result.append(contentsOf: cdp)
        result.append(contentsOf: vision)

        return result
    }
}
