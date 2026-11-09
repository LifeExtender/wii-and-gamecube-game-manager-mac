import XCTest

@testable import WiiKit

final class DiscInfoParsingTests: XCTestCase {
    private let wiiDump = """

        Dump of file out/one.wbfs/#0

          Real path:         /tmp/one.wbfs
          Virtual size:      118240000/hex = 4699979776 = 4482 MiB
          Scrubbed size:       2990000/hex =   43581440 =   42 MiB, 0.93%, 1330*32K
          WBFS file size:      3000000/hex =   50331648 =   48 MiB, 1.07%, 115.5%
          WBFS fragments:    1+0 = a ratio of 0.00 additional_fragments/GiB
          File & disc type:  WBFS/WII  &  Wii
          Disc & part IDs:   disc=TSTE99, ticket=TSTE, tmd=TSTE, boot=TSTE99, wbfs=TSTE99
          Disc name:         Synthetic: Disc One
          ID Region:         NTSC/USA [USA ]
          Region setting:    1 [USA] / Jap=0 USA=0 ?=0 Eur=0,0,0,0,0,0 Kor=0
          System version:    00000001-00000023 = IOS 0x23 = IOS 35
          Partitions:             3  [encrypted, fake signed]
          Directories:            4
          Files:                 14

          1 partition table with 3 partitions:

            index      type    offset ..   end off   size/hex =   size/dec =  MiB  status
            ----------------------------------------------------------------------------------------
             0     part.tab     40020 ..     40028          8 =          8         1 partition
            ----------------------------------------------------------------------------------------
             0.0   UPDATE 1     50000 ..    f50000     f00000 =   15728640 =   15  enc,faked
             0.1     DATA 0   f800000 ..  12370000    2b70000 =   45547520 =   43  enc,faked
             0.2  CHANNEL 2  13000000 ..  14000000    1000000 =   16777216 =   16  enc,faked
            ----------------------------------------------------------------------------------------
        """

    func testReadsIdentity() {
        let info = DiscInfo.parse(dump: wiiDump)
        XCTAssertEqual(info.discID, "TSTE99")
        XCTAssertEqual(info.name, "Synthetic: Disc One", "A colon in the title must survive")
        XCTAssertEqual(info.region, "NTSC/USA")
        XCTAssertEqual(info.requiredSystem, "IOS 35")
        XCTAssertEqual(info.format, "WBFS/WII")
        XCTAssertEqual(info.platform, "Wii")
    }

    func testReadsSizesFromTheDecimalField() {
        let info = DiscInfo.parse(dump: wiiDump)
        XCTAssertEqual(info.discSize, 4_699_979_776)
        XCTAssertEqual(info.usedSize, 43_581_440)
    }

    func testISODumpLabelsTheSizeDifferently() {
        let info = DiscInfo.parse(dump: "  ISO file size:     118240000/hex = 4699979776 = 4482 MiB\n")
        XCTAssertEqual(info.discSize, 4_699_979_776)
    }

    func testReadsProtectionAndCounts() {
        let info = DiscInfo.parse(dump: wiiDump)
        XCTAssertEqual(info.partitionCount, 3)
        XCTAssertEqual(info.protection, "Encrypted, fake signed")
        XCTAssertEqual(info.directories, 4)
        XCTAssertEqual(info.files, 14)
    }

    func testReadsEachPartitionAndSkipsThePartitionTable() {
        let partitions = DiscInfo.parse(dump: wiiDump).partitions
        XCTAssertEqual(partitions.map(\.label), ["Update", "Data", "Channel"])
        XCTAssertEqual(partitions.map(\.sizeBytes), [15_728_640, 45_547_520, 16_777_216])
    }

    func testMissingFieldsStayNil() {
        let info = DiscInfo.parse(dump: "Dump of something unexpected\nwith no: known labels\n")
        XCTAssertNil(info.discSize)
        XCTAssertNil(info.requiredSystem)
        XCTAssertTrue(info.partitions.isEmpty)
    }

