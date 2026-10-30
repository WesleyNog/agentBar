import Testing
@testable import AgentBarCore

@Suite("UsageLevel")
struct UsageLevelTests {
    @Test(arguments: [
        (0.0, UsageLevel.normal),
        (69.9, .normal),
        (70, .warning),
        (89.9, .warning),
        (90, .critical),
        (130, .critical),
    ])
    func faixas(percentage: Double, expected: UsageLevel) {
        #expect(UsageLevel(percentage: percentage) == expected)
    }
}

@Suite("PercentFormat")
struct PercentFormatTests {
    @Test func semDados() {
        #expect(PercentFormat.short(nil) == "--")
        #expect(PercentFormat.short(.nan) == "--")
    }

    @Test func arredondaParaBaixo() {
        #expect(PercentFormat.short(27) == "27%")
        #expect(PercentFormat.short(27.9) == "27%")
        #expect(PercentFormat.short(100) == "100%")
    }

    @Test func negativoViraZero() {
        #expect(PercentFormat.short(-3) == "0%")
    }
}
