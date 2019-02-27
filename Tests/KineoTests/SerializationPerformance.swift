import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension SerializationPerformanceTest {
    static var allTests : [(String, (SerializationPerformanceTest) -> () throws -> Void)] {
        return [
            ("testPerformance_ntriplesSerialization", testPerformance_ntriplesSerialization),
        ]
    }
}
#endif

class SerializationPerformanceTest: XCTestCase {
    override func setUp() {
        super.setUp()
    }
    
    private func testTriples(_ scale: Int = 1_000) -> AnySequence<Triple> {
        let counter = sequence(first: 1) { $0 + 1 }.prefix(scale)

        let s1 = Term(iri: "http://example.org/s1")
        let s2 = Term(iri: "http://example.org/s2")
        let p = Term(iri: "http://example.org/ns/p")
        let q = Term(iri: "http://example.org/ns/q")
        let r = Term(iri: "http://example.org/ns/r")

        var triples = [Triple]()
        for i in counter {
            let integer = Term(integer: i)
            let uuid = Term(string: NSUUID().uuidString)
            let hash = Term(string: "\(i.hashValue)")
            let ascii = (97...122).map { Character(UnicodeScalar($0)!) }
            let kana = (12354...12380).map { Character(UnicodeScalar($0)!) }
            
            let languages = ["en", "fr", "de", "ja", "en-GB", "no"]

            let string: Term
            if Int.random(in: 0...99) < 90 {
                let str = String((0..<Int.random(in: 0...scale)).compactMap { (_) -> Character in
                    ascii.randomElement()!
                })
                let lang = languages.randomElement()!
                string = Term(value: str, type: .language(lang))
            } else {
                let str = String((0..<Int.random(in: 0...scale)).compactMap { (_) -> Character in
                    kana.randomElement()!
                })
                let lang = "ja"
                string = Term(value: str, type: .language(lang))
            }
            
            triples.append(Triple(subject: s1, predicate: p, object: integer))
            triples.append(Triple(subject: s1, predicate: q, object: uuid))
            triples.append(Triple(subject: s2, predicate: q, object: hash))
            triples.append(Triple(subject: s2, predicate: r, object: string))
        }
        return AnySequence(triples)
    }
    
    func testPerformance_ntriplesSerialization() throws {
        let triples = testTriples(800)
        let ser = NTriplesSerializer()
        self.measure {
            var s = ""
            try? ser.serialize(triples, to: &s)
        }
    }
}
