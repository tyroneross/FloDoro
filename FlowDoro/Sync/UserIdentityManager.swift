import Foundation
import CloudKit
import os.log

// MARK: - User Identity Manager
//
// Provides anonymous user tracking via CloudKit's userRecordID.
// No login screen, no email, no password — the user's Apple ID is the identity.
//
// CKContainer.fetchUserRecordID returns a stable, anonymous identifier
// that is the same across all devices signed into the same Apple ID.
// This is the "user tracking without auth" approach.
//
// Usage:
//   let userID = await UserIdentityManager.shared.fetchAnonymousUserID()
//   // userID is stable, unique, anonymous — same on Mac, iPhone, Watch

@MainActor
final class UserIdentityManager: ObservableObject {
    static let shared = UserIdentityManager()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.flodoro",
        category: "identity"
    )

    /// The anonymous user record ID from CloudKit, if available.
    /// Same value on every device signed into the same Apple ID.
    @Published private(set) var anonymousUserID: String?

    /// iCloud account status
    @Published private(set) var iCloudStatus: ICloudStatus = .unknown

    enum ICloudStatus: String {
        case unknown
        case available       // Signed in, everything works
        case noAccount       // Not signed into iCloud
        case restricted      // Parental controls or MDM
        case couldNotDetermine
        case temporarilyUnavailable
    }

    private let container = CKContainer.default()

    private init() {}

    // MARK: - Public API

    /// Check iCloud availability and fetch the anonymous user ID.
    /// Call this on app launch. Non-blocking — publishes results via @Published properties.
    func initialize() {
        Task {
            await checkAccountStatus()
            if iCloudStatus == .available {
                await fetchUserRecordID()
            }
        }
    }

    /// Fetch the anonymous user ID. Returns nil if iCloud is unavailable.
    func fetchAnonymousUserID() async -> String? {
        if let existing = anonymousUserID { return existing }
        await checkAccountStatus()
        guard iCloudStatus == .available else { return nil }
        return await fetchUserRecordID()
    }

    // MARK: - Private

    private func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                iCloudStatus = .available
            case .noAccount:
                iCloudStatus = .noAccount
                Self.logger.info("No iCloud account — sync disabled, local-only mode")
            case .restricted:
                iCloudStatus = .restricted
                Self.logger.info("iCloud restricted — sync disabled")
            case .couldNotDetermine:
                iCloudStatus = .couldNotDetermine
                Self.logger.warning("Could not determine iCloud status")
            case .temporarilyUnavailable:
                iCloudStatus = .temporarilyUnavailable
                Self.logger.info("iCloud temporarily unavailable")
            @unknown default:
                iCloudStatus = .couldNotDetermine
            }
        } catch {
            iCloudStatus = .couldNotDetermine
            Self.logger.error("Failed to check iCloud status: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func fetchUserRecordID() async -> String? {
        do {
            let recordID = try await container.userRecordID()
            let userID = recordID.recordName
            anonymousUserID = userID
            Self.logger.info("Anonymous user ID fetched successfully")
            return userID
        } catch {
            Self.logger.error("Failed to fetch user record ID: \(error.localizedDescription)")
            return nil
        }
    }
}
