// SPDX-License-Identifier: Apache-2.0
import Liquid
import Foundation
import Testing

@Suite("Closed system rendering")
struct SystemRenderingTests {
    private func environment() throws -> LiquidSystemEnvironment {
        let descriptor = try LiquidSystemDescriptor([.init("title", .text("Child"))])
        let policy = try LiquidSystemPolicyIdentity(role: "content", bytes: [1], context: .htmlTextV1)
        let fragment = try LiquidSystemPolicyIdentity(role: "content", bytes: [2], context: .htmlFlowFragmentV1)
        let child: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("B")), descriptor: descriptor))
        let root: LiquidSystemValue = .decorated(.init(primary: .object([
            .init("child", child), .init("items", .array([child])),
            .init("$descriptor", .ordinary(.string("ordinary-dollar"))),
            .init("descriptor", .ordinary(.string("ordinary-name")))
        ]), descriptor: descriptor, plain: .qualified("plain"),
            htmlText: .qualified("A &amp; B", policy), html: .qualified("<b>Hi</b>", fragment)))
        return try LiquidSystemEnvironment([.init("article", root)])
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func propertiesAndOrdinaryKeysRemainDistinct(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let source = "{{ article.$descriptor.title }}|{{ article.$plain }}|{{ article.$htmlText }}|{{ article.$html }}|{{ article['$descriptor'] }}|{{ article.descriptor }}"
        let root = try LiquidTemplate(source, syntaxMode: mode, extensionProfile: .closedSystemV1)
        let registry = try LiquidTemplateRegistry([])
        #expect(try await engine.render(root, environment: environment(), registry: registry) == "Child|plain|A &amp; B|<b>Hi</b>|ordinary-dollar|ordinary-name")
        #expect(try engine.inspect(root).variableRoots == ["article"])
        #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: mode) }
        #expect(throws: LiquidError.self) { try LiquidTemplate("{{ article.$unknown }}", syntaxMode: mode, extensionProfile: .closedSystemV1) }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func childSelectionRetainsDecorationAndValueExtractionStripsIt(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let registry = try LiquidTemplateRegistry([])
        let keep = try LiquidTemplate("{{ article.child.$descriptor.title }}|{% assign selected = article.items | first %}{{ selected.$descriptor.title }}", syntaxMode: mode, extensionProfile: .closedSystemV1)
        #expect(try await engine.render(keep, environment: environment(), registry: registry) == "Child|Child")
        let strip = try LiquidTemplate("{{ article.$value.child.$descriptor.title }}", syntaxMode: mode, extensionProfile: .closedSystemV1)
        do { _ = try await engine.render(strip, environment: environment(), registry: registry); Issue.record("Decorations survived value extraction") }
        catch let error as LiquidSystemError { #expect(error == .unavailable(property: .descriptor, state: .notAdmitted)) }
    }

    @Test func typedUnavailableAndRegistryProfileAdmission() async throws {
        let engine = LiquidEngine()
        let bare: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("A"))))
        let env = try LiquidSystemEnvironment([.init("article", bare)])
        let root = try LiquidTemplate("{{ article.$descriptor }}", syntaxMode: .strict2, extensionProfile: .closedSystemV1)
        let empty = try LiquidTemplateRegistry([])
        do { _ = try await engine.render(root, environment: env, registry: empty); Issue.record("Unadmitted descriptor succeeded") }
        catch let error as LiquidSystemError { #expect(error == .unavailable(property: .descriptor, state: .notAdmitted)) }
        let plain = try LiquidTemplate("{{ article.$plain }}", syntaxMode: .strict2, extensionProfile: .closedSystemV1)
        do { _ = try await engine.render(plain, environment: env, registry: empty); Issue.record("Unrequested plain representation succeeded") }
        catch let error as LiquidSystemError { #expect(error == .unavailable(property: .plain, state: .notRequested)) }
        let standard = try LiquidTemplate("unrelated", syntaxMode: .strict2)
        let mixed = try LiquidTemplateRegistry([.init("unused", .parsed(standard))])
        do { _ = try await engine.render(root, environment: env, registry: mixed); Issue.record("Mixed profiles succeeded") }
        catch let error as LiquidSystemError { #expect(error == .incompatibleProfile) }
        #expect(throws: LiquidSystemError.incompatibleProfile) {
            try engine.inspectDependencies(root, registry: mixed, extensionProfile: .closedSystemV1)
        }
    }

    @Test func exactPartialBindingsAndFilterTrustLoss() async throws {
        let echo = LiquidFilter("identity") { value, _, _ in value }
        let engine = try LiquidEngine(filters: [echo])
        let source = "{% render 'p' with article.child as item %}|{% for x in article.items %}{{ x.$descriptor.title }}{% endfor %}"
        let root = try LiquidTemplate(source, syntaxMode: .strict2, extensionProfile: .closedSystemV1)
        let registry = try LiquidTemplateRegistry([.init("p.liquid", .raw("{{ item.$descriptor.title }}"))])
        #expect(try await engine.render(root, environment: environment(), registry: registry) == "Child|Child")
        let graph = try engine.inspectDependencies(root, registry: registry, extensionProfile: .closedSystemV1)
        #expect(graph.nodes.count == 2)
        let stripped = try LiquidTemplate("{% assign result = article.child | identity %}{{ result.$descriptor }}", syntaxMode: .strict2, extensionProfile: .closedSystemV1)
        do { _ = try await engine.render(stripped, environment: environment(), registry: registry); Issue.record("Custom filter result acquired decoration") }
        catch let error as LiquidSystemError { #expect(error == .unavailable(property: .descriptor, state: .notAdmitted)) }
        let explicitEscape = try LiquidTemplate("{{ article.$htmlText | escape }}", syntaxMode: .strict2, extensionProfile: .closedSystemV1)
        #expect(try await engine.render(explicitEscape, environment: environment(), registry: registry) == "A &amp;amp; B")
    }

    @Test func primaryTruthinessAndUnavailableRepresentations() async throws {
        let root: LiquidSystemValue = .decorated(.init(primary: .ordinary(.bool(false)), plain: .unavailable("not ready"), htmlText: .optionalFailure("failed")))
        let env = try LiquidSystemEnvironment([.init("flag", root)])
        let engine = LiquidEngine(); let registry = try LiquidTemplateRegistry([])
        let test = try LiquidTemplate("{% if flag %}yes{% else %}no{% endif %}", extensionProfile: .closedSystemV1)
        #expect(try await engine.render(test, environment: env, registry: registry) == "no")
        let plain = try LiquidTemplate("{{ flag.$plain }}", extensionProfile: .closedSystemV1)
        do { _ = try await engine.render(plain, environment: env, registry: registry); Issue.record("Unavailable plain output succeeded") }
        catch let error as LiquidSystemError { #expect(error == .unavailable(property: .plain, state: .unavailable("not ready"))) }
        let html = try LiquidTemplate("{{ flag.$htmlText }}", extensionProfile: .closedSystemV1)
        do { _ = try await engine.render(html, environment: env, registry: registry); Issue.record("Optional failure output succeeded") }
        catch let error as LiquidSystemError { #expect(error == .unavailable(property: .htmlText, state: .optionalFailure("failed"))) }
    }

    @Test func selectingFiltersRetainChildrenAndNewContainersLoseDecoration() async throws {
        func item(_ key: String, _ title: String) throws -> LiquidSystemValue {
            .decorated(.init(primary: .object([.init("key", .ordinary(.string(key)))]),
                             descriptor: try LiquidSystemDescriptor([.init("title", .text(title))])))
        }
        let first = try item("b", "B"); let second = try item("a", "A")
        let parent = LiquidSystemValue.decorated(.init(primary: .array([first, second, first]),
            descriptor: try LiquidSystemDescriptor([.init("title", .text("Container"))])))
        let env = try LiquidSystemEnvironment([.init("items", parent)])
        let engine = LiquidEngine(); let registry = try LiquidTemplateRegistry([])
        let source = """
        {% assign v = items | first %}{{ v.$descriptor.title }}|
        {% assign v = items | last %}{{ v.$descriptor.title }}|
        {% assign v = items | reverse %}{{ v[1].$descriptor.title }}|
        {% assign v = items | sort: 'key' %}{{ v[0].$descriptor.title }}|
        {% assign v = items | where: 'key', 'a' %}{{ v[0].$descriptor.title }}|
        {% assign v = items | uniq %}{{ v[0].$descriptor.title }}|
        {% assign v = items | slice: 1, 1 %}{{ v[0].$descriptor.title }}|
        {% assign v = items | concat: items %}{{ v[3].$descriptor.title }}|
        {% assign v = items | default: 'fallback' %}{{ v.$descriptor.title }}
        """
        let template = try LiquidTemplate(source, syntaxMode: .strict2, extensionProfile: .closedSystemV1)
        let output = try await engine.render(template, environment: env, registry: registry)
        #expect(output.replacingOccurrences(of: "\n", with: "") == "B|B|A|A|A|B|A|B|Container")
        let produced = try LiquidTemplate("{% assign v = items | reverse %}{{ v.$descriptor }}", extensionProfile: .closedSystemV1)
        do { _ = try await engine.render(produced, environment: env, registry: registry); Issue.record("New container inherited a descriptor") }
        catch let error as LiquidSystemError { #expect(error == .unavailable(property: .descriptor, state: .notAdmitted)) }
    }

    @Test func systemLookupsChargeTheInvocationValueBudget() async throws {
        let root: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("x")), plain: .qualified("ok")))
        let env = try LiquidSystemEnvironment([.init("v", root)])
        let template = try LiquidTemplate("{{ v.$plain }}{{ v.$plain }}", extensionProfile: .closedSystemV1)
        let registry = try LiquidTemplateRegistry([])
        #expect(try await LiquidEngine(limits: .init(contextValues: 4)).render(template, environment: env, registry: registry) == "okok")
        do { _ = try await LiquidEngine(limits: .init(contextValues: 3)).render(template, environment: env, registry: registry); Issue.record("Lookup budget was not enforced") }
        catch let error as LiquidError { if case .limitExceeded("contextValues") = error { } else { Issue.record("Wrong limit failure: \(error)") } }
    }

    @Test func mapDefaultAndChangedValuesDoNotInventQualification() async throws {
        let descriptor = try LiquidSystemDescriptor([.init("title", .text("Selected"))])
        let selected = LiquidSystemValue.decorated(.init(primary: .ordinary(.string("x")), descriptor: descriptor))
        let record = LiquidSystemValue.decorated(.init(primary: .object([.init("selected", selected)])))
        let missing = LiquidSystemValue.decorated(.init(primary: .ordinary(.null)))
        let env = try LiquidSystemEnvironment([.init("records", .array([record])), .init("fallback", selected), .init("missing", missing)])
        let engine = LiquidEngine(); let registry = try LiquidTemplateRegistry([])
        let source = "{% assign mapped = records | map: 'selected' %}{{ mapped[0].$descriptor.title }}|{% assign choice = missing | default: fallback %}{{ choice.$descriptor.title }}"
        let template = try LiquidTemplate(source, syntaxMode: .strict2, extensionProfile: .closedSystemV1)
        #expect(try await engine.render(template, environment: env, registry: registry) == "Selected|Selected")
        let changed = try LiquidTemplate("{% assign result = fallback | append: '' %}{{ result.$descriptor }}", extensionProfile: .closedSystemV1)
        do { _ = try await engine.render(changed, environment: env, registry: registry); Issue.record("Changed value acquired decoration") }
        catch let error as LiquidSystemError { #expect(error == .unavailable(property: .descriptor, state: .notAdmitted)) }
    }

    @Test func descriptorProjectionChargesElementsAndCancellationDoesNotPoisonReuse() async throws {
        let descriptor = try LiquidSystemDescriptor([.init("type", .typeNames(["one", "two"]))])
        let value: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("x")), descriptor: descriptor))
        let env = try LiquidSystemEnvironment([.init("v", value)])
        let template = try LiquidTemplate("{{ v.$descriptor.type | size }}", extensionProfile: .closedSystemV1)
        let registry = try LiquidTemplateRegistry([])
        #expect(try await LiquidEngine(limits: .init(contextValues: 6)).render(template, environment: env, registry: registry) == "2")
        do { _ = try await LiquidEngine(limits: .init(contextValues: 5)).render(template, environment: env, registry: registry); Issue.record("Descriptor elements escaped the invocation budget") }
        catch let error as LiquidError { if case .limitExceeded("contextValues") = error { } else { Issue.record("Wrong limit failure: \(error)") } }
        let engine = LiquidEngine()
        let cancelled = Task { () throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template, environment: env, registry: registry)
        }
        do { _ = try await cancelled.value; Issue.record("Cancelled rendering succeeded") }
        catch is CancellationError { }
        #expect(try await engine.render(template, environment: env, registry: registry) == "2")
    }

    @Test func ordinaryContainerRenderingNeverExposesDecorations() async throws {
        let env = try environment()
        let template = try LiquidTemplate("{{ article }}|{{ article.items }}", extensionProfile: .closedSystemV1)
        let result = try await LiquidEngine().render(template, environment: env, registry: LiquidTemplateRegistry([]))
        #expect(result == "{\"child\"=>B, \"items\"=>B, \"$descriptor\"=>ordinary-dollar, \"descriptor\"=>ordinary-name}|B")
        #expect(!result.contains("SystemRuntimeValue"))
        #expect(!result.contains("Child"))
        #expect(!result.contains("A &amp; B"))
    }

    @Test func decoratedDynamicIndicesUsePrimaryAndPreserveSelectedChild() async throws {
        let descriptor = try LiquidSystemDescriptor([.init("title", .text("selected"))])
        let child: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("visible")), descriptor: descriptor))
        let index: LiquidSystemValue = .decorated(.init(primary: .ordinary(.integer(0))))
        let key: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("child"))))
        let env = try LiquidSystemEnvironment([.init("items", .array([child])), .init("index", index), .init("key", key), .init("obj", .object([.init("child", child)]))])
        let template = try LiquidTemplate("{{ items[index] }}|{{ items[index].$descriptor.title }}|{{ obj[key].$descriptor.title }}", extensionProfile: .closedSystemV1)
        #expect(try await LiquidEngine().render(template, environment: env, registry: LiquidTemplateRegistry([])) == "visible|selected|selected")
    }

    @Test func decoratedArgumentsAndNullChildrenMatchOrdinarySemantics() async throws {
        let d2: LiquidSystemValue = .decorated(.init(primary: .ordinary(.integer(2))))
        let nilValue: LiquidSystemValue = .decorated(.init(primary: .ordinary(.null)))
        let env = try LiquidSystemEnvironment([.init("d2", d2), .init("p2", .ordinary(.integer(2))), .init("nils", .array([nilValue])), .init("plainNils", .array([.ordinary(.null)]))])
        let template = try LiquidTemplate("{{ 5 | divided_by: p2 }}|{{ 5 | divided_by: d2 }}|{{ plainNils | compact | size }}|{{ nils | compact | size }}", extensionProfile: .closedSystemV1)
        #expect(try await LiquidEngine().render(template, environment: env, registry: LiquidTemplateRegistry([])) == "2|2|0|0")
    }

    @Test func childOperationsUsePrimaryAndRetainSelectedValues() async throws {
        let descriptor = try LiquidSystemDescriptor([.init("title", .text("keep"))])
        let word: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("alpha")), descriptor: descriptor))
        let number: LiquidSystemValue = .decorated(.init(primary: .ordinary(.integer(3))))
        let nested: LiquidSystemValue = .decorated(.init(primary: .array([number])))
        let env = try LiquidSystemEnvironment([.init("words", .array([word])), .init("numbers", .array([nested]))])
        let template = try LiquidTemplate("{% assign found = words | find: 'alp' %}{{ found.$descriptor.title }}|{{ numbers | sum }}", extensionProfile: .closedSystemV1)
        #expect(try await LiquidEngine().render(template, environment: env, registry: LiquidTemplateRegistry([])) == "keep|3")
    }

    @Test func decoratedIntegerArgumentsPreservePrecisionAndOverflow() async throws {
        let large = 9_007_199_254_740_993
        let wrapped: LiquidSystemValue = .decorated(.init(primary: .ordinary(.integer(large))))
        let max: LiquidSystemValue = .decorated(.init(primary: .ordinary(.integer(Int.max))))
        let neg: LiquidSystemValue = .decorated(.init(primary: .ordinary(.integer(-1))))
        let minimum: LiquidSystemValue = .decorated(.init(primary: .ordinary(.integer(Int.min))))
        let env = try LiquidSystemEnvironment([.init("plain", .ordinary(.integer(large))), .init("wrapped", wrapped), .init("max", max), .init("min", minimum), .init("neg", neg)])
        let engine = LiquidEngine(); let registry = try LiquidTemplateRegistry([])
        for filter in ["plus", "minus", "times", "divided_by", "modulo"] {
            let plain = try LiquidTemplate("{{ 1 | \(filter): plain }}", extensionProfile: .closedSystemV1)
            let decorated = try LiquidTemplate("{{ 1 | \(filter): wrapped }}", extensionProfile: .closedSystemV1)
            #expect(try await engine.render(plain, environment: env, registry: registry) == engine.render(decorated, environment: env, registry: registry))
        }
        let precise = try LiquidTemplate("{{ 1 | plus: wrapped }}", extensionProfile: .closedSystemV1)
        #expect(try await engine.render(precise, environment: env, registry: registry) == "9007199254740994")
        for source in ["{{ 1 | plus: max }}", "{{ 0 | minus: min }}", "{{ 2 | times: max }}", "{{ min | divided_by: neg }}"] {
            let overflow = try LiquidTemplate(source, extensionProfile: .closedSystemV1)
            do { _ = try await engine.render(overflow, environment: env, registry: registry); Issue.record("Decorated integer overflow succeeded: \(source)") }
            catch let error as LiquidError { if case .invalidValue = error { } else { Issue.record("Wrong overflow error: \(error)") } }
        }
        let remainder = try LiquidTemplate("{{ min | modulo: neg }}", extensionProfile: .closedSystemV1)
        #expect(try await engine.render(remainder, environment: env, registry: registry) == "0")
    }

    @Test func decoratedPartialNamesAndRenderCollectionsUsePrimaryValues() async throws {
        let descriptor = try LiquidSystemDescriptor([.init("title", .text("selected"))])
        let child: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("visible")), descriptor: descriptor))
        let part: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("p"))))
        let items: LiquidSystemValue = .decorated(.init(primary: .array([child])))
        let env = try LiquidSystemEnvironment([.init("part", part), .init("items", items)])
        let registry = try LiquidTemplateRegistry([.init("p", .raw("X{{ item.$descriptor.title }}"))])
        let render = try LiquidTemplate("{% render 'p' for items as item %}", extensionProfile: .closedSystemV1)
        #expect(try await LiquidEngine().render(render, environment: env, registry: registry) == "Xselected")
        let includeRegistry = try LiquidTemplateRegistry([.init("p", .raw("included"))])
        let include = try LiquidTemplate("{% include part %}", extensionProfile: .closedSystemV1)
        #expect(try await LiquidEngine().render(include, environment: env, registry: includeRegistry) == "included")
        let literalFirst = try LiquidTemplateRegistry([.init("part", .raw("literal")), .init("p", .raw("fallback"))])
        #expect(try await LiquidEngine().render(include, environment: env, registry: literalFirst) == "literal")
        do { _ = try await LiquidEngine().render(include, environment: env, registry: LiquidTemplateRegistry([])); Issue.record("Missing partial succeeded") }
        catch is LiquidError { }
        let cancelled = Task { () throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LiquidEngine().render(render, environment: env, registry: registry)
        }
        do { _ = try await cancelled.value; Issue.record("Cancelled partial render succeeded") }
        catch is CancellationError { }
    }

    @Test func decoratedLoopParametersAndIncludeCollectionsUsePrimaryValues() async throws {
        let descriptor = try LiquidSystemDescriptor([.init("title", .text("selected"))])
        let child: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("value")), descriptor: descriptor))
        let one: LiquidSystemValue = .decorated(.init(primary: .ordinary(.integer(1))))
        let items: LiquidSystemValue = .decorated(.init(primary: .array([child])))
        let env = try LiquidSystemEnvironment([.init("one", one), .init("two", .array([.ordinary(.string("A")), .ordinary(.string("B"))])), .init("items", items)])
        let registry = try LiquidTemplateRegistry([.init("p", .raw("{{ p.$descriptor.title }}"))])
        let source = "{% for x in two limit: one %}{{ x }}{% endfor %}|{% for x in two offset: one %}{{ x }}{% endfor %}|{% include 'p' for items %}"
        let template = try LiquidTemplate(source, extensionProfile: .closedSystemV1)
        #expect(try await LiquidEngine().render(template, environment: env, registry: registry) == "A|B|selected")
        let invalid: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("not-a-number"))))
        let invalidEnv = try LiquidSystemEnvironment([.init("one", invalid), .init("two", .array([.ordinary(.string("A"))]))])
        let invalidTemplate = try LiquidTemplate("{% for x in two limit: one %}{{ x }}{% endfor %}", extensionProfile: .closedSystemV1)
        do { _ = try await LiquidEngine().render(invalidTemplate, environment: invalidEnv, registry: registry); Issue.record("Invalid decorated loop limit succeeded") }
        catch is LiquidError { }
    }

}
