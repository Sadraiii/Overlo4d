import Foundation
import Testing
@testable import TallyCore

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tally-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func text(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}

@Suite struct StoreFileTests {
    @Test func backUpOnceKeepsTheFirstCopy() throws {
        let folder = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("gym.json")
        let backup = folder.appendingPathComponent("gym-before-0.6.json")

        try "0.5 data".write(to: file, atomically: true, encoding: .utf8)
        #expect(StoreFile.backUpOnce(file, to: backup))
        try "0.6 data".write(to: file, atomically: true, encoding: .utf8)
        #expect(!StoreFile.backUpOnce(file, to: backup))
        #expect(try text(backup) == "0.5 data")
    }

    @Test func backUpOnceWithoutAFileDoesNothing() throws {
        let folder = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let backup = folder.appendingPathComponent("gym-before-0.6.json")

        #expect(!StoreFile.backUpOnce(folder.appendingPathComponent("gym.json"), to: backup))
        #expect(!FileManager.default.fileExists(atPath: backup.path))
    }

    @Test func setAsideMovesAnUnreadableFileOutOfTheWay() throws {
        let folder = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("gym.json")
        try "not json".write(to: file, atomically: true, encoding: .utf8)

        let moved = try #require(StoreFile.setAside(file, stamp: "1700000000"))
        #expect(moved.lastPathComponent == "gym-unreadable-1700000000.json")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try text(moved) == "not json")
    }
}
