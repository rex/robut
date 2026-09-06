// RobotMoodGridTests.swift — the robot's pixel grids stay well-formed.
//
// Both renderers size the glyph from the widest row and draw whatever
// each row contains, so a mistyped row (15 characters, a stray space)
// misrenders silently — a lopsided robot in the menubar with no error
// anywhere. These pin the shape the renderers assume.

import Testing

@testable import Robut

@Suite("Robot pixel grids")
struct RobotMoodGridTests {

    private let moods: [RobotMood] = [.calm, .squint, .alarmed, .dim]

    @Test("Every mood is a full 16×16 grid")
    func gridsAre16By16() {
        for mood in moods {
            #expect(mood.pixels.count == 16, "\(mood) has \(mood.pixels.count) rows")
            for (index, row) in mood.pixels.enumerated() {
                #expect(row.count == 16, "\(mood) row \(index) is \(row.count) wide")
            }
        }
    }

    @Test("The moods are distinct faces, not one face recoloured")
    func moodsDiffer() {
        #expect(Set(moods.map(\.pixels)).count == 4)
    }

    @Test("The antenna is on row 0 — the row both renderers draw at the top")
    func antennaOnTop() {
        #expect(RobotMood.calm.pixels[0].contains("#"))
        // Breathing room under the body, so the glyph isn't glued to the
        // bottom of the menubar cell.
        #expect(!RobotMood.calm.pixels[15].contains("#"))
    }
}
