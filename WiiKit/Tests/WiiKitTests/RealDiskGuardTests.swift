import XCTest

@testable import WiiKit

/// Read-only: asks the live guard about this Mac's real disks. Nothing here writes to any device.
final class RealDiskGuardTests: XCTestCase {
    private var service: DiskService {
        DiskService(tools: Tools(directory: URL(fileURLWithPath: "/nonexistent")), policy: .externalPhysicalOnly)
    }

    func testStartupDiskIsIdentified() async throws {
        let boot = await service.bootDisks()
        XCTAssertFalse(boot.isEmpty, "The guard must be able to find the startup disk")
    }

    func testRealInternalDiskIsRefused() async throws {
        let service = service
        let boot = await service.bootDisks()
        for disk in boot {
            let facts = try await service.facts(for: disk)
            let reason = try await service.refusal(for: facts)
            XCTAssertNotNil(reason, "\(disk) must be refused")
        }
        let internalDisk = try await service.facts(for: "disk0")
        let reason = try await service.refusal(for: internalDisk)
        XCTAssertNotNil(reason, "disk0 must be refused")
    }

    func testExternalListNeverContainsTheStartupDisk() async throws {
        let service = service
        let boot = await service.bootDisks()
        let listed = try await service.listExternal().map(\.facts.parentWholeDisk)
        XCTAssertTrue(boot.isDisjoint(with: listed), "Startup disk appeared among formattable drives")
        XCTAssertFalse(listed.contains("disk0"))
    }
}
