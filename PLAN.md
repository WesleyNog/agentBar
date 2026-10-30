# Plano e tarefas: AgentBar

> Baseado em [SPEC.md](SPEC.md) · 29/10/2026

## Abordagem

Primeiro o núcleo (`AgentBarCore`): código puro, testado com fixtures e conferido contra os dados reais desta máquina pelo `agentbar-dump`. A interface só vem depois que os números estiverem certos. As duas incertezas técnicas são atacadas primeiro: o rótulo de duas linhas na barra (T1) e a fórmula de tokens (T6).

## Componentes e dependências

```
T1 Esqueleto + item da barra
 ├── T2 Limites de uso ─────────┐
 ├── T3 Status line + instalador │
 ├── T4 Sessões vivas ───────────┤
 └── T5 Workflows ── T6 Tokens ──┤
                                 ▼
                      T7 agentbar-dump  ← checkpoint B
                                 ▼
                      T8 Store + monitoramento de arquivos
                                 ▼
               T9 Barra + uso  →  T10 Workflows na UI  →  T11 Ajustes
                                 ▼
                      T12 Empacotamento  →  T13 Verificação final
```

T2 a T5 são independentes entre si depois do T1.

## Riscos

| Risco | Mitigação |
|---|---|
| Rótulo de duas linhas não ficar bom na barra (tamanho, claro/escuro) | T1 é um protótipo só disso. Se `NSHostingView` não ficar bom, o rótulo é desenhado como imagem. |
| Soma de tokens diferente da que o Claude Code mostra | T6 calibra contra um workflow real antes de fechar. |
| Estragar o `settings.json` de quem instala | Backup com data e hora, campos desconhecidos preservados e testes só em pastas temporárias. A gravação mexe só no trecho do `statusLine`: ordem e formatação do resto ficam iguais (se a edição não conferir, regrava o JSON inteiro). |
| Transcrições de agentes grandes (2–3 MB cada) | Leitura incremental a partir do último byte lido. Só entram workflows rodando ou das últimas 24 h. |
| Formato interno do Claude Code mudar | Parser tolerante e `agentbar-dump` para diagnosticar. |
| Abrir no login não funcionar com app sem assinatura | Testado no T11. Se falhar, a opção fica desativada com explicação. |

## Checkpoints

- **A (após T1):** o app aparece na barra com o rótulo de duas linhas, ainda com dados fixos.
- **B (após T7):** `swift test` passa e `swift run agentbar-dump` mostra os dados reais batendo com o `/usage` e com o painel de workflows.
- **C (após T11):** o app mostra tudo ao vivo e conecta/desconecta o status line.
- **D (após T13):** o `.zip` instala do zero seguindo o README e os 10 critérios de sucesso estão conferidos.

## Tarefas

- [x] **T1: Esqueleto e protótipo do item da barra**
  - Aceite: `git init`, `.gitignore` e `Package.swift` com os alvos `AgentBarCore`, `AgentBar`, `agentbar-dump` e `AgentBarCoreTests`. `scripts/bundle.sh` gera `build/AgentBar.app` (sem ícone no Dock, assinatura ad-hoc). O app mostra `5h 27%` / `7d 45%` fixos em duas linhas e abre um popover vazio ao clicar. Fica legível com a barra clara e escura.
  - Verificar: `swift build && swift test && ./scripts/bundle.sh && open build/AgentBar.app`, mais uma captura de tela da barra.
  - Arquivos: `Package.swift`, `.gitignore`, `Resources/Info.plist`, `scripts/bundle.sh`, `Sources/AgentBar/AgentBarApp.swift`, `Sources/AgentBar/StatusItemController.swift`

- [x] **T2: Leitura dos limites de uso**
  - Aceite: `RateLimits` decodifica o JSON salvo pelo status line. Reset já passado vira 0%. Arquivo ausente ou inválido retorna `nil` sem travar. O "atualizado há" vem do mtime do arquivo.
  - Verificar: `swift test --filter RateLimits`
  - Arquivos: `Sources/AgentBarCore/RateLimits/RateLimits.swift`, `RateLimitsReader.swift`, `Tests/AgentBarCoreTests/RateLimitsTests.swift`, fixtures `rate_limits*.json`

