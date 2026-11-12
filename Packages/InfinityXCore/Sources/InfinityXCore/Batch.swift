import Foundation

public struct BatchInput {
    public var namePrefix: String
    public var bundlePrefix: String
    public var numbersText: String?
    public var count: Int?
    public var stripPlugins: Bool

    public init(namePrefix: String = "WAB", bundlePrefix: String = "chip",
                numbersText: String? = nil, count: Int? = nil, stripPlugins: Bool = false) {
        self.namePrefix = namePrefix
        self.bundlePrefix = bundlePrefix
        self.numbersText = numbersText
        self.count = count
        self.stripPlugins = stripPlugins
    }
}

public struct SigningJob: Equatable {
    public let number: Int
    public var displayName: String
    public var bundleID: String
    public var outputFileName: String

    public init(number: Int, displayName: String, bundleID: String, outputFileName: String) {
        self.number = number
        self.displayName = displayName
        self.bundleID = bundleID
        self.outputFileName = outputFileName
    }
}

/// `numbersText` and `count` are exclusive. With neither: next 1 after `lastUsed`.
public func makeJobs(_ input: BatchInput, lastUsed: Int, filePrefix: String = "WA") throws -> [SigningJob] {
    let hasText = !(input.numbersText?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    if hasText && input.count != nil { throw BatchError.bothRangeAndCount }
    let numbers: [Int]
    if hasText {
        numbers = try parseNumbers(input.numbersText!)
    } else {
        let k = input.count ?? 1
        if k < 1 { throw BatchError.countTooSmall }
        numbers = Array((lastUsed + 1)...(lastUsed + k))
    }
    return numbers.map { n in
        let f = formatNumber(n)
        return SigningJob(number: n,
                          displayName: "\(input.namePrefix) \(f)",
                          bundleID: "\(input.bundlePrefix).\(f)",
                          outputFileName: "\(filePrefix)\(f)-signed.ipa")
    }
}
