# Spec: AgentBar

> Status: revisado com as decisões de 29/10/2026
> Fontes de dados verificadas nesta máquina com Claude Code 2.1.312.

## Pressupostos

1. App nativo de macOS que vive só na barra de menus: sem ícone no Dock e sem janela principal.
2. Os dados vêm só de arquivos que o Claude Code grava no próprio Mac. O app não faz chamadas de rede e não lê o token de login no Keychain.
3. A porcentagem vem do status line do Claude Code (campo `rate_limits`), que é o jeito documentado de receber esses números. Por isso ela só atualiza enquanto alguma sessão do Claude Code está aberta.
4. "Agentes em workflow" são os Dynamic Workflows (ferramenta Workflow). Subagentes avulsos (ferramenta Agent) ficam para uma versão futura.
5. Somente leitura: o app mostra os workflows, mas não para nem pausa.
6. macOS 14 (Sonoma) ou mais novo.
7. Interface em português e inglês.
8. Distribuição direta (GitHub Releases), fora da Mac App Store e, por enquanto, sem assinatura da Apple.

## Decisões

| Tema | Decisão |
|---|---|
| Nome | AgentBar |
| Conta Apple Developer | Não por enquanto. O app sai com assinatura ad-hoc, e a notarização entra quando houver conta. |
| Barra de menus | 5h e 7d empilhados, no estilo do CPU/MEM |
| Limites | Só sessão (5h) e semana (7d). Limite semanal por modelo fica fora da v1. |
| Licença | MIT |

## Objetivo

Um app de barra de menus, público e gratuito, para quem usa Claude Code acompanhar o próprio consumo e os workflows sem precisar abrir o terminal.

Histórias de usuário:

- Vejo de relance, na barra de menus, quanto já usei do limite de 5 horas e da semana.
- Ao clicar, vejo o detalhe: sessão (5h) e semana, cada uma com barra, porcentagem e horário de reset.
- Vejo os workflows de todos os projetos: nome, projeto, tempo, agentes concluídos/total e tokens.
- Ao abrir um workflow, vejo as fases e cada agente: rótulo, modelo, tokens, tempo e status.
- Conecto o app ao Claude Code com um clique e desfaço com um clique, sem perder o status line que já uso.

Fora do escopo da v1: custo em dólar, limite semanal por modelo, "What's contributing to your limits", parar ou pausar workflows, uso feito em outras máquinas, notificações e subagentes fora de workflow.

## De onde vêm os dados

| Dado | Fonte | Observação |
|---|---|---|
| % da sessão (5h) e da semana | JSON que o Claude Code envia ao comando de status line: `rate_limits.five_hour` e `rate_limits.seven_day`, cada um com `used_percentage` e `resets_at` (epoch em segundos) | Documentado. Só atualiza com o Claude Code aberto. |
| Sessões vivas | `~/.claude/sessions/<pid>.json` (`pid`, `sessionId`, `cwd`, `status`), mais a checagem de que o PID ainda existe | Formato interno |
| Workflows e agentes | `~/.claude/projects/<projeto>/<sessão>/subagents/workflows/<runId>/journal.jsonl`: eventos `started` e `result` por agente, com `agentId`, `label` e `phase` | Formato interno |
| Nome, descrição e fases | `export const meta` em `<sessão>/workflows/scripts/<nome>-<runId>.js` | Formato interno |
| Workflow concluído | Existência de `<sessão>/workflows/<runId>.json` | Formato interno |
| Tokens, modelo e "idle" por agente | `agent-<id>.jsonl`: linhas `type: "assistant"` com `message.model` e `message.usage`; o mtime do arquivo dá o "idle" | Arquivos de 2–3 MB, então a leitura é incremental |

Status de um workflow:

- **Rodando:** não existe o `<runId>.json` final e a sessão dona está viva.
- **Concluído:** o `<runId>.json` existe.
- **Interrompido:** não existe o `.json` final e a sessão dona morreu.

## Integração com o status line

- O app instala `~/.claude/agentbar/statusline.sh` e aponta `statusLine.command` do `~/.claude/settings.json` para ele.
- O script salva `rate_limits` em `~/.claude/agentbar/rate_limits.json` com escrita atômica. Depois repassa o mesmo stdin ao comando de status line que existia antes e imprime a saída dele, para que o status line atual continue igual.
- Antes de editar o `settings.json`, o app faz backup. "Desconectar" restaura o comando anterior.
- Se a pessoa usa `CLAUDE_CONFIG_DIR`, dá para escolher a pasta nos Ajustes.
- O script precisa rodar em menos de 50 ms para não atrasar o Claude Code.

