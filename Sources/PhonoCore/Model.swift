import Foundation

/// Where the Phonon-2 Core ML model lives and how to tell it is complete.
///
/// `Scripts/download-model.sh` puts the files there. Phono never downloads
/// anything itself.
public enum Model {
    /// Audio the model expects: mono, 16 kHz.
    public static let sampleRate = 16_000.0

    public static func directory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Phono/Phonon-2-CoreML", isDirectory: true)
    }

    /// The files the runner reads. Keep in step with Scripts/download-model.sh.
    public static let files = [
        "manifest.json",
        "decoder.bin",
        "Phonon-2.mlpackage/Manifest.json",
        "Phonon-2.mlpackage/Data/com.apple.CoreML/model.mlmodel",
        "Phonon-2.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
    ]

    public static func isInstalled(
        at directory: URL,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        files.allSatisfy { exists(directory.appendingPathComponent($0).path) }
    }

    public static func duration(sampleCount: Int) -> Double {
        Double(sampleCount) / sampleRate
    }
}
