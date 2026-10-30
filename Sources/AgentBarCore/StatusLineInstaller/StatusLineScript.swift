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

    # Escrita atômica: arquivo temporário na mesma pasta e depois mv.
    if tmp=$(mktemp "$dir/.rate_limits.XXXXXX" 2>/dev/null); then
        if printf '%s' "$input" | plutil -extract rate_limits json -o "$tmp" - 2>/dev/null; then
            mv -f "$tmp" "$dir/rate_limits.json"
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
