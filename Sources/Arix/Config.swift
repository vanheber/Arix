import Foundation

/// Chaves de API carregadas de um arquivo de configuração, para não irem
/// em commits (config.json está no .gitignore).
///
/// Ordem de busca do arquivo:
///   1. config.json no diretório atual (raiz do projeto)
///   2. ~/.config/arix/config.json
///
/// Variáveis de ambiente ainda funcionam como fallback se o arquivo
/// não existir ou o campo estiver vazio.
struct Config: Decodable {
    var grokApiKey: String?
    var geminiApiKey: String?
    var arixElevenlabsApiKey: String?

    enum CodingKeys: String, CodingKey {
        case grokApiKey = "grok_api_key"
        case geminiApiKey = "gemini_api_key"
        case arixElevenlabsApiKey = "arix_elevenlabs_api_key"
    }

    static let shared = load()

    static var grokKey: String? {
        resolve(shared.grokApiKey, envVar: "GROK_API_KEY")
    }

    static var geminiKey: String? {
        resolve(shared.geminiApiKey, envVar: "GEMINI_API_KEY")
    }

    static var elevenLabsKey: String? {
        resolve(shared.arixElevenlabsApiKey, envVar: "ARIX_ELEVENLABS_API_KEY")
    }

    private static func resolve(_ fileValue: String?, envVar: String) -> String? {
        if let fileValue, !fileValue.isEmpty {
            return fileValue
        }
        if let envValue = ProcessInfo.processInfo.environment[envVar], !envValue.isEmpty {
            return envValue
        }
        return nil
    }

    private static func load() -> Config {
        let fm = FileManager.default
        let candidates = [
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("config.json"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/arix/config.json")
        ]
        for url in candidates where fm.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let config = try JSONDecoder().decode(Config.self, from: data)
                print("🔑 Configuração carregada de \(url.path)")
                return config
            } catch {
                print("⚠️ Não consegui ler \(url.path): \(error.localizedDescription)")
            }
        }
        return Config(grokApiKey: nil, geminiApiKey: nil, arixElevenlabsApiKey: nil)
    }
}
