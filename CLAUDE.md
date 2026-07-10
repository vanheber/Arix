# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## O que é

Arix é um assistente de voz para macOS (Apple Silicon M4, Swift Package). Fluxo: escuta contínua do microfone → wake word "Arix" → transcrição local (pt-BR) → pergunta à API do Grok (xAI) ou Gemini (Google) → resposta falada (ElevenLabs ou voz do sistema) com avatar animado na tela e lip sync por visemas.

## Comandos

```bash
swift build            # compila
swift run -c release   # roda em modo desenvolvimento (app de menu bar)
./make_app.sh          # monta o Arix.app (bundle com Info.plist, recursos e assinatura ad-hoc)
```

Não há testes nem linter configurados. O app só roda de fato em macOS (frameworks Speech/AVFoundation/AppKit) e requer permissões de Microfone e Reconhecimento de Fala concedidas ao terminal na primeira execução.

## Configuração em runtime

- `config.json` na raiz (gitignored; modelo em `config.example.json`) ou `~/.config/arix/config.json`: chaves `grok_api_key`, `gemini_api_key`, `arix_elevenlabs_api_key`. Carregado por `Config.swift`; variáveis de ambiente `GROK_API_KEY`/`GEMINI_API_KEY`/`ARIX_ELEVENLABS_API_KEY` são fallback.
- Env vars opcionais: `ARIX_MODEL`, `ARIX_WAKE_WORD`, `ARIX_WEB_SEARCH=0`, `ARIX_VOICE`, `ARIX_ELEVENLABS_VOICE_ID`, `ARIX_ELEVENLABS_MODEL`, `ARIX_RIVE_INPUT`, `ARIX_RIVE_STATE_MACHINE`.
- Imagens carregadas em runtime da raiz do projeto (ou `~/.config/arix/`): `avatar.png` (obrigatória para exibir o avatar) e sprites de boca opcionais `avatar_mid.png`, `avatar_open.png`, `avatar_round.png`, `avatar_fv.png`.

## Arquitetura (Sources/Arix/)

O centro é a máquina de estados em `VoiceAssistant.swift`: `waitingWakeWord → capturingQuestion → thinking → speaking → waitingWakeWord`. Tudo converge para ela; os demais arquivos são satélites plugados por closures.

- `ArixApp.swift` — entrada do app (SwiftUI `@main`): `MenuBarExtra` cujo ícone reflete o estado, menu (pausar/retomar, sugestores, sair) e a janela dos sugestores de notícias (`@AppStorage` → UserDefaults, lidos pelo `LLMClient` a cada pergunta). `AppDelegate` define `.accessory` (sem Dock) e inicia o assistente.
- `AssistantController.swift` — `ObservableObject` singleton que faz a ponte VoiceAssistant → SwiftUI (`AssistantStatus` com símbolo e rótulo por estado; `pause()`/`resume()`).
- `SpeechRecognizer.swift` — AVAudioEngine + SFSpeechRecognizer pt-BR (on-device quando disponível). Emite transcrições parciais via `onPartial`. Detalhes críticos: sessões do SFSpeechRecognizer expiram em ~1 min, então `VoiceAssistant` reinicia a escuta a cada 45s (watchdog) e após erros; um contador `generation` invalida callbacks de sessões antigas; a wake word é injetada em `contextualStrings` para favorecer o reconhecimento.
- Detecção de fim de pergunta: por silêncio — timer rearmado a cada transcrição parcial *alterada* (1,8s com pergunta; 6s sem). A pergunta é o texto após a última ocorrência da wake word no transcript.
- `LLMClient.swift` — API Grok (xAI) como primário, Gemini (Google) como fallback. Suporta histórico (máx. 20 mensagens). O system prompt é recomputado a cada chamada para injetar data/hora locais e inclui: persona bem-humorada, limite estrito de 1 frase, "modo opinião" e sugestores de notícias.
- `Speaker.swift` — define o protocolo `Speaking` (speak + callback `onMouthLevel`) e a implementação com AVSpeechSynthesizer (escolhe a melhor voz pt-BR masculina instalada). Boca animada por evento de palavra (`willSpeakRangeOfSpeechString`).
- `ElevenLabsSpeaker.swift` — TTS principal. Usa o endpoint `with-timestamps` (JSON com `audio_base64` + alignment por caractere) e constrói uma timeline de visemas (mapa caractere→nível de boca 0-4); um timer 60fps segue `player.currentTime`. Degradação em camadas: sem alignment → medição de amplitude (`averagePower`); falha da API → fallback para `Speaker` (voz do sistema).
- `AvatarWindow.swift` — janela borderless/transparente/flutuante no canto inferior direito, que ignora cliques. Dois renderizadores, decididos na inicialização: rig Rive (`avatar.riv`, boca via input numérico "mouth" 0-4 do state machine "State Machine 1"; RiveRuntime via SPM) ou sprites PNG. Entrada animada: a *janela fica fixa* e a view (Rive ou NSImageView) sobe dentro de um container com `masksToBounds`. Design: Nankin Gray (estrutura), Antique Bronze (contornos), Deep Monarch Blue (emissão/lip-sync). `setMouth(_:)` envia ao Rive ou troca sprites com cadeias de fallback por nível.
- A escuta é **pausada durante a fala** (para o assistente não se ouvir) e retomada no completion do `speak`.

## Convenções

- Idioma do código/comentários/mensagens de terminal: português brasileiro.
- Concorrência por GCD/closures (`DispatchQueue.main`) — não migrar para async/await sem pedido explícito.
- Um único alvo executável; única dependência externa: RiveRuntime (rig do avatar). Rede via URLSession + JSONSerialization.
