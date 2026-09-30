import Testing
@testable import SealbreakCore

struct SealStatusMotionTests {
    @Test
    func unknownToUnsealedResolvesWithoutHeroEffect() {
        var motion = SealStatusMotion(phase: .unknown)

        motion.transition(to: .unsealed)

        #expect(motion.phase == .unsealed)
        #expect(motion.effect == .none)
        #expect(motion.unsealRevealProgress == 1)
        #expect(motion.resultScale == 1)
    }

    @Test
    func sealedToUnsealedStartsRevealThenResultEffect() {
        var motion = SealStatusMotion(phase: .sealed)

        motion.transition(to: .unsealed)
        let revealID = motion.animationID

        #expect(motion.effect == .unsealReveal)
        #expect(motion.unsealRevealProgress == 0)

        #expect(motion.setUnsealRevealProgress(1, for: revealID))
        #expect(motion.unsealRevealProgress == 1)
        #expect(motion.completeUnsealReveal(for: revealID))

        #expect(motion.effect == .result)
        #expect(motion.animationID != revealID)
    }

    @Test
    func unknownInvalidatesPendingUnsealReveal() {
        var motion = SealStatusMotion(phase: .sealed)
        motion.transition(to: .unsealed)
        let staleRevealID = motion.animationID

        motion.transition(to: .unknown)

        #expect(motion.phase == .unknown)
        #expect(motion.effect == .none)
        #expect(motion.unsealRevealProgress == 0)
        #expect(motion.resultScale == 1)
        #expect(!motion.completeUnsealReveal(for: staleRevealID))
        #expect(!motion.setUnsealRevealProgress(1, for: staleRevealID))
    }

    @Test
    func resealInvalidatesPendingUnsealRevealAndStartsOneResultEffect() {
        var motion = SealStatusMotion(phase: .sealed)
        motion.transition(to: .unsealed)
        let staleRevealID = motion.animationID

        motion.transition(to: .sealed)
        let resealResultID = motion.animationID

        #expect(motion.phase == .sealed)
        #expect(motion.effect == .result)
        #expect(!motion.completeUnsealReveal(for: staleRevealID))
        #expect(motion.animationID == resealResultID)
        #expect(motion.setResultScale(0.96, for: resealResultID))
        #expect(motion.resultScale == 0.96)
    }

    @Test
    func newerStatusResetsInFlightResultScale() {
        var motion = SealStatusMotion(phase: .unsealed)
        motion.transition(to: .sealed)
        let staleResultID = motion.animationID

        #expect(motion.setResultScale(0.96, for: staleResultID))
        #expect(motion.resultScale == 0.96)

        motion.transition(to: .unknown)

        #expect(motion.resultScale == 1)
        #expect(motion.effect == .none)
        #expect(!motion.setResultScale(1.045, for: staleResultID))
    }

    @Test
    func repeatedPhaseDoesNotCreateNewAnimationGeneration() {
        var motion = SealStatusMotion(phase: .sealed)
        let initialID = motion.animationID

        motion.transition(to: .sealed)

        #expect(motion.animationID == initialID)
        #expect(motion.generation == 0)
    }
}
