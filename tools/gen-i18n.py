#!/usr/bin/env python3
"""
tools/gen-i18n.py — regenera o bloco de catálogo de mensagens dentro de
secrets.bash a partir dos arquivos i18n/*.json.

Uso:
    python3 tools/gen-i18n.py [caminho-do-secrets.bash]

Cada arquivo i18n/<codigo>.json vira um array associativo bash chamado
_SECRETS_MSG_<CODIGO> (maiúsculo), mais uma função _secrets_usage_text_<codigo>
com o texto de --help daquele idioma (a chave especial "_usage_full").

O secrets.bash precisa ter os marcadores abaixo (já vêm no arquivo):
    # >>> AUTO-GENERATED I18N CATALOG - DO NOT EDIT BY HAND <<<
    ...
    # >>> END AUTO-GENERATED I18N CATALOG <<<

Fluxo de trabalho pra adicionar/atualizar um idioma:
    1. Crie ou edite i18n/<codigo>.json (ou baixe do Weblate).
    2. Rode: python3 tools/gen-i18n.py secrets.bash
    3. Rode a bateria de testes.
    4. Commit.

Nenhuma dependência externa além de python3 — não precisa de jq,
gettext, msgfmt, nem nada além do que já vem no sistema.
"""
import json
import re
import sys
from pathlib import Path

BEGIN_MARKER = "# >>> AUTO-GENERATED I18N CATALOG - DO NOT EDIT BY HAND <<<"
END_MARKER = "# >>> END AUTO-GENERATED I18N CATALOG <<<"


def bash_escape(value: str) -> str:
    # Dentro de aspas duplas do bash: escapar barra invertida, aspas
    # duplas, crase e cifrão (que dispararia expansão de variável/comando).
    value = value.replace("\\", "\\\\")
    value = value.replace('"', '\\"')
    value = value.replace("`", "\\`")
    value = value.replace("$", "\\$")
    return value


def load_langs(i18n_dir: Path):
    langs = {}
    for jf in sorted(i18n_dir.glob("*.json")):
        code = jf.stem  # "pt", "en", "es", etc.
        with open(jf, "r", encoding="utf-8") as f:
            data = json.load(f)
        if "_usage_full" not in data:
            print(f"AVISO: {jf} não tem a chave '_usage_full' — help ficará vazio nesse idioma", file=sys.stderr)
        langs[code] = data
    return langs


def render_array(code: str, data: dict) -> str:
    varname = f"_SECRETS_MSG_{code.upper()}"
    lines = [f"declare -A {varname}=("]
    for key in sorted(data.keys()):
        if key == "_usage_full":
            continue
        lines.append(f'\t[{key}]="{bash_escape(data[key])}"')
    lines.append(")")
    return "\n".join(lines)


def render_usage_function(code: str, data: dict) -> str:
    text = data.get("_usage_full", "")
    # heredoc sem expansão de variáveis do bash (quoted delimiter),
    # {PROG} é substituído em runtime com sed-like replace no bash.
    return (
        f"_secrets_usage_text_{code}() {{\n"
        f"\tcat <<-'_I18N_EOF_{code.upper()}'\n"
        + "\n".join("\t" + line for line in text.split("\n"))
        + f"\n\t_I18N_EOF_{code.upper()}\n"
        f"}}"
    )


def build_block(langs: dict) -> str:
    parts = [BEGIN_MARKER, ""]
    parts.append(
        "# Gerado por tools/gen-i18n.py a partir de i18n/*.json — para\n"
        "# adicionar ou corrigir uma tradução, edite o .json correspondente\n"
        "# e rode o gerador de novo. Não edite este bloco à mão, a próxima\n"
        "# regeneração vai sobrescrever."
    )
    parts.append("")
    parts.append(f"readonly _SECRETS_LANGS_AVAILABLE=({' '.join(sorted(langs.keys()))})")
    parts.append("")
    for code, data in sorted(langs.items()):
        parts.append(render_array(code, data))
        parts.append("")
    for code, data in sorted(langs.items()):
        parts.append(render_usage_function(code, data))
        parts.append("")
    parts.append(END_MARKER)
    return "\n".join(parts)


def main():
    script_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("secrets.bash")
    i18n_dir = Path(__file__).resolve().parent.parent / "i18n"

    langs = load_langs(i18n_dir)
    if not langs:
        print(f"Nenhum arquivo .json encontrado em {i18n_dir}", file=sys.stderr)
        sys.exit(1)

    new_block = build_block(langs)

    content = script_path.read_text(encoding="utf-8")
    if BEGIN_MARKER not in content or END_MARKER not in content:
        print("Marcadores de catálogo não encontrados em", script_path, file=sys.stderr)
        sys.exit(1)

    pattern = re.compile(
        re.escape(BEGIN_MARKER) + r".*?" + re.escape(END_MARKER),
        re.DOTALL,
    )
    updated = pattern.sub(new_block, content, count=1)
    script_path.write_text(updated, encoding="utf-8")

    keys_per_lang = {code: len([k for k in d if k != "_usage_full"]) for code, d in langs.items()}
    print(f"OK — {len(langs)} idioma(s) gerado(s) em {script_path}: {keys_per_lang}")


if __name__ == "__main__":
    main()
