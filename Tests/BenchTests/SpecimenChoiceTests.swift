// SpecimenChoiceTests.swift — picking specimens one by one and by category.
// Uses the real catalogue: specimens are drawings, not anyone's data.
import Testing
@testable import Bench

struct SpecimenChoiceTests {
    private func scenes(_ group: SceneGroup) -> [LabScene] {
        LabScenes.catalogue.filter { $0.theme.group == group }
    }

    @Test func aSpecimenInACategoryThatIsOffComesOnAlone() throws {
        var choice = SpecimenChoice.all
        choice.set(.data, on: false)
        let plot = try #require(scenes(.data).first)
        choice.toggle(plot)
        #expect(choice.isOn(plot))
        #expect(choice.onCount(in: .data) == 1)
        #expect(choice.state(of: .data) == .mixed)
    }

    @Test func switchingOffACategorysLastSpecimenSwitchesTheCategoryOff() {
        var choice = SpecimenChoice.all
        for scene in scenes(.earth) { choice.toggle(scene) }
        #expect(choice.state(of: .earth) == .off)
        // Off as a category, so specimens it gains in an update stay off too.
        #expect(!choice.groups.contains(.earth))
        #expect(choice.hidden.isEmpty)
    }

    @Test func aMixedCategoryGoesAllOnThenAllOff() throws {
        var choice = SpecimenChoice.all
        choice.toggle(try #require(scenes(.chemistry).first))
        #expect(choice.state(of: .chemistry) == .mixed)
        choice.toggle(.chemistry)
        #expect(choice.state(of: .chemistry) == .on)
        choice.toggle(.chemistry)
        #expect(choice.state(of: .chemistry) == .off)
    }

    @Test func playOnlyLeavesOneSpecimen() throws {
        var choice = SpecimenChoice.all
        let one = try #require(scenes(.biology).last)
        choice.playOnly(one)
        #expect(choice.onCount == 1)
        #expect(choice.rotation.scenes.map(\.name) == [one.name])
    }

    @Test func theLastSpecimenOnStaysOn() throws {
        var choice = SpecimenChoice.all
        let one = try #require(scenes(.physics).first)
        choice.playOnly(one)
        choice.toggle(one)
        #expect(choice.isOn(one))
        choice.set(.physics, on: false)
        #expect(choice.isOn(one))
        #expect(!choice.canTurnOff(.physics))
        #expect(!choice.canTurnOff(one))
    }

    @Test func noneKeepsTheFirstSpecimenThatWasOn() throws {
        var choice = SpecimenChoice.all
        choice.set(.lab, on: false)
        choice.setAll(on: false)
        #expect(choice.onCount == 1)
        let kept = try #require(LabScenes.catalogue.first(where: choice.isOn))
        #expect(kept.theme.group != .lab)
        choice.setAll(on: true)
        #expect(choice == .all)
    }

    @Test func aStoredChoiceThatPlaysNothingStartsAfresh() {
        #expect(SpecimenChoice(groups: [], hidden: []) == .all)
        let everyLabName = Set(scenes(.lab).map(\.name))
        #expect(SpecimenChoice(groups: [.lab], hidden: everyLabName) == .all)
        // A category stored on with all its specimens off is stored off.
        let tidied = SpecimenChoice(groups: [.lab, .data], hidden: everyLabName)
        #expect(tidied.groups == [.data])
        #expect(tidied.hidden.isEmpty)
    }

    @Test func everythingOnIsTheFullRotation() {
        #expect(SpecimenChoice.all.rotation == .full)
    }
}
