import Foundation
import IOKit.pwr_mgt

final class PowerAssertionManager {
    enum PowerAssertionError: LocalizedError {
        case systemAssertionFailed(IOReturn)
        case displayAssertionFailed(IOReturn)

        var errorDescription: String? {
            switch self {
            case .systemAssertionFailed(let code):
                "Awayo could not keep the Mac awake. IOKit returned \(code)."
            case .displayAssertionFailed(let code):
                "Awayo could not keep the display awake. IOKit returned \(code)."
            }
        }
    }

    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0

    func start(keepDisplayAwake: Bool, reason: String) throws {
        stop()

        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &systemAssertionID
        )

        guard systemResult == kIOReturnSuccess else {
            throw PowerAssertionError.systemAssertionFailed(systemResult)
        }

        if keepDisplayAwake {
            let displayResult = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &displayAssertionID
            )

            guard displayResult == kIOReturnSuccess else {
                stop()
                throw PowerAssertionError.displayAssertionFailed(displayResult)
            }
        }
    }

    func stop() {
        release(&displayAssertionID)
        release(&systemAssertionID)
    }

    private func release(_ assertionID: inout IOPMAssertionID) {
        guard assertionID != 0 else {
            return
        }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}
