# Arix — assistente de voz local para macOS

Assistente de voz nativo para macOS (Apple Silicon M4). Escuta o microfone continuamente; ao ouvir **"Arix"**, captura a pergunta, transcreve localmente, envia para Grok (xAI) ou Gemini (Google) via API e fala a resposta com lip sync animado.

## Privacidade

- Wake word e transcrição: **Speech framework da Apple, on-device** (nenhum áudio sai do Mac, se o idioma pt-BR estiver baixado).
- Voz: **ElevenLabs** (voz neural) ou **AVSpeechSynthesizer** local como fallback.
- Único tráfego de rede: o **texto** da pergunta para a API de LLM escolhida (Grok ou Gemini).

## Requisitos

- macOS 13+ (Apple Silicon M4 recomendado), Command Line Tools instalados.
- Chave de API do Grok (https://console.x.ai) ou Gemini (https://aistudio.google.com).
- Para transcrição 100% local: em **Ajustes do Sistema > Teclado > Ditado**, ative o ditado e baixe o idioma Português (Brasil).

## Como rodar

1. Copie `config.example.json` para `config.json` e preencha as chaves:

```json
{
  "grok_api_key": "xai-...",
  "gemini_api_key": "...",
  "arix_elevenlabs_api_key": "..."
}
```

2. Compile e rode:

```bash
swift run -c release
```

3. Ou monte o aplicativo de verdade (menu bar, sem terminal):

```bash
./make_app.sh                               # gera Arix.app
mkdir -p ~/.config/arix && cp config.json ~/.config/arix/
mv Arix.app /Applications/                  # opcional
```

O app vive na **menu bar** (sem ícone no Dock). O `config.json` é lido de `~/.config/arix/`. Variáveis de ambiente `GROK_API_KEY`/`GEMINI_API_KEY`/`ARIX_ELEVENLABS_API_KEY` são fallback.

## Uso

1. Aguarde `👂 Aguardando "arix"...`
2. Diga: **"Arix, que horas são em Tóquio?"**
3. Ele transcreve, consulta o LLM e responde em voz alta com lip sync.

## Configuração

| Variável | Padrão | Descrição |
|---|---|---|
| `ARIX_MODEL` | `grok-2-1212` ou `gemini-1.5-flash` | modelo da API |
| `ARIX_VOICE` | melhor voz masculina pt-BR | nome da voz do sistema |
| `ARIX_ELEVENLABS_VOICE_ID` | `f016iUUEKqhX0trYHH6Q` | voz da ElevenLabs |
| `ARIX_ELEVENLABS_MODEL` | `eleven_multilingual_v2` | modelo ElevenLabs |
| `ARIX_WEB_SEARCH` | `1` | `0` desativa a busca na web |
| `ARIX_WAKE_WORD` | `arix` | wake word (sem recompilar) |
| `ARIX_RIVE_INPUT` | `mouth` | input numérico do state machine Rive |
| `ARIX_RIVE_STATE_MACHINE` | `State Machine 1` | state machine do Rive |

### Avatar na tela

Salve `avatar.png` na raiz do projeto (ou `~/.config/arix/avatar.png`) — PNG com fundo transparente. O avatar aparece com fade no canto inferior direito ao detectar a wake word.

**Design dos assets:** Revestimento estrutural em Nankin Gray, contornos metálicos em Antique Bronze, e núcleo de emissão/lip-sync (visemas) em Deep Monarch Blue. Fundo estritamente transparente.

**Boca animada (lip sync):** Com ElevenLabs, usa timestamps de caracteres para visemas sincronizados. Sprites opcionais: `avatar_mid.png`, `avatar_open.png`, `avatar_round.png`, `avatar_fv.png`. Alternativamente, um rig Rive (`avatar.riv`) substitui os PNGs.

### LLM: Grok (xAI) e Gemini (Google)

O provedor é escolhido automaticamente: se `GROK_API_KEY` estiver definida, usa Grok (endpoint `https://api.x.ai/v1/chat/completions`); senão, se `GEMINI_API_KEY` estiver definida, usa Gemini (endpoint `https://generativelanguage.googleapis.com`). O histórico da conversa é mantido durante a sessão (máx. 20 mensagens).

### Busca na web

Controlada por `ARIX_WEB_SEARCH=0`. Quando habilitada, o LLM pode pesquisar informações atuais. O suporte varia por provedor.

### Voz ElevenLabs

Com `ARIX_ELEVENLABS_API_KEY` definida, a resposta é sintetizada na ElevenLabs (voz neural). Fallback para voz do sistema em caso de falha.

## Arquitetura

```
ArixApp.swift            → entrada (SwiftUI @main), menu bar
VoiceAssistant.swift     → máquina de estados (aguardando → capturando → pensando → falando)
SpeechRecognizer.swift   → AVAudioEngine + SFSpeechRecognizer (pt-BR, on-device)
LLMClient.swift          → API Grok ou Gemini, com histórico
Speaker.swift            → AVSpeechSynthesizer (voz pt-BR)
ElevenLabsSpeaker.swift  → API ElevenLabs com visemas por timestamps
AvatarWindow.swift       → janela flutuante com avatar (Rive ou sprites PNG)
AssistantController.swift→ ponte VoiceAssistant → SwiftUI
Config.swift             → carregamento de chaves (config.json + env vars)
```

## Análise Crítica e Roadmap de Evolução (Arix)

Este projeto foi refatorado para operar na arquitetura Apple Silicon (M4), utilizando chamadas nativas de sistema para transcrição on-device e integração com Grok/Gemini.

**Limitações Atuais e Soluções Planejadas:**
1. **Gargalo de Latência:** O sistema aguarda o payload completo da API. O roadmap inclui implementar streaming de resposta (chunking), iniciando a síntese de áudio assim que a primeira sentença completa for recebida.
2. **Wake Word Ineficiente:** O `SFSpeechRecognizer` exige reset a cada 45s e sofre em ambientes ruidosos. O próximo passo é integrar um motor CoreML ou Porcupine apenas para a detecção de "Arix", acionando o ditado contínuo somente após o trigger.
3. **UI Responsivo:** Transição do atual lip-sync por PNG estático para um State Machine completo no Rive, gerenciando status (idle, listening, thinking, speaking) com pulsações dinâmicas.
