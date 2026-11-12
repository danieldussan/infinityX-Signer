import Foundation

public enum BatchError: Error, Equatable {
    case invalidNumber(String)
    case empty
    case negative
    case bothRangeAndCount
    case countTooSmall
}

/// "21,22,25-27" -> [21, 22, 25, 26, 27] (no duplicates, in order).
public func parseNumbers(_ text: String) throws -> [Int] {
    var result: [Int] = []
    let cleaned = text.filter { !$0.isWhitespace }
    for part in cleaned.split(separator: ",", omittingEmptySubsequences: true) {
        let numbers: [Int]
        if part.contains("-") {
            let pieces = part.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2,
                  let a = Int(pieces[0]), let b = Int(pieces[1]), a <= b
            else { throw BatchError.invalidNumber(String(part)) }
            numbers = Array(a...b)
        } else {
            guard let n = Int(part) else { throw BatchError.invalidNumber(String(part)) }
            numbers = [n]
        }
        for n in numbers {
            if n < 0 { throw BatchError.negative }
            if !result.contains(n) { result.append(n) }
        }
    }
    if result.isEmpty { throw BatchError.empty }
    return result
}

/// Two digits minimum: 4 -> "04", 12 -> "12", 105 -> "105".
public func formatNumber(_ n: Int) -> String {
    n < 10 ? "0\(n)" : "\(n)"
}
