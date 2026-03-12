import Foundation

public enum PageElementIndex {
    public static func lookup(_ index: Int, in snapshot: PageSnapshot) -> PageIndexedElement? {
        snapshot.indexedElements.first(where: { $0.index == index })
    }

    public static func actionableLabels(in snapshot: PageSnapshot) -> [String] {
        snapshot.indexedElements.compactMap(\.label)
    }
}
