import XCTest

@testable import WiiKit

final class SectionTests: XCTestCase {
    func testParsesValuesContainingEquals() {
        let sections = parseSections("[disc-0]\nid=TSTE99\nname=A = B\nregion=USA \n\n[disc-1]\nid=X\n")
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].values["name"], "A = B")
        XCTAssertEqual(sections[0].values["region"], "USA")
    }

    func testPartitionParsing() {
        let output = """
            [wbfs-0]
            file=/dev/rdisk9
            used_discs=2
            total_discs=215
            used_mib=78
            free_mib=7550
            total_mib=7628

            [disc-0]
            id=TSTE99
            name=One
            region=USA
            size=48234496
            filetype=WBFS/WII
            wbfs_slot=0
            source=/dev/rdisk9/#0
            """
        let contents = Engine.parsePartition(output, device: "/dev/rdisk9")
        XCTAssertEqual(contents.space?.freeMiB, 7550)
        XCTAssertEqual(contents.space?.totalDiscs, 215)
        XCTAssertEqual(contents.games.first?.id, "/dev/rdisk9/#0")
        XCTAssertEqual(contents.games.first?.location, .partition(device: "/dev/rdisk9", slot: 0))
    }
}

final class ProgressTests: XCTestCase {
    func testRealProgressLine() {
        XCTAssertEqual(ToolOutput.progressFraction(in: "      53% copied in 0:01 (1315.1 MiB/sec) -> ETA 0:00   "), 0.53)
    }

    func testIgnoresOtherOutput() {
        XCTAssertNil(ToolOutput.progressFraction(in: "     2478 MiB copied in 0:01, 1328.0 MiB/sec"))
        XCTAssertNil(ToolOutput.progressFraction(in: "1 object scanned"))
        XCTAssertNil(ToolOutput.progressFraction(in: "999% copied"))
    }

    func testFailureDetailPrefersMessageLine() {
        let stderr = "!! wit: ERROR #64 [FILE ALREADY EXISTS] in CopyImage() @ src/lib-sf.c#3278\n!!      File already exists: out/one.wbfs\n"
        XCTAssertEqual(
            ToolOutput.failureDetail(stdout: "", stderr: stderr, exitCode: 64), "File already exists: out/one.wbfs")
    }

    func testFailureDetailFromSectionOutput() {
        let stdout = "[error]\ncode=48\nname=NO WBFS FOUND\ntext=No WBFS found\n"
        XCTAssertEqual(ToolOutput.failureDetail(stdout: stdout, stderr: "", exitCode: 48), "No WBFS found")
    }
}

final class NamingTests: XCTestCase {
    func testStripsFATIllegalCharacters() {
        XCTAssertEqual(Naming.safeComponent("Mario: Part*2 / <Deluxe>?"), "Mario Part2 Deluxe")
    }

    func testPathTraversalIsNeutralised() {
        XCTAssertEqual(Naming.safeComponent(".."), "Untitled")
        XCTAssertEqual(Naming.safeComponent("../../etc/passwd"), "etcpasswd")
    }

    func testTrailingDotsRemoved() {
        XCTAssertEqual(Naming.safeComponent("Wii Sports..."), "Wii Sports")
    }

    func testLoaderLayout() {
        let url = Naming.outputURL(
            base: URL(fileURLWithPath: "/V/wbfs"), gameID: "RSPE01", title: "Wii Sports",
            format: .wbfs, naming: .gameID, subdirectories: true)
        XCTAssertEqual(url.path, "/V/wbfs/Wii Sports [RSPE01]/RSPE01.wbfs")
    }

    func testFlatIDTitleName() {
        let url = Naming.outputURL(
            base: URL(fileURLWithPath: "/V"), gameID: "RSPE01", title: "Wii Sports",
            format: .iso, naming: .gameIDTitle, subdirectories: false)
        XCTAssertEqual(url.path, "/V/RSPE01_Wii Sports.iso")
    }

    func testPercentIsEscapedForWit() {
        XCTAssertEqual(Naming.escapedDestination("/V/100% Game.wbfs"), "/V/100%% Game.wbfs")
    }

    func testCSVQuoting() {
        XCTAssertEqual(CSV.encode([["a,b", "c\"d", "e"]]), "\"a,b\",\"c\"\"d\",e\r\n")
    }
}

final class CoverTests: XCTestCase {
    func testRegionFromGameID() {
        XCTAssertEqual(GameTDB.artRegions(gameID: "RMCE01", language: "EN"), ["US", "EN", "JA"])
        XCTAssertEqual(GameTDB.artRegions(gameID: "RMCJ01", language: "EN"), ["JA", "EN", "US"])
        XCTAssertEqual(GameTDB.artRegions(gameID: "RMCP01", language: "FR"), ["FR", "EN", "US", "JA"])
    }

