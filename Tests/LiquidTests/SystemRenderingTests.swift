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

}
