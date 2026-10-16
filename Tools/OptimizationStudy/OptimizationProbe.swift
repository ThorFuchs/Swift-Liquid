// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation
import Liquid
private struct Workload: Decodable, Sendable {
 let name: String, template: String, context: [String: String], expected: String
}
private struct Configuration: Decodable, Sendable { let workloads: [Workload] }
private struct Failure: Error { let message: String }
@main struct OptimizationProbe {
 nonisolated private static func cpu() throws -> Double {
  var u = rusage(); guard getrusage(RUSAGE_SELF, &u) == 0 else { throw Failure(message: "getrusage") }
  return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) * 1e9 + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) * 1000
 }
 @MainActor private static func actor(_ config: Configuration, order: String, only: Bool) async throws -> Data {

  try Task.checkCancellation()
  let engine = LiquidEngine(referenceTime: Date(timeIntervalSince1970: 1_007_044_400)), clock = ContinuousClock()
  var records: [[String: Any]] = []
  var plans: [(Workload, Bool)] = config.workloads.flatMap { [($0, false), ($0, true)] }
  if order == "reverse" { plans.reverse() }
  for (input, reused) in plans {
   let template = try LiquidTemplate(input.template)
   let context = LiquidObject(input.context.keys.sorted().map { LiquidObject.Entry($0, .string(input.context[$0]!)) })
   var hash: UInt64 = 14695981039346656037
   var wall: [Double] = [], utilization: [Double] = []
   let repetitions = only ? 1 : 100
   for sample in (only ? 0 : -10)..<(only ? 1 : 25) {
    try Task.checkCancellation()
    let beforeCPU = try cpu(), before = clock.now
    for _ in 0..<repetitions {
     let output = try await reused ? engine.render(template, context: context) : engine.render(template: input.template, context: context)
     guard output.utf8.elementsEqual(input.expected.utf8) else { throw Failure(message: "Output mismatch: \(input.name): \(output)") }
     for b in output.utf8 { hash = (hash ^ UInt64(b)) &* 1099511628211 }
    }
    let elapsed = before.duration(to: clock.now).components, deltaCPU = try cpu() - beforeCPU
    if sample >= 0 { wall.append((Double(elapsed.seconds) * 1e9 + Double(elapsed.attoseconds) / 1e9) / Double(repetitions)); utilization.append(deltaCPU / Double(repetitions)) }
   }
   var record: [String: Any] = ["name": input.name, "mode": reused ? "reused" : "source", "outputBytes": input.expected.utf8.count, "fnv1aChecksum": String(hash, radix: 16)]
   if only { record["validated"] = true }
   else {
    record["samples"] = 25; record["warmupSamples"] = 10; record["repetitionsPerSample"] = repetitions
    for (c, times) in [("wall", wall), ("cpu", utilization)] { let s = times.sorted();guard s.count == 25 && s[12] > 0 else { throw Failure(message: "Samples") };record[c+"SampleNanoseconds"] = times;record[c+"MedianNanoseconds"] = s[12];record[c+"P95Nanoseconds"] = s[23] }
    record["cpuZeroSamples"] = utilization.filter { $0 == 0 }.count
   }
   records.append(record)
  }
  try Task.checkCancellation()
  return try JSONSerialization.data(withJSONObject: ["configuration": "release", "caller": "actor", "recordOrder": order, "kind": only ? "validation" : "measurement", "records": records], options: [.prettyPrinted, .sortedKeys])
 }
 @concurrent private static func concurrent(_ config: Configuration, order: String, only: Bool) async throws -> Data {

  try Task.checkCancellation()
  let engine = LiquidEngine(referenceTime: Date(timeIntervalSince1970: 1_007_044_400)), clock = ContinuousClock()
  var records: [[String: Any]] = []
  var plans: [(Workload, Bool)] = config.workloads.flatMap { [($0, false), ($0, true)] }
  if order == "reverse" { plans.reverse() }
  for (input, reused) in plans {
   let template = try LiquidTemplate(input.template)
   let context = LiquidObject(input.context.keys.sorted().map { LiquidObject.Entry($0, .string(input.context[$0]!)) })
   var hash: UInt64 = 14695981039346656037
   var wall: [Double] = [], utilization: [Double] = []
   let repetitions = only ? 1 : 100
   for sample in (only ? 0 : -10)..<(only ? 1 : 25) {
    try Task.checkCancellation()
    let beforeCPU = try cpu(), before = clock.now
    for _ in 0..<repetitions {
     let output = try await reused ? engine.render(template, context: context) : engine.render(template: input.template, context: context)
     guard output.utf8.elementsEqual(input.expected.utf8) else { throw Failure(message: "Output mismatch: \(input.name): \(output)") }
     for b in output.utf8 { hash = (hash ^ UInt64(b)) &* 1099511628211 }
    }
    let elapsed = before.duration(to: clock.now).components, deltaCPU = try cpu() - beforeCPU
    if sample >= 0 { wall.append((Double(elapsed.seconds) * 1e9 + Double(elapsed.attoseconds) / 1e9) / Double(repetitions)); utilization.append(deltaCPU / Double(repetitions)) }
   }
   var record: [String: Any] = ["name": input.name, "mode": reused ? "reused" : "source", "outputBytes": input.expected.utf8.count, "fnv1aChecksum": String(hash, radix: 16)]
   if only { record["validated"] = true }
   else {
    record["samples"] = 25; record["warmupSamples"] = 10; record["repetitionsPerSample"] = repetitions
    for (c, times) in [("wall", wall), ("cpu", utilization)] { let s = times.sorted();guard s.count == 25 && s[12] > 0 else { throw Failure(message: "Samples") };record[c+"SampleNanoseconds"] = times;record[c+"MedianNanoseconds"] = s[12];record[c+"P95Nanoseconds"] = s[23] }
    record["cpuZeroSamples"] = utilization.filter { $0 == 0 }.count
   }
   records.append(record)
  }
  try Task.checkCancellation()
  return try JSONSerialization.data(withJSONObject: ["configuration": "release", "caller": "concurrent", "recordOrder": order, "kind": only ? "validation" : "measurement", "records": records], options: [.prettyPrinted, .sortedKeys])
 }
 static func main() async throws {
  #if DEBUG
  throw Failure(message: "Release required")
  #else
  guard [5, 6].contains(CommandLine.arguments.count) else { throw Failure(message: "OUTPUT CALLER INPUTS ORDER [--validate-only]") }
  let caller = CommandLine.arguments[2], order = CommandLine.arguments[4], only = CommandLine.arguments.count == 6
  guard ["actor", "concurrent"].contains(caller), ["forward", "reverse"].contains(order), !only || CommandLine.arguments[5] == "--validate-only" else { throw Failure(message: "Arguments") }
  let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
  let data = try await caller == "actor" ? actor(config, order: order, only: only) : concurrent(config, order: order, only: only)
  try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
  print("Completed public optimization probe: \(caller), \(order), validation=\(only)")
  #endif
 }
}
