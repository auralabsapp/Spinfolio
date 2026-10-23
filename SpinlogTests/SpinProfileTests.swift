import Testing
@testable import Spinlog

/// Mouvement du disque sur la platine : démarrage progressif, vitesse de croisière, ralentissement.
struct SpinProfileTests {
    private let profile = SpinProfile(omega: 200, startupDuration: 1, stopDuration: 2, startTime: 100)

    @Test func theDiscIsStillBeforeItStarts() {
        #expect(profile.angle(at: 99) == 0)
        #expect(profile.angle(at: 100) == 0)
    }

    @Test func startupAccelerates() {
        // Parabole : ω·τ²/(2d) → 100° au bout d'1 s, 25° au bout de 0,5 s.
        #expect(abs(profile.angle(at: 101) - 100) < 0.0001)
        #expect(abs(profile.angle(at: 100.5) - 25) < 0.0001)
    }

    @Test func atCruisingSpeedTheAngleGrowsLinearly() {
        let a = profile.angle(at: 103)
        let b = profile.angle(at: 104)
        #expect(abs((b - a) - 200) < 0.0001)
    }

    @Test func angleIsContinuousAtTheEndOfStartup() {
        let before = profile.angle(at: 100.999999)
        let after = profile.angle(at: 101.000001)
        #expect(abs(after - before) < 0.01)
    }

    @Test func stopDeceleratesThenSettlesForGood() {
        var stopped = profile
        stopped.stopTime = 110
        let atStop = stopped.angle(at: 110)
        let halfway = stopped.angle(at: 111)
        let settled = stopped.angle(at: 112)
        #expect(halfway > atStop)
        #expect(settled > halfway)
        // Distance de freinage : v·d/2 = 200·2/2.
        #expect(abs((settled - atStop) - 200) < 0.0001)
        #expect(stopped.angle(at: 500) == settled)
        #expect(stopped.isSettled(at: 112))
        #expect(!stopped.isSettled(at: 111))
    }

    @Test func angleNeverGoesBackwards() {
        var stopped = profile
        stopped.stopTime = 105
        var previous = -1.0
        for step in 0...400 {
            let angle = stopped.angle(at: 100 + Double(step) * 0.05)
            #expect(angle >= previous)
            previous = angle
        }
    }

    /// Un arrêt pendant le démarrage ralentit depuis la vitesse atteinte, donc plus vite.
    @Test func stoppingDuringStartupBrakesProportionally() {
        var early = profile
        early.stopTime = 100.5
        let speedFactorAtStop = 0.5
        let expectedBraking = 200 * speedFactorAtStop * (2 * speedFactorAtStop) / 2
        let atStop = early.angle(at: 100.5)
        let settled = early.angle(at: 110)
        #expect(abs((settled - atStop) - expectedBraking) < 0.0001)
    }

    @Test func neverSettledWhileTheListeningLasts() {
        #expect(!profile.isSettled(at: 100_000))
    }

    @Test func cassetteTapeProgressStaysInRangeAndIsPeriodic() {
        for angle in stride(from: 0.0, through: 100_000.0, by: 1_234.5) {
            let progress = CassetteView.tapeProgress(forAngle: angle)
            #expect(progress >= 0.2 - 1e-9 && progress <= 0.85 + 1e-9)
        }
        #expect(abs(CassetteView.tapeProgress(forAngle: 0) - 0.2) < 1e-9)
        #expect(abs(CassetteView.tapeProgress(forAngle: 21_600) - 0.85) < 1e-9)
        #expect(abs(CassetteView.tapeProgress(forAngle: 43_200) - 0.2) < 1e-9)
    }
}
