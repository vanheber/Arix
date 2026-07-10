# Roadmap: Substituição do ElevenLabs TTS

## Motivação

O ElevenLabs oferece qualidade de voz superior, mas com custo 3-6x maior que os concorrentes (US$ 50-100/1M chars contra US$ 16/1M de Azure e Polly). Além disso, o suporte a visemas no ElevenLabs exige parsing manual do alinhamento caractere a caractere, enquanto Azure e Polly expõem visemas nativamente via SSML.

## Prioridade 1: Microsoft Azure TTS

### Por quê

- **Visemes nativos via SSML:** o endpoint retorna IDs de visema (0-21) que mapeiam diretamente para os níveis de boca 0-4 do `AvatarWindow`, sem necessidade de tabela de mapeamento caractere → visema
- **pt-BR feminina:** "Francisca" (Neural) — qualidade próxima ao ElevenLabs
- **Custo:** US$ 16/1M chars (~US$ 14,11 efetivo com faturamento por hora), free tier de 500K chars/mês (perpétuo)
- **Latência:** time-to-first-audio ~150ms (streaming)
- **500+ vozes, 140+ idiomas**

### Plano de implementação

1. **Criar `AzureSpeaker.swift`** — novo arquivo no `Sources/Arix/`, conformando ao protocolo `Speaking`
   - Usar a API REST do Azure Speech (`/cognitiveservices/v1`) com SSML
   - Incluir o elemento `<viseme>` no SSML para receber os IDs de visema no áudio de resposta
   - O retorno do Azure vem no formato `application/stream+json`, com eventos `Viseme` contendo `visemeId` + `audioOffset`
   - Alternativa: usar o SDK `Azure-Speech` via SPM (mais simples, mas adiciona dependência)

2. **Configuração de credenciais**
   - Adicionar ao `config.json`: `"azure_speech_key"` e `"azure_speech_region"`
   - Adicionar ao `Config.swift`: `static var azureSpeechKey` e `static var azureSpeechRegion`
   - Env vars: `AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION`

3. **Atualizar `VoiceAssistant.swift`** — adicionar Azure como alternativa na escolha do speaker:
   ```
   Se ARIX_ELEVENLABS_API_KEY → ElevenLabsSpeaker
   Senão, se AZURE_SPEECH_KEY → AzureSpeaker
   Senão → Speaker (voz do sistema)
   ```

### API Azure — formato SSML com viseme

```xml
<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis"
       xmlns:mstts="http://www.w3.org/2001/mstts" xml:lang="pt-BR">
  <voice name="pt-BR-FranciscaNeural">
    <mstts:viseme type="redlips_front" />
    <prosody rate="default" pitch="default">Texto a ser falado</prosody>
  </voice>
</speak>
```

### Resposta — parsing de visemes

O Azure retorna eventos no formato:
```
{"type":"Viseme","visemeId":1,"offset":3200000}
```

Mapeamento `visemeId` (0-21) → nível de boca Arix (0-4):

| visemeId | Descrição | Nível |
|---|---|---|
| 0 | Silêncio / pausa | 0 |
| 1 | ae, ax, ah | 2 |
| 2 | aa | 2 |
| 3 | ao | 3 |
| 4 | ey, eh, uh | 1 |
| 5 | er | 1 |
| 6 | y, iy, ih, ix | 1 |
| 7 | w, uw | 3 |
| 8 | ow | 3 |
| 9 | aw | 3 |
| 10 | oy | 1 |
| 11 | ay | 2 |
| 12 | h | 1 |
| 13 | r | 1 |
| 14 | l | 1 |
| 15 | s, z | 1 |
| 16 | sh, ch, jh, zh | 1 |
| 17 | th, dh | 1 |
| 18 | f, v | 4 |
| 19 | d, t, n | 0 |
| 20 | k, g, ng | 0 |
| 21 | p, b, m | 0 |

Isso elimina a necessidade da função `viseme(for:)` e do parsing de caracteres do `ElevenLabsSpeaker.swift`.

---

## Prioridade 2: Amazon Polly

### Por quê

- **Visemes nativos:** Polly suporta `SpeechMark` do tipo `viseme` via parâmetro `SpeechMarkTypes=["viseme"]`
- **Custo:** US$ 16/1M chars (Neural) — idêntico ao Azure, mas sem free tier perpétuo (expira em 12 meses)
- **pt-BR feminina:** Camila (Neural) e Vitória (Neural)
- **Integração AWS:** perfeito se o ecossistema já usar AWS

### Plano de implementação

1. **Criar `PollySpeaker.swift`** — conformando ao protocolo `Speaking`
   - Usar AWS SDK via SPM (`aws-sdk-swift`) ou chamada REST direta via `SynthesizeSpeechCommand`
   - Habilitar `SpeechMarkTypes=["viseme"]`
   - O retorno é um stream JSON onde cada linha contém o tipo, timestamp e valor do viseme
   - Montar timeline de visemas similar ao que o `ElevenLabsSpeaker.swift` já faz com `MouthEvent`

2. **Configuração de credenciais**
   - Adicionar ao `config.json`: `"aws_access_key_id"`, `"aws_secret_access_key"`, `"aws_region"`
   - Env vars: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`
   - (Ou usar credenciais da cadeia padrão AWS se o SDK for usado)

3. **Hierarquia de fallback final**
   ```
   Se ARIX_ELEVENLABS_API_KEY → ElevenLabsSpeaker
   Senão, se AZURE_SPEECH_KEY → AzureSpeaker
   Senão, se AWS credenciais → PollySpeaker
   Senão → Speaker (voz do sistema)
   ```

### API Polly — exemplo de resposta viseme

```
{"time":0,"type":"viseme","value":"0"}
{"time":120,"type":"viseme","value":"21"}
{"time":200,"type":"viseme","value":"1"}
```

O `value` é um número 0-21 compatível com a tabela de visemes do Azure, permitindo reusar o mesmo mapeamento → nível de boca.

---

## Comparação final: qualidade vs custo

| Provedor | Custo/1M chars | Free Tier | Qualidade | Visemes | pt-BR |
|---|---|---|---|---|---|
| ElevenLabs v3 | $100 | 10K/mês | ⭐⭐⭐⭐⭐ | caractere | multilíngue |
| ElevenLabs Flash | $50 | 10K/mês | ⭐⭐⭐⭐ | caractere | multilíngue |
| **Azure Neural** | **$16** | **500K/mês** | ⭐⭐⭐⭐ | **nativo SSML** | Francisca |
| **Polly Neural** | **$16** | 1M/mês (12m) | ⭐⭐⭐½ | **nativo** | Camila/Vitória |
| Voz do sistema | $0 | ∞ | ⭐⭐ | palavra | Luciana |

A substituição é **incremental**: o AzureSpeaker pode coexistir com o ElevenLabsSpeaker, e a escolha do provedor é feita em tempo de execução pela chave disponível, sem impacto no resto do sistema.
