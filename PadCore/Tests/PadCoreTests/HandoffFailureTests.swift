import Testing
@testable import PadCore

struct HandoffFailureTests {
    @Test(arguments: [Handoff.Failure.reading, .writing])
    func failuresNeverEnableAddressOnlySharingWithoutAChoice(failure: Handoff.Failure) {
        let stage = Handoff.Stage.failed(failure)
        #expect(!stage.hasFile)
        #expect(stage.isSettled)
        #expect(stage.progress(of: .choose) != .working)
        #expect(stage.headline != Handoff.Stage.wordsOnly.headline)
    }
    @Test func explicitAddressOnlyChoiceHasNoFile() {
        #expect(!Handoff.Stage.addressOnly.hasFile)
        #expect(Handoff.Stage.addressOnly.progress(of: .choose) == .working)
        #expect(Handoff.Stage.addressOnly.headline != Handoff.Stage.wordsOnly.headline)
    }
}