## Interface

**Barra de menus:** duas linhas empilhadas, no estilo do CPU/MEM:

```
5h 27%
7d 45%
```

Cada linha tem a própria cor: normal abaixo de 70%, âmbar de 70% a 89%, vermelho a partir de 90%. Se o horário de reset de uma janela já passou, ela mostra 0%. Sem dados, mostra `--`.

**Popover ao clicar:**

```
┌───────────────────────────────────────────┐
│ Sessão atual (5h)                    27%  │
│ ███████░░░░░░░░░░░░░░░░░░                 │
│ Reseta 02:50 · em 3h 35m                  │
│                                           │
│ Semana (todos os modelos)            45%  │
│ ███████████░░░░░░░░░░░░░░                 │
│ Reseta sex 31/10 11:59                    │
│ Atualizado há 1 min                       │
├───────────────────────────────────────────┤
│ Workflows · 1 rodando · 6 concluídos (24h)│
│ ● revisar-checkout                        │
│   meu-app · 23m 49s · 3/6 agentes · 991.8k│
│ ✓ mapear-api-de-pagamentos        3h 45m  │
│ ✓ corrigir-testes-instaveis       28m     │
├───────────────────────────────────────────┤
│ Ajustes…                            Sair  │
└───────────────────────────────────────────┘
```

**Detalhe do workflow:** descrição, fases com progresso (`Revisão 3/3`, `Verificação 0/3`) e, para cada agente, `rótulo · modelo · tokens · tempo · status`, onde status é rodando, concluído ou `idle 34s`.

**Ajustes:** abrir ao iniciar a sessão do Mac, conectar ou desconectar o status line e a pasta do Claude.

## Tech stack

- Swift 6.4 com modo de linguagem 6 (concorrência estrita).
- Item da barra com AppKit (`NSStatusItem`), porque o `MenuBarExtra` do SwiftUI não renderiza bem um rótulo de duas linhas. O conteúdo (rótulo e popover) é SwiftUI, hospedado em `NSHostingView` e `NSPopover`.
- `@Observable` para o estado.
- Swift Package Manager, sem dependências externas.
- `LSUIElement = YES` (sem ícone no Dock).
- Monitoramento de arquivos com FSEvents e um timer de 5 s como reserva.
- Abrir no login com `SMAppService.mainApp`.

## Comandos

```bash
swift build                     # compila em debug
swift test                      # roda os testes
swift run agentbar-dump         # mostra no terminal o que o app está lendo (diagnóstico)
./scripts/bundle.sh             # gera build/AgentBar.app em release, com assinatura ad-hoc
open build/AgentBar.app         # abre o app
./scripts/release.sh            # gera build/AgentBar-<versão>.zip para o GitHub Releases
```

## Estrutura do projeto

```
Package.swift
Sources/
  AgentBarCore/            → leitura e interpretação dos arquivos, sem UI (testável)
    RateLimits/
    Workflows/
    Sessions/
    StatusLineInstaller/
    Store/
  AgentBar/                → app: item da barra, popover e ajustes
  agentbar-dump/           → ferramenta de diagnóstico em linha de comando
Tests/
  AgentBarCoreTests/
    Fixtures/              → arquivos sintéticos imitando o formato do Claude Code
Resources/
  Info.plist               → o statusline.sh fica embutido no código (StatusLineScript.swift)
scripts/
  bundle.sh
  release.sh
SPEC.md
PLAN.md
README.md
LICENSE
```

## Estilo de código

```swift
/// Uma janela de limite, como o Claude Code entrega no status line.
struct RateLimitWindow: Codable, Sendable, Equatable {
    let usedPercentage: Double
    let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    /// Depois do reset, o valor salvo deixa de valer: a janela recomeçou do zero.
    func effectivePercentage(now: Date = .now) -> Double {
        now >= resetsAt ? 0 : usedPercentage
    }
}
```

- Tipos e código em inglês. Os textos da interface ficam num String Catalog com pt-BR e en.
- Parsers são funções puras sobre `Data` ou `URL` e não tocam na UI.
- Nada de force unwrap no parsing: campo ausente ou desconhecido vira `nil` e a UI mostra "—".
- `@MainActor` só na camada de UI e no store.