    func testID8() {
        var info = DiscInfo()
        info.applyID8("TSTE99 01.02\n")
        XCTAssertEqual(info.discNumber, 1)
        XCTAssertEqual(info.version, 2)
    }
}

final class ProgressDetailTests: XCTestCase {
    func testReadsRateAndTimeLeft() {
        let parsed = ToolOutput.rateAndETA(in: "      53% copied in 0:01 (1315.1 MiB/sec) -> ETA 0:02   ")
        XCTAssertEqual(parsed?.rate, "1315.1 MiB/s")
        XCTAssertEqual(parsed?.eta, "0:02")
        XCTAssertNil(ToolOutput.rateAndETA(in: "     2478 MiB copied in 0:01, 1328.0 MiB/sec"))
    }

    func testScrubbedSizesKeyBothSlotAndPath() {
        let output = """

               ISO  ISO
            blocks  MiB  filename
            -------------------------------------------------------------------------------
              1330   42  /x/one.iso
              5973  187  /x/My Game (USA)/one.wbfs/#0
            -------------------------------------------------------------------------------
            Total: 7303 blocks (229 MiB) in 2 files
            """
        let sizes = Engine.parseScrubbedSizes(output)
        XCTAssertEqual(sizes["/x/one.iso"], 1330 * 32768)
        XCTAssertEqual(sizes["/x/My Game (USA)/one.wbfs"], 5973 * 32768)
        XCTAssertEqual(sizes["/x/My Game (USA)/one.wbfs/#0"], 5973 * 32768)
    }
}

final class LoaderPathTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Volumes/WII")

    func testWiiLayout() {
        XCTAssertEqual(Naming.wiiURL(root: root, gameID: "RMCE01", title: "Mario Kart Wii").path, "/Volumes/WII/wbfs/Mario Kart Wii [RMCE01]/RMCE01.wbfs")
    }

    func testGameCubeLayout() {
        XCTAssertEqual(
            Naming.gameCubeURL(root: root, gameID: "GZLE01", title: "The Legend of Zelda: The Wind Waker", discNumber: 0).path,
            "/Volumes/WII/games/The Legend of Zelda The Wind Waker [GZLE01]/game.iso")
    }

    func testSecondGameCubeDisc() {
        XCTAssertEqual(Naming.gameCubeURL(root: root, gameID: "GF7E01", title: "X", discNumber: 1).lastPathComponent, "disc2.iso")
    }
}

final class DiscFileTests: XCTestCase {
    private let listing = """

         offset     size     size
            hex      hex      dec  path + file
        --------------------------------------------
              -        - N=17
        f8004e0      a00     2560  cert.bin
              -        - N=2       files/
         1f0000+ 2800000 41943040  files/payload.bin
        29f0000+      14       20  files/readme with space.txt
              -        - N=1       files/sub/
        30000000      10       16  files/sub/deep.bin
              0       72      114  setup.bat
              -        - N=5       sys/
           2440+     420     1056  sys/apploader.img
        """

    func testKeepsOnlyTheGamesOwnFiles() {
        let paths = DiscFiles.parse(listing: listing).map(\.path)
        XCTAssertEqual(paths, ["files/payload.bin", "files/readme with space.txt", "files/sub/deep.bin", "sys/apploader.img"])
    }

    func testFolderCountIncludesNestedFolders() {
        XCTAssertEqual(DiscFiles.folderCount(DiscFiles.parse(listing: listing)), 3)
    }

    func testTreeSumsFoldersAndListsThemFirst() throws {
        let tree = DiscFiles.tree(DiscFiles.parse(listing: listing))
        XCTAssertEqual(tree.map(\.name), ["files", "sys"])
        let files = try XCTUnwrap(tree.first)
        XCTAssertEqual(files.sizeBytes, 41_943_040 + 20 + 16)
        XCTAssertEqual(files.fileCount, 3)
        XCTAssertEqual(files.children?.first?.name, "sub", "Folders sort ahead of files")
    }
}
