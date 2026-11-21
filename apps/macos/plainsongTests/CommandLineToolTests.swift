import Foundation
@testable import Plainsong
import Testing

@Suite
struct CommandLineToolTests {
    @Test
    func shellReceivesOriginalPath() throws {
        let path = "/Users/a/Apps/Plainsong's Copy $HOME/Plainsong.app/Contents/SharedSupport/bin/song"
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "printf %s \(CommandLineTool.shellQuoted(path))"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let received = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        #expect(received == path)
    }
}
