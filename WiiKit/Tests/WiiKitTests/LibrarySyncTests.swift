import XCTest

@testable import WiiKit

final class LibrarySyncTests: XCTestCase {
    private func game(_ id: String, disc: Int = 0, type: String = "WBFS/WII", path: String? = nil) -> Game {
        let source = path ?? "/lib/\(id)-\(disc)"
        var result = Game(
            id: source, gameID: id, discName: id, region: "USA", fileType: type,
            sizeBytes: 1, bytesOnDisk: 1, location: .file(URL(fileURLWithPath: source)))
        result.discNumber = disc
        return result
    }

    func testFindsOnlyWhatTheDriveLacks() {
        let missing = LibrarySync.missing(from: [[game("AAAE01"), game("BBBE01")]], on: [game("AAAE01", path: "/drive/a")])
        XCTAssertEqual(missing.map(\.gameID), ["BBBE01"])
    }

    func testAGameInTwoLibrariesIsListedOnce() {
        let missing = LibrarySync.missing(from: [[game("AAAE01", path: "/one/a")], [game("AAAE01", path: "/two/a")]], on: [])
        XCTAssertEqual(missing.map(\.id), ["/one/a"])
    }

    func testNothingMissingWhenDriveHasEverything() {
        XCTAssertTrue(LibrarySync.missing(from: [[game("AAAE01")]], on: [game("AAAE01", path: "/drive/a")]).isEmpty)
    }

    func testEmptyLibrariesProduceNothing() {
        XCTAssertTrue(LibrarySync.missing(from: [], on: [game("AAAE01")]).isEmpty)
    }

    func testDeclinedGamesStayHiddenButNewOnesAppear() {
        let library = [[game("AAAE01"), game("CCCE01")]]
        let missing = LibrarySync.missing(from: library, on: [], excluding: [game("AAAE01").identity])
        XCTAssertEqual(missing.map(\.gameID), ["CCCE01"])
    }

    func testSecondDiscIsDetectedWhenOnlyFirstIsOnDrive() {
        let cube = "CISO/GC"
        let library = [[game("GTSE01", disc: 0, type: cube), game("GTSE01", disc: 1, type: cube)]]
        let missing = LibrarySync.missing(from: library, on: [game("GTSE01", disc: 0, type: "ISO/GC", path: "/drive/g")])
        XCTAssertEqual(missing.map(\.discNumber), [1], "Disc 2 shares the game ID but is a separate game file")
    }

    func testRawWBFSDrivesOnlyAskForWiiGames() {
        let library = [[game("AAAE01"), game("GTSE01", type: "CISO/GC")]]
        XCTAssertEqual(LibrarySync.missing(from: library, on: [], wiiOnly: true).map(\.gameID), ["AAAE01"])
        XCTAssertEqual(LibrarySync.missing(from: library, on: [], wiiOnly: false).count, 2)
    }

    func testRegionalVariantsAreDifferentGames() {
        let missing = LibrarySync.missing(from: [[game("RMCP01")]], on: [game("RMCE01", path: "/drive/m")])
        XCTAssertEqual(missing.map(\.gameID), ["RMCP01"])
    }
}
