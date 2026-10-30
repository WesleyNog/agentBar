/// Script que o AgentBar instala como status line do Claude Code.
///
/// Fica embutido no código (e não como recurso) para o `.app` não depender de bundle de recursos.
enum StatusLineScript {
    static let contents = #"""
    #!/bin/bash
    # Instalado pelo AgentBar.
    # Salva os limites de uso (rate_limits) que o Claude Code envia ao status line
    # e repassa a mesma entrada ao status line que existia antes, se houver.
    dir="$(cd "$(dirname "$0")" && pwd)"
    input=$(cat)

    # Um arquivo por sessão: sessões paradas reenviam números antigos, e o AgentBar
    # escolhe os mais recentes ao juntar todos.
    # O status line roda a cada resposta: o que der para fazer sem abrir processo, é feito no bash.
    limits="$dir/rate_limits"
    [ -d "$limits" ] || mkdir -p "$limits"
    session="sem-sessao"
    if [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]+)\" ]]; then
        session="${BASH_REMATCH[1]}"
    fi
    target="$limits/$session.json"

    # Sessão nova: limpa as que estão sem notícia há mais de 8 dias e o arquivo único das versões anteriores.
    if [ ! -e "$target" ]; then
        find "$limits" -name '*.json' -mtime +8 -delete 2>/dev/null
        rm -f "$dir/rate_limits.json"
    fi

    # Escrita atômica: arquivo temporário na mesma pasta e depois mv.
    if tmp=$(mktemp "$limits/.tmp.XXXXXX" 2>/dev/null); then
        if printf '%s' "$input" | plutil -extract rate_limits json -o "$tmp" - 2>/dev/null; then
            mv -f "$tmp" "$target"
        else
            rm -f "$tmp"
        fi
    fi

    previous=$(plutil -extract command raw -o - "$dir/previous-statusline.json" 2>/dev/null)
    if [ -n "$previous" ]; then
        printf '%s' "$input" | /bin/bash -c "$previous"
    fi
    """# + "\n"
}
