import Foundation
import DictatorCore

/// Developer-only command line mode. Uses the app's own Keychain access, never
/// prints the key, and sends only the synthetic samples defined below.
enum CleanupBenchmark {
    struct Sample: Codable {
        let model: String
        let round: Int
        let input: String
        let output: String?
        let seconds: Double
        let error: String?
    }
    struct Report: Codable {
        let generatedAt: Date
        let samples: [Sample]
    }
    static func run() async throws -> Report {
        guard let key = try Keychain.read() else { throw DictationError.message("Save an API key in Dictator first.") }
        let models = ["gpt-4.1-mini", "gpt-4.1-nano", "gpt-5.4-nano", "gpt-6-luna"]
        let inputs = [
            "I think we should, um, actually no, let's launch on Friday",
            "Schedule it for Monday, sorry, Wednesday at three p m. I might be ten minutes late.",
            "The SwiftUI client calls PostgreSQL through a REST API. We saw a 429 error, not a 401, and we should retry twice, not ten times.",
            "Um can you check whether the invoice is paid? I don't know if it is, so please don't say that it is."
        ]
        let api = OpenAIClient()
        var samples: [Sample] = []
        // Rotate model order and compare the same inputs; no microphone or private text.
        for round in 0..<2 {
            for input in inputs {
                let batch = await withTaskGroup(of: Sample.self, returning: [Sample].self) { group in
                    for model in (round == 0 ? models : models.reversed()) {
                        group.addTask {
                            var options = AIOptions(); options.correctionModel = model
                            options.vocabulary = "SwiftUI, PostgreSQL, REST API"
                            let start = ProcessInfo.processInfo.systemUptime
                            do {
                                let output = try await api.correct(input, key: key, options: options)
                                return Sample(model: model, round: round + 1, input: input, output: output,
                                              seconds: ProcessInfo.processInfo.systemUptime - start, error: nil)
                            } catch {
                                return Sample(model: model, round: round + 1, input: input, output: nil,
                                              seconds: ProcessInfo.processInfo.systemUptime - start,
                                              error: error.localizedDescription)
                            }
                        }
                    }
                    var results: [Sample] = []
                    for await result in group { results.append(result) }
                    return results.sorted { $0.model < $1.model }
                }
                samples.append(contentsOf: batch)
            }
        }
        return Report(generatedAt: Date(), samples: samples)
    }
}
