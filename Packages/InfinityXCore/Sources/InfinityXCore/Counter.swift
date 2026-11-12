import Foundation

public protocol CounterStore {
    var last: Int { get set }
}

/// Persists `{"last": n}` like `.wab_counter` in signer.py.
public struct JSONFileCounterStore: CounterStore {
    public let url: URL
    public init(url: URL) { self.url = url }

    public var last: Int {
        get {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let n = obj["last"] as? Int else { return 0 }
            return n
        }
        set {
            if let data = try? JSONSerialization.data(withJSONObject: ["last": newValue]) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}

/// Call only after a successful signing: last never goes down.
public func advance(_ store: inout some CounterStore, afterSuccess n: Int) {
    store.last = max(store.last, n)
}
