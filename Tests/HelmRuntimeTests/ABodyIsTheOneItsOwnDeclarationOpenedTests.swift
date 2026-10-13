import HelmTestSupport
import XCTest

/// `SwiftSource.bodiesNamed`, `body(of:in:)` and `functionBodies(in:)` hand back
/// the block the named declaration itself opened, and no other.
///
/// **Why this is a test.** The reading keeps a pending name from a `func` or
/// `init` word to the next `{` at parenthesis depth zero, and three shapes once
/// let a name wait for a brace that was not its own: the bare word `init` in a
/// call (`super.init()`, `.init(…)`, `map(Item.init)`) named the next `if`
/// block; a declaration with no body, a protocol requirement, left its name for
/// the type that followed it; an operator function was named after its first
/// parameter, because the operator is not a word. Each row reads a fixture
/// string written here, never a file under `Sources`, so a live file moving
/// does not move the proof. Every message prints what came back — the first
/// line and the length of each body, or the names read — so a red row reads
/// without the source.
///
/// **What a row cannot pass on.** A row that expects no stray body also expects
/// the real one, so a helper that returned nothing at all would fail every
/// row. The rows under the last mark are the declarations a change to the
/// pending name must keep reading, written as the shapes it is likeliest to
/// lose.
final class ABodyIsTheOneItsOwnDeclarationOpenedTests: XCTestCase {

    // MARK: - Reading what came back

