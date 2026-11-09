import DiskArbitration
import Foundation

/// Calls back when disks come and go. Device changes arrive in bursts, so calls are coalesced.
final class DriveMonitor {
    private let session: DASession
    private let onChange: @MainActor () -> Void
    private var pending: DispatchWorkItem?

    init?(onChange: @escaping @MainActor () -> Void) {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        self.session = session
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, { _, context in
            Unmanaged<DriveMonitor>.fromOpaque(context!).takeUnretainedValue().changed()
        }, context)
        DARegisterDiskDisappearedCallback(session, nil, { _, context in
            Unmanaged<DriveMonitor>.fromOpaque(context!).takeUnretainedValue().changed()
        }, context)
        DARegisterDiskDescriptionChangedCallback(session, nil, nil, { _, _, context in
            Unmanaged<DriveMonitor>.fromOpaque(context!).takeUnretainedValue().changed()
        }, context)
        DASessionSetDispatchQueue(session, .main)
    }

    private func changed() {
        pending?.cancel()
        let handler = onChange
        let work = DispatchWorkItem { MainActor.assumeIsolated { handler() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