## Estratégia de testes

- Swift Testing (`import Testing`), rodado com `swift test`.
- No Core, com fixtures sintéticas:
  - `rate_limits`: normal, ausente e com reset já passado.
  - journal: rodando, concluído, interrompido e com a última linha cortada (arquivo sendo escrito).
  - `meta` do script.
  - Soma de tokens.
  - Leitura incremental com o arquivo crescendo entre duas leituras.
- No instalador: `settings.json` com e sem `statusLine` anterior, e com campos desconhecidos, que precisam ser preservados. Também a restauração.
- Calibração manual: a soma de tokens tem que bater com o painel de workflows do Claude Code numa execução real.
- UI: verificação manual com o app rodando.
- Meta de cobertura: 90% ou mais no Core. A UI não tem meta.

## Limites

**Sempre:**

- Em `~/.claude`, só leitura, com três exceções: o script de status line, a pasta do próprio app e a chave `statusLine` do `settings.json` (com backup).
- Tolerar formato desconhecido sem travar: mostrar "formato não reconhecido" e seguir.
- Rodar `swift test` antes de cada commit.
- Usar só fixtures sintéticas nos testes.

**Perguntar antes:**

- Adicionar qualquer dependência externa.
- Qualquer chamada de rede, inclusive checagem de atualização (Sparkle).
- Ler o Keychain ou usar endpoint não documentado da Anthropic.
- Mudar a versão mínima do macOS.
- Mexer no `~/.claude/settings.json` real durante o desenvolvimento.
- Criar o repositório no GitHub ou publicar uma release.

**Nunca:**

- Enviar dados para fora da máquina ou incluir telemetria.
- Commitar transcrições reais, nomes de projetos ou trechos de `~/.claude`, porque o repositório vai ser público.
- Usar o logo da Anthropic ou do Claude, ou um nome que pareça oficial.
- Escrever nos arquivos de sessão ou de workflow do Claude Code.

## Critérios de sucesso

1. Com uma sessão do Claude Code aberta, as duas porcentagens na barra de menus ficam iguais às do `/usage` (arredondadas) em até 10 s depois de o status line atualizar.
2. Depois do horário de reset, a janela aparece como 0% sem precisar abrir o Claude Code.
3. Um workflow novo aparece no popover em até 5 s depois de começar e passa para concluído em até 5 s depois de terminar.
4. Cada workflow mostra nome, projeto, tempo, agentes concluídos/total e tokens. Os tokens ficam a no máximo 2% do valor do painel do Claude Code.
5. Cada agente mostra rótulo, fase, modelo, tokens, tempo e status (rodando, concluído ou idle).
6. Um workflow de sessão fechada aparece como "interrompido", e não como "rodando" para sempre.
7. Conectar e desconectar preservam o status line anterior: o seu `5h:27% | 7d:45%` continua aparecendo.
8. Em repouso, com 10 workflows na lista: CPU média abaixo de 1% e memória abaixo de 80 MB.
9. Nenhuma chamada de rede (dá para verificar com `nettop` ou Little Snitch).
10. Uma pessoa que nunca viu o projeto consegue baixar o `.zip` do GitHub Releases e abrir o app seguindo só o README, que explica a liberação em Ajustes do Sistema > Privacidade e Segurança > "Abrir Mesmo Assim" e também como compilar a partir do código.

## Riscos

- **Formato interno pode mudar.** Os arquivos de workflow são internos do Claude Code e podem mudar em qualquer atualização. Mitigação: parser tolerante, testes com fixtures, `agentbar-dump` para diagnosticar, aviso na UI e registro da versão do Claude Code testada.
- **Porcentagem defasada.** O `rate_limits` só chega com o Claude Code aberto. Uso feito no claude.ai ou em outra máquina só aparece na próxima atualização. A UI mostra "Atualizado há X".
- **Instalação com atrito.** Sem assinatura da Apple, cada pessoa precisa liberar o app manualmente na primeira abertura e a cada atualização. Isso só some com a notarização, quando houver conta Apple Developer.
- **Já existe app parecido.** O script atual do seu status line foi instalado por um app chamado "Token Usage for Claude", que já cobre a porcentagem. O diferencial do AgentBar é a parte de workflows.
