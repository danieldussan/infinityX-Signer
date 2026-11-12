import Foundation
import InfinityXCore

/// Persists the "last used number" across launches.
struct UserDefaultsCounterStore: CounterStore {
    private static let key = "counter.last"

    init() {}

    var last: Int {
        get { UserDefaults.standard.integer(forKey: UserDefaultsCounterStore.key) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsCounterStore.key) }
    }
}
