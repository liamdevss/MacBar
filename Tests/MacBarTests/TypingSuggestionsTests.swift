import XCTest
@testable import MacBar

final class TypingSuggestionsTests: XCTestCase {
    func testTrailingWordStopsAtNonLetters() {
        XCTAssertEqual(TypingSuggestions.trailingWord("hello wrold"), "wrold")
        XCTAssertEqual(TypingSuggestions.trailingWord("it's don’t"), "don’t")
        XCTAssertEqual(TypingSuggestions.trailingWord("hello "), "")
        XCTAssertEqual(TypingSuggestions.trailingWord("abc123"), "")
    }

    func testBuildPutsTypedWordThenCorrectionThenCompletions() {
        let list = TypingSuggestions.build(word: "kow", correction: "know",
                                           candidates: [("kow", 3), ("kowtow", 3), ("kowtows", 3)])
        XCTAssertEqual(list.map(\.display), ["“kow”", "know", "kowtow"])
        XCTAssertEqual(list.map(\.text), ["kow ", "know ", "kowtow "])
        XCTAssertEqual(list.map(\.deleteCount), [3, 3, 3])
    }

    func testBuildShowsPredictionsAfterSpace() {
        let list = TypingSuggestions.build(word: "", correction: nil,
                                           candidates: [("be", 0), ("have", 0), ("do", 0), ("go", 0)])
        XCTAssertEqual(list.map(\.display), ["be", "have", "do"])
        XCTAssertEqual(list.map(\.deleteCount), [0, 0, 0])
    }
}
