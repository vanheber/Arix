import Foundation

/// Provedor de LLM usado na sessão.
enum LLMProvider {
    case grok
    case gemini
}

/// Cliente mínimo para APIs no formato chat completion, com suporte
/// primário a Grok (xAI) e secundário a Gemini (Google).
/// A escolha é automática pela chave disponível: Grok > Gemini.
final class LLMClient {

    enum LLMError: LocalizedError {
        case noKey(String)
        case badResponse(String)
        var errorDescription: String? {
            switch self {
            case .noKey(let provider): return "Chave da \(provider) ausente."
            case .badResponse(let message): return message
            }
        }
    }

    private var history: [[String: String]] = []
    private let provider: LLMProvider
    private let apiKey: String
    private let model: String
    private let webSearchEnabled: Bool

    /// Nomes de quem sugeriu as notícias — definidos na janela
    /// "Sugestores de notícias" da menu bar (UserDefaults).
    private var newsSuggesters: [String] {
        let defaults = UserDefaults.standard
        return [defaults.string(forKey: "newsSuggester1"),
                defaults.string(forKey: "newsSuggester2")]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Montado a cada pergunta para incluir a data/hora atual do Mac.
    private var systemPrompt: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEEE, d 'de' MMMM 'de' yyyy, HH:mm"
        let now = formatter.string(from: Date())
        let timezone = TimeZone.current.identifier

        var suggestersRule = ""
        if !newsSuggesters.isEmpty {
            let names = newsSuggesters.joined(separator: " e ")
            suggestersRule = """
            Se perguntarem quem sugeriu a notícia ou as notícias, responda exatamente: \
            "Essas notícias foram sugeridas por \(names) e várias outras pessoas." \

            """
        }

        return suggestersRule + """
        Você é Arix, um assistente de voz rodando no Mac do usuário. \
        Responda sempre em português do Brasil, adequado para ser lido em voz alta. \
        REGRA ESTRITA DE TAMANHO: responda em UMA única frase, com no máximo 40 \
        palavras. Nunca ultrapasse esse limite, mesmo que a pergunta peça detalhes; \
        nesse caso, resuma o essencial em uma frase. \
        Nunca use markdown, listas, símbolos ou emojis. \
        Sua personalidade é agradável e acolhedora, mas você não hesita em soltar \
        um sarcasmo afiado quando a ocasião pede — seja uma pergunta ingênua, um \
        absurdo ou alguém merecendo uma alfinetada bem-humorada. O sarcasmo é seu \
        tempero secreto: usado na medida certa, sem ser gratuito. Furada de \
        nariz sutil, ironia educada, nunca maldade. \
        Primeiro responda o que foi perguntado, com informação correta; em assuntos \
        sérios ou delicados, deixe o sarcasmo de lado. \
        MODO OPINIÃO: se a pergunta começar com "Na sua opinião" (ou variação \
        próxima), NÃO pesquise na web nem dê uma resposta fundamentada ou equilibrada: \
        dê uma opinião puramente cômica. Escolha um lado aleatoriamente, defenda-o com \
        exagero e convicção total, e se couber use um argumento absurdo ou maluco. \
        Continue respeitando o limite de uma frase e 60 palavras. \
        Você tem conhecimento especializado nas seguintes áreas e pode \
        aprofundar quando perguntado: Design e Design Thinking (princípios, \
        metodologias como empatia, definição, ideação, prototipagem e teste, \
        aplicação em inovação e resolução de problemas); Branding (estratégia \
        de marca, identidade visual, posicionamento, branding emocional); \
        Storytelling for Design (narrativa em UX, jornada do cliente, \
        comunicação visual, arquitetura de informação); Literatura de ficção \
        científica e fantasia (obras clássicas e contemporâneas, autores, \
        subgêneros, worldbuilding, análise literária). \
        Data e hora atuais no Mac do usuário: \(now), fuso horário \(timezone). \
        Use essa informação para perguntas sobre data e hora; para a hora em outros \
        lugares, calcule a diferença de fuso a partir dela. \
        Você também tem acesso a busca na web: use-a quando a pergunta envolver \
        fatos atuais (notícias, cotações, clima, esportes). Não cite URLs em voz alta.
        """
    }