    /// The first non-empty line of a body, trimmed — what a reader recognises it by.
    private func firstLine(_ body: String) -> String {
        body.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    /// Every body that came back, as «first line» and its length in characters.
    private func summary(_ bodies: [String]) -> String {
        "\(bodies.count) body(ies): "
        + bodies.map { "«\(firstLine($0))» (\($0.count) chars)" }.joined(separator: ", ")
    }

    /// `bodiesNamed(name)` returns exactly these bodies, told apart by their first
    /// line, in this order. An expected list that is empty asserts the absence; a
    /// non-empty one asserts the presence as well, which is what keeps a helper
    /// that answers nothing from passing.
    private func expectBodies(named name: String, in source: String, firstLines expected: [String],
                              _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let got = SwiftSource.bodiesNamed(name, in: source)
        XCTAssertEqual(got.map(firstLine), expected,
            "\(context): bodiesNamed(\"\(name)\") returned \(summary(got)); expected \(expected.count) "
            + "starting \(expected.map { "«\($0)»" }.joined(separator: ", "))",
            file: file, line: line)
    }

    // MARK: - A call to init is not a declaration

    /// A function that holds one statement, then an `if` block, with the
    /// statement in front of it.
    private func builder(calling statement: String) -> String {
        "struct Builder {\n    func build() {\n        \(statement)\n"
        + "        if ready {\n            start()\n        }\n    }\n}\n"
    }

    /// The shape of the settings window's initialiser: a `super.init()` and then
    /// an `if let` block. The initialiser's own body is the only block named
    /// `init`.
    func testASuperInitCallDoesNotNameTheIfBlockAfterIt() {
        let source = """
        final class Window {
            init() {
                super.init()
                window.delegate = self
                if let toolbar {
                    toolbar.window = window
                }
            }
        }
        """
        expectBodies(named: "init", in: source, firstLines: ["super.init()"], "super.init() then if let")
    }

    /// `body(of:)` is the first body that closed, and the `if` block closes before
    /// the initialiser that holds it.
    func testBodyOfInitIsTheInitialisersBodyNotTheBlockThatClosesFirst() {
        let source = """
        final class Window {
            init() {
                super.init()
                if let toolbar {
                    toolbar.window = window
                }
            }
        }
        """
        let first = SwiftSource.body(of: "init", in: source)
        XCTAssertEqual(first.map(firstLine), "super.init()",
            "body(of: \"init\") returned «\(first.map(firstLine) ?? "nil")» (\(first?.count ?? 0) chars); "
            + "the initialiser's own body starts with «super.init()»")
    }

    /// A call that spells the initialiser out through its type or through an
    /// implicit member, in a function that declares no `init` at all.
    func testADotInitCallDoesNotNameTheBraceAfterIt() {
        for statement in ["let made = Item.init(id: 1)", "let made: Item = .init(id: 1)",
                          "let made = try Item.init(id: 1)"] {
            let source = builder(calling: statement)
            expectBodies(named: "init", in: source, firstLines: [], "«\(statement)» then if")
            expectBodies(named: "build", in: source, firstLines: [statement], "«\(statement)» then if")
        }
    }

    /// An initialiser handed on as a function value: bare, and spelled with its
    /// argument labels.
    func testAnInitPassedAsAFunctionDoesNotNameTheBraceAfterIt() {
        for statement in ["let made = ids.map(Item.init)", "let made = ids.compactMap(Item.init(rawValue:))",
                          "let made = ids.map(Item.init(id:))"] {
            let source = builder(calling: statement)
            expectBodies(named: "init", in: source, firstLines: [], "«\(statement)» then if")
            expectBodies(named: "build", in: source, firstLines: [statement], "«\(statement)» then if")
        }
    }

    /// The declaration and the call in one type: only the declaration's body is
    /// an `init`, wherever the call sits.
    func testACallBesideARealInitialiserLeavesOnlyTheInitialiser() {
        let source = """
        struct Item {
            init(id: Int) {
                self.id = id
            }
            func copy() -> Item {
                let made = Item.init(id: id)
                if made.id > 0 {
                    return made
                }
                return self
            }
        }
        """
        expectBodies(named: "init", in: source, firstLines: ["self.id = id"], "declaration beside a call")
        expectBodies(named: "copy", in: source,
                     firstLines: ["let made = Item.init(id: id)"], "declaration beside a call")
    }

    /// The word `init` with no dot in front of it and no parenthesis, `?`, `!` or
    /// `<` after it names nothing: a comment line or a string that says "init"
    /// stands in a raw read exactly where a declaration would, in front of an
    /// `if` block, and in a label.
    func testTheWordInitInProseOrInAStringNamesNoBlockAfterIt() {
        for statement in ["// init", "// the init sets it up", "let text = \"init\"",
                          "let note = \"the init runs first\"", "call(init: 1)"] {
            let source = builder(calling: statement)
            expectBodies(named: "init", in: source, firstLines: [], "«\(statement)» then if")
            expectBodies(named: "build", in: source, firstLines: [statement], "«\(statement)» then if")
        }
    }

    /// The same words above the brace of a type, where a name read from them
    /// would take the whole type for the body of an initialiser.
    func testTheWordInitInACommentAboveATypeNamesNoBodyForIt() {
        for comment in ["// The init of the shape is explained below.", "/// Built by init, never by a literal.",
                        "/* init */"] {
            let source = "\(comment)\nstruct Shape {\n    func draw() {\n        paint()\n    }\n}\n"
            expectBodies(named: "init", in: source, firstLines: [], "«\(comment)» above a type")
            expectBodies(named: "draw", in: source, firstLines: ["paint()"], "«\(comment)» above a type")
        }
    }

    // MARK: - A declaration with no body names nothing after it

    /// The shape of the fold link: a protocol whose last requirement is `stop`,
    /// then a class. Here the class does not declare `stop` itself, so nothing
    /// is a body of `stop`, and the class body is not one.
    func testAProtocolRequirementDoesNotNameTheTypeAfterIt() {
        let source = """
        protocol FoldLink {
            func start()
            func stop()
        }

        final class DisplayFoldLink: FoldLink {
            var running = false
            func begin() {
                running = true
            }
        }
        """
        expectBodies(named: "stop", in: source, firstLines: [], "requirement then a class without it")
        expectBodies(named: "begin", in: source, firstLines: ["running = true"], "requirement then a class")
        XCTAssertNil(SwiftSource.body(of: "stop", in: source),
            "body(of: \"stop\") returned the class that follows the requirement: "
            + "\(summary(SwiftSource.bodiesNamed("stop", in: source)))")
    }

    /// The same protocol with the class implementing the requirement: the one
    /// `stop` body is the method's, and the class is not a second.
    func testAProtocolRequirementBesideItsImplementationLeavesOnlyTheImplementation() {
        let source = """
        protocol FoldLink {
            func start()
            func stop()
        }

        final class DisplayFoldLink: FoldLink {
            func start() {
                running = true
            }
            func stop() {
                running = false
            }
        }
        """
        expectBodies(named: "stop", in: source, firstLines: ["running = false"], "requirement then its implementation")
        expectBodies(named: "start", in: source, firstLines: ["running = true"], "requirement then its implementation")
    }

    /// A requirement with parameters and a return type, and an extension after it:
    /// an `extension` body is not a body of the requirement either.
    func testAProtocolRequirementDoesNotNameAnExtensionAfterIt() {
        let source = """
        protocol Notice {
            func post(_ text: String, area: String) -> Bool
        }

        extension Notice {
            func shout(_ text: String) {
                _ = post(text, area: "all")
            }
        }
        """
        expectBodies(named: "post", in: source, firstLines: [], "requirement then an extension")
        expectBodies(named: "shout", in: source, firstLines: ["_ = post(text, area: \"all\")"],
                     "requirement then an extension")
    }

    /// A requirement followed by a struct that holds a computed property: the
    /// struct's brace is the first one after the requirement.
    func testAProtocolRequirementDoesNotNameAStructAfterIt() {
        let source = """
        protocol Counting {
            func total() -> Int
        }

        struct Tally {
            var size: Int { items.count }
            func describe() {
                print(size)
            }
        }
        """
        expectBodies(named: "total", in: source, firstLines: [], "requirement then a struct")
        expectBodies(named: "describe", in: source, firstLines: ["print(size)"], "requirement then a struct")
    }

    /// A function requirement followed by a property requirement with a brace of
    /// its own: that brace is the property's, not the function's.
    func testAFunctionRequirementDoesNotNameTheBraceOfAPropertyRequirement() {
        let source = """
        protocol Sized {
            func grow()
            var size: Int { get }
            func shrink() -> Bool
            var label: String { get set }
        }

        struct Box {
            func settle() {
                settling()
            }
        }
        """
        expectBodies(named: "grow", in: source, firstLines: [], "requirement then a var requirement")
        expectBodies(named: "shrink", in: source, firstLines: [], "requirement then a var requirement")
        expectBodies(named: "settle", in: source, firstLines: ["settling()"], "requirement then a var requirement")
    }

    /// The same with a subscript requirement, whose parameter list holds no brace
    /// and whose own brace follows the return type.
    func testAFunctionRequirementDoesNotNameTheBraceOfASubscriptRequirement() {
        let source = """
        protocol Indexed {
            func reset()
            subscript(index: Int) -> Int { get }
            func clear() -> Bool
            subscript(name: String) -> String { get set }
        }

        struct Table {
            func settle() {
                settling()
            }
        }
        """
        expectBodies(named: "reset", in: source, firstLines: [], "requirement then a subscript requirement")
        expectBodies(named: "clear", in: source, firstLines: [], "requirement then a subscript requirement")
        expectBodies(named: "settle", in: source, firstLines: ["settling()"],
                     "requirement then a subscript requirement")
    }

    /// A function named by `var` or `subscript` in backticks is a function like
    /// any other: the word after `func` is its name, not the start of a property
    /// or a subscript.
    func testAFunctionNamedByAPropertyWordInBackticksKeepsItsOwnBody() {
        let source = """
        struct Words {
            func `var`() {
                varBody()
            }
            func `subscript`(index: Int) {
                subscriptBody()
            }
        }
        """
        expectOne("var", in: source, startsWith: "varBody()", "function named var")
        expectOne("subscript", in: source, startsWith: "subscriptBody()", "function named subscript")
    }

    // MARK: - An operator is not named after its first parameter

    /// An operator function: the first word after `func` is the first
    /// parameter's label or name, and the operator is not a word. No body may
    /// come back under a parameter's name; each comes back under its operator
    /// as spelled, and a function beside them still comes back under its own.
    func testAnOperatorFunctionIsNamedByItsOperatorAndNotByItsFirstParameter() {
        let source = """
        struct Version {
            let major: Int
            static func < (lhs: Version, rhs: Version) -> Bool {
                lhs.major < rhs.major
            }
            static func == (_ left: Version, _ right: Version) -> Bool {
                left.major == right.major
            }
            static func + (first: Version, second: Version) -> Version {
                Version(major: first.major + second.major)
            }
            func describe() -> String {
                "v\\(major)"
            }
        }
        """
        let names = SwiftSource.functionBodies(in: source).map(\.name)
        XCTAssertEqual(names, ["<", "==", "+", "describe"],
            "function bodies in closing order are named \(names); expected the operators as spelled, then describe")
        expectOne("<", in: source, startsWith: "lhs.major < rhs.major", "operator <")
        expectOne("==", in: source, startsWith: "left.major == right.major", "operator ==")
        expectOne("+", in: source, startsWith: "Version(major: first.major + second.major)", "operator +")
        expectBodies(named: "describe", in: source, firstLines: ["\"v\\(major)\""], "operators beside a method")
        for parameter in ["lhs", "rhs", "_", "left", "right", "first", "second"] {
            let got = SwiftSource.bodiesNamed(parameter, in: source)
            XCTAssertEqual(got.count, 0,
                "an operator's parameter «\(parameter)» named a body: returned \(summary(got)); "
                + "all names read: \(names)")
        }
    }

    // MARK: - What a repair of the pending name must keep reading

    /// Exactly one body under `name`, told by its first line.
    private func expectOne(_ name: String, in source: String, startsWith first: String, _ context: String,
                           file: StaticString = #filePath, line sourceLine: UInt = #line) {
        expectBodies(named: name, in: source, firstLines: [first], context, file: file, line: sourceLine)
    }

    /// A brace on the line after the signature.
    func testABraceOnTheNextLineStillOpensTheDeclaration() {
        let source = """
        struct Store {
            func load()
            {
                read()
            }
            init()
            {
                self.items = []
            }
            func save() -> Bool
            {
                write()
            }
        }
        """
        expectOne("load", in: source, startsWith: "read()", "brace on the next line")
        expectOne("init", in: source, startsWith: "self.items = []", "brace on the next line")
        expectOne("save", in: source, startsWith: "write()", "brace on the next line")
    }

    /// A parameter list over several lines, a return type on its own line, a
    /// `where` clause on its own line, `async throws` on a continuation line.
    func testASignatureThatContinuesOverLinesStillOpensTheDeclaration() {
        let source = """
        struct Store {
            func many(
                first: Int,
                second: String
            ) {
                useMany()
            }
            func returning(first: Int)
                -> Bool {
                useReturning()
            }
            func constrained<T>(first: T)
                where T: Equatable {
                useConstrained()
            }
            func waiting(first: Int)
                async throws {
                useWaiting()
            }
            func everything<T>(
                first: T
            )
                async throws
                -> Bool
                where T: Equatable
            {
                useEverything()
            }
        }
        """
        for name in ["many", "returning", "constrained", "waiting", "everything"] {
            let use = "use" + name.prefix(1).uppercased() + name.dropFirst() + "()"
            expectOne(name, in: source, startsWith: use, "signature over lines")
        }
    }

    /// The initialiser spelled failable, implicitly unwrapped, generic, and
    /// behind `convenience`, `required` and an access modifier.
    func testEveryKindOfInitialiserStillOpensItsDeclaration() {
        let source = """
        class Shape {
            init?(raw: Int) {
                failable()
            }
            init!(forced: Int) {
                implicit()
            }
            init<T>(generic: T) {
                generic()
            }
            convenience init(plain: Int) {
                plain()
            }
            required init?(coder: Coder) {
                required()
            }
            public required convenience init!(both: Int) {
                both()
            }
        }
        """
        let got = SwiftSource.bodiesNamed("init", in: source)
        XCTAssertEqual(got.map(firstLine),
                       ["failable()", "implicit()", "generic()", "plain()", "required()", "both()"],
                       "init variants: bodiesNamed(\"init\") returned \(summary(got))")
    }

    /// A default value that is a closure sits inside the parameter list and
    /// leaves the declaration's name for its own body.
    func testADefaultClosureInTheParameterListStillLeavesTheDeclarationItsBody() {
        let source = """
        struct Runner {
            init(then: () -> Void = { }, other: Int = 1) {
                ready()
            }
            func run(after: () -> Void = { print(1) }) {
                go()
            }
        }
        """
        expectOne("init", in: source, startsWith: "ready()", "default closure")
        expectOne("run", in: source, startsWith: "go()", "default closure")
    }

    /// Overloads: each one comes back, and siblings in the order they stand in
    /// the file (a body is filed when it closes).
    func testAnOverloadedNameReturnsEachBodyInSourceOrder() {
        let source = """
        struct Store {
            func put(_ value: Int) {
                putInt()
            }
            func put(_ value: String) {
                putString()
            }
            func put(_ value: Int, at index: Int) {
                putIndexed()
            }
            init(items: [Int]) {
                fromItems()
            }
            init(count: Int) {
                fromCount()
            }
        }
        """
        let put = SwiftSource.bodiesNamed("put", in: source)
        XCTAssertEqual(put.map(firstLine), ["putInt()", "putString()", "putIndexed()"],
                       "overloads of put: returned \(summary(put))")
        let initialisers = SwiftSource.bodiesNamed("init", in: source)
        XCTAssertEqual(initialisers.map(firstLine), ["fromItems()", "fromCount()"],
                       "overloaded init: returned \(summary(initialisers))")
    }

    /// A function inside a function, and a function inside a type declared inside
    /// a function: every body under its own name, the outer one holding the rest.
    func testNestedFunctionsEachKeepTheirOwnBody() {
        let source = """
        struct Outer {
            func outer() {
                outerStart()
                func inner() {
                    innerStart()
                    func innermost() {
                        innermostOnly()
                    }
                }
                struct Local {
                    func member() {
                        memberOnly()
                    }
                }
            }
            struct Nested {
                func nested() {
                    nestedOnly()
                }
            }
        }
        """
        expectOne("outer", in: source, startsWith: "outerStart()", "nesting")
        expectOne("inner", in: source, startsWith: "innerStart()", "nesting")
        expectOne("innermost", in: source, startsWith: "innermostOnly()", "nesting")
        expectOne("member", in: source, startsWith: "memberOnly()", "nesting")
        expectOne("nested", in: source, startsWith: "nestedOnly()", "nesting")
        let outer = SwiftSource.bodiesNamed("outer", in: source).first ?? ""
        XCTAssertTrue(outer.contains("innermostOnly()") && outer.contains("memberOnly()"),
            "the outer body lost what it holds: returned \(summary([outer]))")
        let inner = SwiftSource.bodiesNamed("inner", in: source).first ?? ""
        XCTAssertFalse(inner.contains("outerStart()") || inner.contains("memberOnly()"),
            "the inner body took in what is outside it: returned \(summary([inner]))")
    }
}
