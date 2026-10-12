import Foundation

/// Finds the `fermion` command-line engine and says how to start it.
///
/// Phono does not run the model in-process. It starts `fermion serve
/// phonon-2` once, keeps it warm, and sends each dictation to it over
/// loopback. The first load takes 10–40 s; after that a sentence decodes in
/// well under a second.
public enum Engine {
    /// The model Phono asks the engine to serve.
    public static let model = "phonon-2"

    /// Where `Scripts/setup-engine.sh` puts its Python venv.
    public static func defaultDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Phono/engine", isDirectory: true)
    }

    /// Where the engine's stdout and stderr go.
    public static func logFile(home: URL) -> URL {
        home.appendingPathComponent("Library/Logs/Phono/engine.log")
    }

    /// Paths to try for the `fermion` binary, in order. An explicit override
    /// wins; then the venv the setup script makes; then common install spots.
    public static func candidates(home: URL, override: String?) -> [String] {
        var paths: [String] = []
        if let override, !override.isEmpty {
            paths.append((override as NSString).expandingTildeInPath)
        }
        paths.append(defaultDirectory(home: home).appendingPathComponent(".venv/bin/fermion").path)
        paths.append(home.appendingPathComponent(".local/bin/fermion").path)
        paths.append("/opt/homebrew/bin/fermion")
        paths.append("/usr/local/bin/fermion")
        return paths
    }

    public static func locate(
        home: URL,
        override: String?,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        candidates(home: home, override: override).first(where: isExecutable)
    }

    /// Arguments for `fermion`. Bound to 127.0.0.1 so nothing off this Mac can
    /// reach it.
    public static func serveArguments(port: Int) -> [String] {
        ["serve", model, "--host", "127.0.0.1", "--port", String(port)]
    }
}