    /// The ID comes straight from the disc, so a malformed image must not crash or escape the URL path.
    func testMalformedGameIDsAreEncoded() throws {
        let urls = GameTDB.coverCandidates(kind: .flat, gameID: "AB C/../1", language: "EN")
        let url = try XCTUnwrap(urls.first)
        XCTAssertTrue(url.absoluteString.hasSuffix("AB%20C%2F..%2F1.png"), url.absoluteString)
    }

    func testEveryCoverKindProducesURLs() {
        for kind in CoverKind.allCases {
            XCTAssertFalse(GameTDB.coverCandidates(kind: kind, gameID: "RMCE01", language: "EN").isEmpty, kind.rawValue)
        }
    }

    func testDiscPreferenceOrder() {
        let custom = GameTDB.coverCandidates(kind: .disc, gameID: "RMCE01", language: "EN", preferCustomDisc: true)
        XCTAssertTrue(custom[0].path.contains("/disccustom/"))
        let normal = GameTDB.coverCandidates(kind: .disc, gameID: "RMCE01", language: "EN")
        XCTAssertTrue(normal[0].path.contains("/disc/"))
    }

    func testTitleDatabaseSkipsHeaderAndFallsBackToID4() {
        let db = TitleDatabase(text: "TITLES = https://www.gametdb.com (type: Wii)\nRMCE = Mario Kart\nRMCE01 = Mario Kart Wii\n")
        XCTAssertEqual(db.title(for: "RMCE01"), "Mario Kart Wii")
        XCTAssertEqual(db.title(for: "RMCE99"), "Mario Kart")
        XCTAssertNil(db.title(for: "TITLES"))
    }

    func testGameInfoReadsControlsRatingAndOnlinePlay() throws {
        let xml = """
            <datafile><game name="x"><id>RMCE01</id><region>NTSC-U</region><languages>EN,FR</languages>
            <rating type="ESRB" value="E"><descriptor>comic mischief</descriptor></rating>
            <wi-fi players="12"><feature>online</feature></wi-fi>
            <input players="4"><control type="wheel" required="false"/><control type="wiimote" required="true"/></input>
            </game><game name="y"><id>RSPE01</id><wi-fi players="0"/><input players="1"/></game></datafile>
            """
        let parsed = GameInfoParser.parse(data: Data(xml.utf8), language: "EN")
        let info = try XCTUnwrap(parsed["RMCE01"])
        XCTAssertEqual(info.controls, ["Wii Remote", "Wii Wheel"], "Required controllers come first")
        XCTAssertEqual(info.rating, "ESRB E")
        XCTAssertEqual(info.onlinePlayers, "12")
        XCTAssertEqual(info.region, "NTSC-U")
        XCTAssertEqual(info.languages, "EN,FR")
        XCTAssertEqual(parsed["RSPE01"]?.onlinePlayers, "", "Zero online players means no online play")
        XCTAssertEqual(parsed["RSPE01"]?.controls, [], "Controls must not leak between games")
    }

    func testGameInfoPrefersRequestedLanguage() {
        let xml = """
            <datafile><game name="x"><id>RMCE01</id>
            <locale lang="EN"><title>English</title><synopsis>Eng syn</synopsis></locale>
            <locale lang="FR"><title>French</title><synopsis></synopsis></locale>
            <developer>Dev</developer><date year="2008" month="4" day="27"/><genre>racing</genre>
            <input players="4"></input></game></datafile>
            """
        let info = GameInfoParser.parse(data: Data(xml.utf8), language: "FR")["RMCE01"]
        XCTAssertEqual(info?.title, "French")
        XCTAssertEqual(info?.synopsis, "Eng syn", "An empty translation must fall back to English")
        XCTAssertEqual(info?.year, "2008")
        XCTAssertEqual(info?.players, "4")
    }
}

/// The guard is the only thing between a mistaken click and an erased drive.
final class DiskGuardTests: XCTestCase {
    private let boot: Set<String> = ["disk0", "disk3"]
    private let external: Set<String> = ["disk6"]

    private func usbDrive(_ change: (inout DiskFacts) -> Void = { _ in }) -> DiskFacts {
        var facts = DiskFacts(
            identifier: "disk6", parentWholeDisk: "disk6", mediaName: "SanDisk", sizeBytes: 64_000_000_000,
            isWholeDisk: true, isInternal: false, removableOrExternal: true, osInternal: false,
            virtualOrPhysical: "Physical", busProtocol: "USB")
        change(&facts)
        return facts
    }