    init() {
        let env = ProcessInfo.processInfo.environment

        // Grok é primário; Gemini é fallback.
        if let key = Config.grokKey, !key.isEmpty {
            provider = .grok
            apiKey = key
            model = env["ARIX_MODEL"] ?? "grok-2-1212"
        } else if let key = Config.geminiKey, !key.isEmpty {
            provider = .gemini
            apiKey = key
            model = env["ARIX_MODEL"] ?? "gemini-1.5-flash"
        } else {
            provider = .grok
            apiKey = ""
            model = env["ARIX_MODEL"] ?? "grok-2-1212"
            print("⚠️ Chave de API ausente: defina GROK_API_KEY ou GEMINI_API_KEY no config.json.")
        }

        webSearchEnabled = env["ARIX_WEB_SEARCH"] != "0"
        if webSearchEnabled {
            print("🌐 Busca na web habilitada (desative com ARIX_WEB_SEARCH=0).")
        }
    }

    func ask(_ question: String, completion: @escaping (Result<String, Error>) -> Void) {
        history.append(["role": "user", "content": question])
        if history.count > 20 {
            history.removeFirst(history.count - 20)
        }

        guard !apiKey.isEmpty else {
            completion(.failure(LLMError.noKey(provider == .grok ? "GROK" : "GEMINI")))
            return
        }

        switch provider {
        case .grok:
            sendGrok(question: question, completion: completion)
        case .gemini:
            sendGemini(question: question, completion: completion)
        }
    }

    // MARK: - Grok (xAI)

    private func sendGrok(question: String, completion: @escaping (Result<String, Error>) -> Void) {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1000,
            "messages": [
                ["role": "system", "content": systemPrompt]
            ] + history
        ]

        var req = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            self?.handleOpenAIResponse(data: data, error: error, completion: completion)
        }.resume()
    }

    // MARK: - Gemini (Google)

    private func sendGemini(question: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Gemini usa um formato diferente: contents[] > parts[] > text.
        // Converte o histórico para o formato Gemini.
        let geminiContents: [[String: Any]] = history.map { msg in
            let role = msg["role"] == "assistant" ? "model" : "user"
            return [
                "role": role,
                "parts": [["text": msg["content"] ?? ""]]
            ]
        }

        var body: [String: Any] = [
            "contents": geminiContents,
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ]
        ]
        if webSearchEnabled {
            body["tools"] = [["googleSearch": [:]]]
        }

        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(LLMError.badResponse("Resposta inválida da API Gemini.")))
                return
            }
            if let apiError = json["error"] as? [String: Any],
               let message = apiError["message"] as? String {
                completion(.failure(LLMError.badResponse(message)))
                return
            }
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.compactMap({ $0["text"] as? String }).first else {
                completion(.failure(LLMError.badResponse("Formato inesperado na resposta do Gemini.")))
                return
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.history.append(["role": "assistant", "content": trimmed])
            completion(.success(trimmed))
        }.resume()
    }

    // MARK: - Resposta OpenAI-compatible (Grok, etc.)

    private func handleOpenAIResponse(data: Data?, error: Error?, completion: @escaping (Result<String, Error>) -> Void) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            completion(.failure(LLMError.badResponse("Resposta inválida da API.")))
            return
        }
        if let apiError = json["error"] as? [String: Any],
           let message = apiError["message"] as? String {
            completion(.failure(LLMError.badResponse(message)))
            return
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else {
            completion(.failure(LLMError.badResponse("Formato inesperado na resposta da API.")))
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(LLMError.badResponse("A API não retornou texto.")))
            return
        }
        history.append(["role": "assistant", "content": trimmed])
        completion(.success(trimmed))
    }
}
