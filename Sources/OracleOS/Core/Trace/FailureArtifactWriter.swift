import Foundation

@MainActor
public enum FailureArtifactWriter {
    public static func capture(
        appName: String?,
        actionName: String,
        pre: Observation,
        post: Observation,
        recorder: TraceRecorder = .shared
    ) -> TraceArtifactReferences? {
        let artifactsDir = recorder.store.artifactsDirectory()
        let stem = "\(timestampStem())-\(sanitize(actionName))"

        let prePath = writeObservation(pre, to: artifactsDir.appendingPathComponent("\(stem)-pre.json"))
        let postPath = writeObservation(post, to: artifactsDir.appendingPathComponent("\(stem)-post.json"))
        let screenshotPath = writeScreenshot(appName: appName, to: artifactsDir.appendingPathComponent("\(stem).png"))

        if prePath == nil, postPath == nil, screenshotPath == nil {
            return nil
        }

        return TraceArtifactReferences(
            screenshotPath: screenshotPath,
            preObservationPath: prePath,
            postObservationPath: postPath
        )
    }

    private static func writeObservation(_ observation: Observation, to url: URL) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(observation) else { return nil }
        do {
            try data.write(to: url)
            return url.path
        } catch {
            Log.warn("Failed to write observation artifact: \(error)")
            return nil
        }
    }

    private static func writeScreenshot(appName: String?, to url: URL) -> String? {
        let result = Perception.screenshot(appName: appName, fullResolution: false)
        guard result.success,
              let data = result.data,
              let base64 = data["image"] as? String,
              let png = Data(base64Encoded: base64)
        else {
            return nil
        }

        do {
            try png.write(to: url)
            return url.path
        } catch {
            Log.warn("Failed to write screenshot artifact: \(error)")
            return nil
        }
    }

    private static func timestampStem() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }.reduce(into: "") { result, character in
            result.append(character)
        }
    }
}