- [x] **T3: Script de status line e instalador**
  - Aceite:
    - `statusline.sh` salva `rate_limits` com escrita atômica, repassa o stdin ao comando anterior, imprime a saída dele e roda em menos de 50 ms.
    - O instalador faz backup, troca o `statusLine`, guarda o anterior e preserva os outros campos.
    - "Desconectar" restaura o anterior.
    - O instalador detecta o estado: conectado, outro comando ou nenhum.
  - Verificar: `swift test --filter StatusLine`, cobrindo `settings.json` com e sem `statusLine`, com campos extras e a restauração. Mais `echo '<json>' | statusline.sh` com `time`. Nada toca no seu `settings.json` real.
  - Arquivos: `Sources/AgentBarCore/StatusLineInstaller/StatusLineScript.swift` (script embutido), `StatusLineInstaller.swift`, `Tests/AgentBarCoreTests/StatusLineInstallerTests.swift`, fixtures `settings*.json`

- [x] **T4: Sessões vivas**
  - Aceite: lê `sessions/*.json`, mapeia `sessionId` para pid, cwd e status, marca como viva se o PID existe e ignora arquivos ilegíveis.
  - Verificar: `swift test --filter Session`
  - Arquivos: `Sources/AgentBarCore/Sessions/SessionRegistry.swift`, `Tests/AgentBarCoreTests/SessionRegistryTests.swift`, fixtures `sessions/`

- [x] **T5: Descoberta e estado dos workflows**
  - Aceite:
    - Encontra execuções em `projects/*/*/subagents/workflows/*` que estão rodando ou que mudaram nas últimas 24 h.
    - Lê nome, descrição e fases do `meta` do script.
    - Do journal, tira os agentes (rótulo, fase, iniciado/terminado), aguentando a última linha cortada.
    - Define o status: rodando, concluído ou interrompido.
    - Tira o nome do projeto do `cwd` da sessão ou, sem ele, do nome da pasta.
  - Verificar: `swift test --filter Workflow`
  - Arquivos: `Sources/AgentBarCore/Workflows/WorkflowRun.swift`, `WorkflowScanner.swift`, `JournalParser.swift`, `ScriptMetaParser.swift`, `Tests/AgentBarCoreTests/WorkflowTests.swift`

- [x] **T6: Tokens, modelo e tempo por agente**
  - Aceite: um leitor incremental de `agent-*.jsonl` guarda o offset, lê só o que cresceu e aguenta linha incompleta. Dele saem a soma de tokens, o último modelo, início e fim, e o tempo idle. A fórmula de tokens bate com o painel do Claude Code com diferença de até 2%.
  - Verificar: `swift test --filter AgentTranscript`, mais a comparação manual com o painel de workflows numa execução real.
  - Arquivos: `Sources/AgentBarCore/Workflows/AgentTranscriptReader.swift`, `IncrementalLineReader.swift`, `Tests/AgentBarCoreTests/AgentTranscriptTests.swift`, fixtures `agent-*.jsonl`

- [x] **T7: Ferramenta de diagnóstico `agentbar-dump`** · checkpoint B
  - Aceite: `swift run agentbar-dump` imprime limites, sessões vivas e workflows com agentes, em texto ou com `--json`. Usa só o Core.
  - Verificar: rodar nesta máquina e comparar com o `/usage` e com o painel de workflows.
  - Arquivos: `Sources/agentbar-dump/main.swift`

- [x] **T8: Store e monitoramento de arquivos**
  - Aceite:
    - `AgentBarStore` (`@Observable`, `@MainActor`) junta limites, sessões e workflows.
    - FSEvents vigia `~/.claude/agentbar` e `~/.claude/projects`, com um timer de 5 s como reserva.
    - A leitura roda fora da main thread, com no máximo uma atualização por segundo.
    - O "reseta em" é recalculado a cada minuto.
  - Verificar: `swift test --filter Store`, numa pasta temporária: criar um arquivo e ver o estado mudar.
  - Arquivos: `Sources/AgentBarCore/Store/AgentBarStore.swift`, `FileWatcher.swift`, `Tests/AgentBarCoreTests/StoreTests.swift`

