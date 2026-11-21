import Foundation

/// Which certificate/profile an app was signed with, kept in the library so expiry can be tracked per app.
public struct CertSnapshot: Codable, Equatable {
    public var certificateFile: String
    public var profileName: String
    public var profileUUID: String
    public var teamName: String
    public var teamID: String
    public var expiresAt: Date?

    public init(certificateFile: String, profile: ProvisioningProfile) {
        self.certificateFile = certificateFile
        self.profileName = profile.name
        self.profileUUID = profile.uuid
        self.teamName = profile.teamName
        self.teamID = profile.teamID
        self.expiresAt = profile.expirationDate
    }

    public func daysRemaining(now: Date = Date()) -> Int? {
        guard let exp = expiresAt else { return nil }
        return Int((exp.timeIntervalSince(now) / 86_400).rounded(.down))
    }

    public func status(now: Date = Date()) -> ProfileStatus {
        guard let exp = expiresAt else { return .valid }
        if exp <= now { return .expired }
        if exp.timeIntervalSince(now) < 7 * 86_400 { return .expiringSoon }
        return .valid
    }
}

/// A local notification to schedule ahead of a certificate expiring.
public struct ExpiryReminder: Equatable {
    public let fire: Date
    public let daysBefore: Int
    public let expiry: Date
}

/// Reminders `leadDays` before `expiry`, skipping the ones already in the past.
public func expiryReminders(expiry: Date, now: Date = Date(), leadDays: [Int] = [7, 1]) -> [ExpiryReminder] {
    leadDays.compactMap { d in
        let fire = expiry.addingTimeInterval(-Double(d) * 86_400)
        return fire > now ? ExpiryReminder(fire: fire, daysBefore: d, expiry: expiry) : nil
    }
    .sorted { $0.fire < $1.fire }
}
