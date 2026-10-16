import Foundation

/// Which kind of build this is: the demo tools (sample data, Pro unlocked) are only in test builds, never in the
/// App Store version.
nonisolated enum BuildChannel {
    /// A development build, or a TestFlight one (its App Store receipt is a sandbox receipt): the jury and the
    /// team can fill the app with demo data and unlock Rebond Pro.
    static let showsDemoTools: Bool = {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()
}