- [x] **T9: Barra e seção de uso**
  - Aceite:
    - O rótulo de duas linhas usa dados reais, com cor por faixa e `--` quando não há dados.
    - O popover mostra sessão e semana (barra, %, reset, "atualizado há").
    - Aparece um aviso quando o status line não está conectado.
    - Os textos estão em pt-BR e en.
  - Verificar: app rodando, capturas comparadas com o esboço da spec e conferência com o sistema em inglês.
  - Arquivos: `Sources/AgentBar/StatusItemLabel.swift`, `PopoverView.swift`, `UsageSection.swift`, `Resources/Localizable.xcstrings`

- [x] **T10: Workflows na interface**
  - Aceite: a lista mostra primeiro os que estão rodando e depois os concluídos e interrompidos das últimas 24 h, com nome, projeto, tempo, agentes e tokens. O detalhe mostra a descrição, as fases com progresso e, em cada agente, rótulo, modelo, tokens, tempo e status.
  - Verificar: app rodando durante um workflow real, comparando com o painel do Claude Code.
  - Arquivos: `Sources/AgentBar/WorkflowList.swift`, `WorkflowDetail.swift`, `Resources/Localizable.xcstrings`

- [x] **T11: Ajustes** · checkpoint C
  - Aceite:
    - Conectar e desconectar o status line, com uma confirmação que mostra o que vai mudar.
    - Abrir no login.
    - Escolher a pasta do Claude.
    - Sair.
  - Verificar (pergunto antes de mexer no seu `settings.json` real):
    - Depois de conectar, seu status line continua mostrando `5h:… | 7d:…` e o arquivo do AgentBar passa a ser atualizado.
    - Depois de desconectar, o `diff` contra o backup mostra o `settings.json` igual ao original.
  - Arquivos: `Sources/AgentBar/SettingsView.swift`, `LoginItem.swift`

- [x] **T12: Empacotamento e documentação**
  - Aceite:
    - Ícone do app.
    - `scripts/release.sh` gera `build/AgentBar-<versão>.zip` em release, com assinatura ad-hoc.
    - README em pt-BR e en explicando:
      - o que o app faz;
      - privacidade (nada sai da máquina);
      - instalação por "Abrir Mesmo Assim" ou compilando do código;
      - que é um projeto não oficial.
    - `LICENSE` MIT.
  - Verificar: baixar o `.zip` com o atributo de quarentena, como outra pessoa faria, e seguir o README do zero.
  - Arquivos: `scripts/release.sh`, `README.md`, `LICENSE`, `Resources/AppIcon.icns`

- [ ] **T13: Verificação final** · checkpoint D
  - Aceite: os 10 critérios de sucesso da spec conferidos, com o resultado anotado aqui embaixo.
  - Verificar: checklist abaixo. Publicar no GitHub só com a sua confirmação.

## Checklist dos critérios de sucesso

- [x] 1. Porcentagens iguais às do `/usage` em até 10 s — 30/10: barra 19%/49% igual ao status line do terminal
- [ ] 2. Janela vira 0% depois do reset
- [ ] 3. Workflow aparece e conclui em até 5 s — 30/10: apareceu ao vivo com 59 s de execução; falta cronometrar o início e o fim
- [x] 4. Tokens por workflow a no máximo 2% do painel — concluídos idênticos; rodando: 436.8k (59 s) contra 442.3k (1m00s) no Claude Code, mesma curva
- [x] 5. Detalhe de cada agente completo — 30/10: fase, rótulo, modelo, tokens e tempo batendo com o painel
- [ ] 6. Sessão fechada mostra "interrompido"
- [x] 7. Status line anterior preservado — 30/10: `5h:19% | 7d:49%` continua no terminal depois de conectar
- [x] 8. CPU abaixo de 1% e memória abaixo de 80 MB em repouso — 30/10: 0,2% e 49 MB
- [ ] 9. Nenhuma chamada de rede
- [ ] 10. Instalação do zero seguindo o README