    private func refusal(_ facts: DiskFacts, external: Set<String>? = nil, boot: Set<String>? = nil) -> String? {
        DiskGuard.refusal(
            for: facts, policy: .externalPhysicalOnly,
            externalPhysical: external ?? self.external, bootDisks: boot ?? self.boot)
    }

    func testAcceptsExternalUSB() { XCTAssertNil(refusal(usbDrive())) }

    func testRefusesInternal() { XCTAssertNotNil(refusal(usbDrive { $0.isInternal = true })) }

    func testRefusesNotReportedExternal() { XCTAssertNotNil(refusal(usbDrive { $0.removableOrExternal = false })) }

    func testRefusesOSInternal() { XCTAssertNotNil(refusal(usbDrive { $0.osInternal = true })) }

    func testRefusesVirtual() { XCTAssertNotNil(refusal(usbDrive { $0.virtualOrPhysical = "Virtual" })) }

    func testRefusesDiskImage() { XCTAssertNotNil(refusal(usbDrive { $0.busProtocol = "Disk Image" })) }

    func testRefusesExternalBootDisk() {
        XCTAssertNotNil(refusal(usbDrive(), boot: ["disk6"]))
    }

    func testRefusesAbsentFromExternalList() {
        XCTAssertNotNil(refusal(usbDrive(), external: []))
    }

    func testFailsClosedWhenBootDiskUnknown() {
        XCTAssertNotNil(refusal(usbDrive(), boot: []))
    }

    func testRefusesRealInternalSSDShape() {
        let ssd = DiskFacts(
            identifier: "disk0", parentWholeDisk: "disk0", mediaName: "APPLE SSD", sizeBytes: 500_277_792_768,
            isWholeDisk: true, isInternal: true, removableOrExternal: false, osInternal: false,
            virtualOrPhysical: "Unknown", busProtocol: "Apple Fabric")
        XCTAssertNotNil(refusal(ssd))
    }

    func testIncompletePlistReadsAsUnsafe() {
        let facts = DiskFacts(plist: ["DeviceIdentifier": "disk6", "ParentWholeDisk": "disk6"])
        XCTAssertNotNil(facts)
        XCTAssertNotNil(refusal(facts!))
    }

    func testTestPolicyOnlyAdmitsDiskImages() {
        XCTAssertNotNil(
            DiskGuard.refusal(for: usbDrive(), policy: .testingDiskImagesOnly, externalPhysical: external, bootDisks: boot))
    }

    func testIdentifierValidationBlocksInjection() {
        XCTAssertTrue(DiskGuard.isValidIdentifier("disk6s1"))
        XCTAssertFalse(DiskGuard.isValidIdentifier("disk6; rm -rf /"))
        XCTAssertFalse(DiskGuard.isValidIdentifier("rdisk6"))
        XCTAssertFalse(DiskGuard.isValidVolumeName("A B"))
        XCTAssertFalse(DiskGuard.isValidVolumeName("TOOLONGNAME12"))
    }

    func testSizeLimitsAreCheckedByFormat() {
        XCTAssertNil(DiskGuard.sizeRefusal(bytes: 2_146_435_072, format: .fat32))
        XCTAssertNil(DiskGuard.sizeRefusal(bytes: 2_146_435_072, format: .wbfs))
        XCTAssertNil(DiskGuard.sizeRefusal(bytes: 64_000_000_000, format: .fat32))
        XCTAssertNotNil(DiskGuard.sizeRefusal(bytes: 3_000_000_000_000, format: .fat32), "MBR tops out at 2 TB")
    }

    func testTypedNamesBecomeValidVolumeNames() {
        XCTAssertEqual(DiskGuard.sanitizedVolumeName("Expanded_Drive1"), "EXPANDED_DR")
        XCTAssertEqual(DiskGuard.sanitizedVolumeName("game hub!"), "GAME_HUB")
        XCTAssertTrue(DiskGuard.isValidVolumeName(DiskGuard.sanitizedVolumeName("Expanded_Drive1")))
        XCTAssertEqual(DiskGuard.sanitizedVolumeName("WII"), "WII")
    }

    func testDriveSwapIsDetected() {
        XCTAssertFalse(usbDrive().isSameDrive(as: usbDrive { $0.mediaName = "Other" }))
        XCTAssertFalse(usbDrive().isSameDrive(as: usbDrive { $0.sizeBytes = 1 }))
        XCTAssertTrue(usbDrive().isSameDrive(as: usbDrive()))
    }
}
