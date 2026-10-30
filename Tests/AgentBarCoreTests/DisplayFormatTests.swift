import Testing
@testable import AgentBarCore

@Suite("DisplayFormat")
struct DisplayFormatTests {
    @Test(arguments: [
        (0, "0"),
        (999, "999"),
        (1_000, "1k"),
        (339_150, "339.2k"),
        (802_618, "802.6k"),
        (999_949, "999.9k"),
        (999_950, "1m"),
        (1_012_345, "1m"),
        (1_349_000, "1.3m"),
        (2_400_000, "2.4m"),
    ])
    func tokens(count: Int, expected: String) {
        #expect(DisplayFormat.tokens(count) == expected)
    }

    @Test(arguments: [
        (0.0, "0s"),
        (45.9, "45s"),
        (960, "16m 0s"),
        (1_429, "23m 49s"),
        (13_543, "3h 45m 43s"),
        (-5, "0s"),
    ])
    func duracao(seconds: Double, expected: String) {
        #expect(DisplayFormat.duration(seconds) == expected)
    }

    @Test(arguments: [
        (0.0, "<1m"),
        (59, "<1m"),
        (60, "1m"),
        (12_900, "3h 35m"),
        (129_600, "1d 12h"),
        (-30, "<1m"),
    ])
    func contagemRegressiva(seconds: Double, expected: String) {
        #expect(DisplayFormat.countdown(seconds) == expected)
    }

    @Test(arguments: [
        ("claude-opus-5-5", "Opus 5.5"),
        ("claude-fable-5-1", "Fable 5.1"),
        ("claude-sonnet-4-5-20250929", "Sonnet 4.5"),
        ("claude-haiku-5", "Haiku 5"),
        ("gpt-qualquer", "gpt-qualquer"),
        ("claude-opus-latest", "claude-opus-latest"),
    ])
    func nomeDoModelo(model: String, expected: String) {
        #expect(DisplayFormat.modelName(model) == expected)
    }
}
