#!/usr/bin/env bash
# pass secrets - Password Store Extension
#
# Alternativa ao pass-tomb para obscurecer a árvore do pass. Serviços e
# pastas usam codinomes aleatórios; a associação real é guardada num
# arquivo .secrets.gpg por identidade.
#
# Identidade = qualquer diretório da árvore do pass que contenha um
# .gpg-id próprio, em qualquer profundidade (não precisa estar no
# topo). Cada identidade é fronteira de confiança própria: uma
# identidade aninhada dentro de outra NÃO herda a chave da pai, e
# comprometer a chave da pai não expõe o conteúdo da filha.
#
# NOTA: nomes de identidade devem ser únicos em toda a árvore,
# independente de profundidade. Dois diretórios com .gpg-id e o mesmo
# nome tornam o comando ambíguo e são recusados.
#
# Instalação (extensão real do pass, não script sourced no .bashrc):
#   1. mkdir -p "$PASSWORD_STORE_EXTENSIONS_DIR" (padrão: ~/.password-store/.extensions)
#   2. cp secrets.bash "$PASSWORD_STORE_EXTENSIONS_DIR/secrets.bash"
#   3. chmod +x "$PASSWORD_STORE_EXTENSIONS_DIR/secrets.bash"
#   4. export PASSWORD_STORE_ENABLE_EXTENSIONS=true   (no .bashrc/.zshrc)
#
# Uso:
#   pass secrets <identidade> dir     <bloco>
#   pass secrets <identidade> word    <termo> [contexto]
#   pass secrets <identidade> count   <bloco>
#   pass secrets <identidade> edit
#   pass secrets <identidade> check
#   pass secrets <identidade> struct
#   pass secrets <identidade> add     <caminho-relativo> <nome-real>
#   pass secrets <identidade> rebuild [--yes] [--prune]
#   pass secrets <identidade> mask add  <alias-email> <caminho-dir>
#   pass secrets <identidade> mask dir  <caminho-dir>
#   pass secrets <identidade> mask word <termo> [contexto]
#   pass secrets <identidade> mask edit
#   pass secrets <identidade> mask list
#   pass secrets <identidade> namegen [bloco] [-n tamanho] [-u quantidade]
#   pass secrets <identidade> generate [bloco] [tamanho] [flags do pass generate]
#
# Formato do mapa (.secrets.gpg, texto plano antes de cifrar):
#   <caminho-do-codinome-relativo-a-identidade> = <nome real / descrição>

readonly VERSION_SECRETS="2.1.0"

cmd_secrets_version() {
	echo "$VERSION_SECRETS"
}

cmd_secrets_usage() {
	cat <<-_EOF
	$PROGRAM $COMMAND - alternativa ao pass-tomb para obscurecer a árvore do pass

	Uso:
	    $PROGRAM $COMMAND <identidade> dir     <bloco>
	    $PROGRAM $COMMAND <identidade> word    <termo> [contexto]
	    $PROGRAM $COMMAND <identidade> count   <bloco>
	    $PROGRAM $COMMAND <identidade> edit
	    $PROGRAM $COMMAND <identidade> check
	    $PROGRAM $COMMAND <identidade> struct
	    $PROGRAM $COMMAND <identidade> add     <caminho-relativo> <nome-real>
	    $PROGRAM $COMMAND <identidade> rebuild [--yes] [--prune]
	    $PROGRAM $COMMAND <identidade> mask add  <alias-email> <caminho-dir>
	    $PROGRAM $COMMAND <identidade> mask dir  <caminho-dir>
	    $PROGRAM $COMMAND <identidade> mask word <termo> [contexto]
	    $PROGRAM $COMMAND <identidade> mask edit
	    $PROGRAM $COMMAND <identidade> mask list
	    $PROGRAM $COMMAND <identidade> namegen  [bloco] [-n tamanho] [-u quantidade]
	    $PROGRAM $COMMAND <identidade> generate [bloco] [tamanho] [flags do pass generate]

	identidade:
	    qualquer diretório da árvore do pass que contenha seu próprio
	    .gpg-id, em qualquer profundidade. NOMES DE IDENTIDADE DEVEM SER
	    ÚNICOS EM TODA A ÁRVORE — dois diretórios com .gpg-id e o mesmo
	    nome tornam o comando ambíguo e são recusados.

	comandos:
	    dir     <bloco>                lista entradas cujo caminho começa com <bloco>
	    word    <termo> [contexto]     busca um termo no mapa (grep -C)
	    count   <bloco>                conta entradas sob <bloco>
	    edit                           abre o .secrets.gpg no vim (via vim-gnupg)
	    check                          audita o mapa contra a árvore real (somente leitura)
	    struct                         lista a estrutura real de codinomes (scan do disco, sem decifrar)
	    add     <caminho> <nome-real>  associa manualmente um codinome já existente
	    rebuild [--yes] [--prune]      varre a árvore real e reconcilia o mapa
	                                       --yes:   não pergunta nome real p/ entradas novas
	                                       --prune: remove entradas órfãs do mapa
	    mask add <alias> <dir>         associa um alias de e-mail a um diretório
	                                    (many-to-many: mesmo alias pode servir
	                                    vários diretórios, e vice-versa)
	    mask dir <dir>                 lista aliases associados a um diretório
	    mask word <termo> [contexto]   busca um alias/diretório no .mask.gpg
	    mask edit                      abre o .mask.gpg no vim (via vim-gnupg)
	    mask list                      lista todo o conteúdo do .mask.gpg
	    namegen [bloco] [-n L] [-u Q]  sugere Q codinome(s) livre(s) de tamanho L,
	                                    sem criar nada (colisão checada só dentro
	                                    da identidade; entre identidades pode repetir)
	    generate [bloco] [tamanho]     gera um codinome livre E já cria a entrada
	                                    real via 'pass generate' — não registra a
	                                    associação (use 'add' depois)

	More information may be found in the pass-secrets(1) man page.
	_EOF
}

# ---------------------------------------------------------------------
# Resolução de identidade e I/O do mapa
# ---------------------------------------------------------------------

_secrets_valid_token() {
	# Usado para bloco/caminho vindos do usuário — evita injeção em
	# grep/awk e caracteres que quebrariam o parsing "chave = valor".
	[[ "$1" =~ ^[A-Za-z0-9_./-]+$ ]] && [[ "$1" != *..* ]]
}

# Escapa '.' antes de inserir um token do usuário num padrão grep -E.
# Necessário porque _secrets_valid_token permite '.' no token, mas em
# ERE '.' significa "qualquer caractere" — sem isso, um caminho com
# ponto pode casar (e em 'add', sobrescrever) uma entrada diferente
# por acidente.
_secrets_re_escape() {
	printf '%s' "${1//./\\.}"
}

# Encontra o diretório de uma identidade pelo nome, em qualquer
# profundidade. Recusa se ambíguo (mais de um .gpg-id com esse nome).
_secrets_resolve() {
	local nome="$1"
	[[ -n "$nome" ]] || die "$PROGRAM $COMMAND: nome de identidade vazio"
	check_sneaky_paths "$nome"
	_secrets_valid_token "$nome" || die "$PROGRAM $COMMAND: nome de identidade inválido"

	local -a matches=()
	local d
	while IFS= read -r -d '' d; do
		matches+=("$d")
	done < <(find "$PREFIX" -type d -name "$nome" -exec test -f "{}/.gpg-id" \; -print0 2>/dev/null)

	case "${#matches[@]}" in
		0)
			die "$PROGRAM $COMMAND: identidade '$nome' não encontrada (nenhum diretório com esse nome contém .gpg-id)"
			;;
		1)
			printf '%s\n' "${matches[0]}"
			;;
		*)
			{
				echo "$PROGRAM $COMMAND: identidade '$nome' é ambígua, encontrada em múltiplos caminhos:"
				printf '  %s\n' "${matches[@]}"
				echo "$PROGRAM $COMMAND: renomeie um dos diretórios para desambiguar (nomes de identidade devem ser únicos em toda a árvore)"
			} >&2
			exit 1
			;;
	esac
}

# Caminho de um arquivo cifrado da identidade (.secrets.gpg, .mask.gpg,
# etc), com checagem de permissões quando o arquivo já existe. Não
# decifra nada. $2 é o nome do arquivo dentro da pasta da identidade,
# default .secrets.gpg pra manter compatibilidade com quem já chamava
# sem esse argumento.
_secrets_mapfile() {
	local nome="$1" nomearq="${2:-.secrets.gpg}"
	local dir
	dir=$(_secrets_resolve "$nome") || exit 1

	local mapfile="$dir/$nomearq"
	if [[ -f "$mapfile" ]]; then
		local perms
		perms=$(stat -c '%a' "$mapfile")
		[[ "$perms" == "640" || "$perms" == "600" ]] || \
			die "$PROGRAM $COMMAND: permissões inseguras em '$mapfile' ($perms) — corrija para 640 ou 600"
	fi
	printf '%s\n' "$mapfile"
}

# Destinatários GPG da PRÓPRIA pasta da identidade — nunca sobe a
# árvore como set_gpg_recipients faria. Isso é o que garante o
# isolamento entre identidade pai/filha.
_secrets_recipients() {
	local nome="$1"
	local dir
	dir=$(_secrets_resolve "$nome") || exit 1

	local -a args=()
	local id
	while IFS= read -r id; do
		id="${id%%#*}"
		[[ -n "$id" ]] || continue
		args+=( -r "$id" )
	done < "$dir/.gpg-id"

	[[ ${#args[@]} -gt 0 ]] || die "$PROGRAM $COMMAND: '$dir/.gpg-id' está vazio"
	printf '%s\n' "${args[@]}"
}

_secrets_load() {
	local nome="$1" nomearq="${2:-.secrets.gpg}"
	local mapfile
	mapfile=$(_secrets_mapfile "$nome" "$nomearq") || exit 1
	[[ -f "$mapfile" ]] || \
		die "$PROGRAM $COMMAND: '$nome' ainda não tem '$nomearq' — crie uma entrada primeiro"

	$GPG -d "${GPG_OPTS[@]}" "$mapfile" 2>/dev/null || \
		die "$PROGRAM $COMMAND: falha ao descriptografar '$mapfile'"
}

# Cifra e salva um arquivo da identidade, reaproveitando GPG/GPG_OPTS e
# o git do pass. $4 é o nome do arquivo, default .secrets.gpg.
_secrets_save() {
	local nome="$1" conteudo="$2" msg="$3" nomearq="${4:-.secrets.gpg}"
	local dir
	dir=$(_secrets_resolve "$nome") || exit 1
	local mapfile="$dir/$nomearq"

	local -a recip=()
	local linha_recip
	while IFS= read -r linha_recip; do recip+=("$linha_recip"); done < <(_secrets_recipients "$nome") || exit 1

	set_git "$mapfile"
	printf '%s\n' "$conteudo" | $GPG -e "${recip[@]}" -o "$mapfile" "${GPG_OPTS[@]}" || \
		die "$PROGRAM $COMMAND: falha ao cifrar o mapa de '$nome'"
	chmod 640 "$mapfile" 2>/dev/null
	git_add_file "$mapfile" "$msg"
}

# ---------------------------------------------------------------------
# Comandos de consulta
# ---------------------------------------------------------------------

cmd_secrets_dir() {
	local nome="$1" bloco="$2"
	[[ -n "$bloco" ]] && _secrets_valid_token "$bloco" || \
		die "Usage: $PROGRAM $COMMAND <identidade> dir <bloco>"

	local content out
	content=$(_secrets_load "$nome") || exit 1
	local bloco_esc
	bloco_esc=$(_secrets_re_escape "$bloco")
	out=$(grep -E "^${bloco_esc}(/[^=]*)?[[:space:]]*=" <<< "$content")
	[[ -n "$out" ]] || die "$PROGRAM $COMMAND: nenhuma entrada sob '$bloco' no mapa de '$nome'"
	printf '%s\n' "$out"
}

cmd_secrets_count() {
	local nome="$1" bloco="$2"
	cmd_secrets_dir "$nome" "$bloco" | grep -c '='
}

cmd_secrets_word() {
	local nome="$1" termo="$2" ctx="${3:-0}"
	[[ -n "$termo" ]] || die "Usage: $PROGRAM $COMMAND <identidade> word <termo> [contexto]"
	[[ "$ctx" =~ ^[0-9]+$ ]] || die "$PROGRAM $COMMAND: contexto deve ser inteiro"

	local content
	content=$(_secrets_load "$nome") || exit 1

	grep -nE -C"$ctx" --color=auto -- "$termo" <<< "$content"
	local ret=$?
	case $ret in
		0) return 0 ;;
		1) die "$PROGRAM $COMMAND: nenhuma ocorrência de '$termo'" ;;
		*) die "$PROGRAM $COMMAND: erro durante a busca (grep retornou $ret)" ;;
	esac
}

cmd_secrets_edit() {
	local nome="$1"
	local mapfile
	mapfile=$(_secrets_mapfile "$nome") || exit 1
	command -v vim >/dev/null || die "$PROGRAM $COMMAND: vim não encontrado"

	if [[ ! -f "$mapfile" ]]; then
		echo "$PROGRAM $COMMAND: '$mapfile' ainda não existe — vim-gnupg vai pedir o destinatário GPG ao salvar (confirme que é o mesmo do .gpg-id local, ou use 'rebuild'/'add' para criar automaticamente)" >&2
	fi

	set_git "$mapfile"

	vim -- "$mapfile"
	local ret=$?

	if [[ -f "$mapfile" ]]; then
		local perms
		perms=$(stat -c '%a' "$mapfile")
		[[ "$perms" == "640" || "$perms" == "600" ]] || \
			echo "$PROGRAM $COMMAND: aviso — permissões de '$mapfile' mudaram para $perms, restaure para 640" >&2
		git_add_file "$mapfile" "Edit secrets map for $nome using ${EDITOR:-vi}."
	fi
	return "$ret"
}

# ---------------------------------------------------------------------
# Inserção manual de uma associação
# ---------------------------------------------------------------------

cmd_secrets_add() {
	local nome="$1" caminho="$2" nome_real="$3"
	[[ -n "$nome" && -n "$caminho" && -n "$nome_real" ]] || \
		die "Usage: $PROGRAM $COMMAND <identidade> add <caminho-relativo> <nome-real>"
	check_sneaky_paths "$caminho"
	_secrets_valid_token "$caminho" || die "$PROGRAM $COMMAND: caminho inválido"

	local dir
	dir=$(_secrets_resolve "$nome") || exit 1

	[[ -f "$dir/$caminho.gpg" ]] || \
		echo "$PROGRAM $COMMAND: aviso — '$caminho' não existe em '$dir' ainda; associação ficará órfã até a entrada real ser criada" >&2

	local content=""
	local mf
	mf=$(_secrets_mapfile "$nome") || exit 1
	[[ -f "$mf" ]] && { content=$(_secrets_load "$nome") || exit 1; }

	local caminho_esc
	caminho_esc=$(_secrets_re_escape "$caminho")
	if grep -qE "^${caminho_esc}[[:space:]]*=" <<< "$content"; then
		yesno "$PROGRAM $COMMAND: '$caminho' já tem associação em '$nome'. Sobrescrever?"
		content=$(grep -vE "^${caminho_esc}[[:space:]]*=" <<< "$content")
	fi

	content="$(printf '%s\n%s = %s\n' "$content" "$caminho" "$nome_real" | sed '/^$/d' | sort -u)"
	_secrets_save "$nome" "$content" "Add secrets association for $caminho in $nome."
}

# ---------------------------------------------------------------------
# Mask (.mask.gpg) — aliases de e-mail associados a diretórios,
# many-to-many: um alias pode valer para vários diretórios, e um
# diretório pode ter vários aliases. Sem chave única, diferente do
# .secrets.gpg (que é uma associação 1:1 por caminho de arquivo).
# ---------------------------------------------------------------------

cmd_secrets_mask_add() {
	local nome="$1" alias_email="$2" caminho_dir="$3"
	[[ -n "$nome" && -n "$alias_email" && -n "$caminho_dir" ]] || \
		die "Usage: $PROGRAM $COMMAND <identidade> mask add <alias-email> <caminho-dir>"
	check_sneaky_paths "$caminho_dir"
	_secrets_valid_token "$caminho_dir" || die "$PROGRAM $COMMAND: caminho de diretório inválido"

	local dir
	dir=$(_secrets_resolve "$nome") || exit 1

	[[ -d "$dir/$caminho_dir" ]] || \
		echo "$PROGRAM $COMMAND: aviso — '$caminho_dir' não é um diretório existente em '$dir' ainda" >&2

	local content=""
	local mf
	mf=$(_secrets_mapfile "$nome" .mask.gpg) || exit 1
	[[ -f "$mf" ]] && { content=$(_secrets_load "$nome" .mask.gpg) || exit 1; }

	content="$(printf '%s\n%s = %s\n' "$content" "$alias_email" "$caminho_dir" | sed '/^$/d' | sort -u)"
	_secrets_save "$nome" "$content" "Add mask association in $nome." .mask.gpg
}

cmd_secrets_mask_dir() {
	local nome="$1" caminho_dir="$2"
	[[ -n "$caminho_dir" ]] && _secrets_valid_token "$caminho_dir" || \
		die "Usage: $PROGRAM $COMMAND <identidade> mask dir <caminho-dir>"

	local content out
	content=$(_secrets_load "$nome" .mask.gpg) || exit 1
	local dir_esc
	dir_esc=$(_secrets_re_escape "$caminho_dir")
	out=$(grep -E "=[[:space:]]*${dir_esc}\$" <<< "$content")
	[[ -n "$out" ]] || die "$PROGRAM $COMMAND: nenhum alias associado a '$caminho_dir' no mapa de '$nome'"
	printf '%s\n' "$out"
}

cmd_secrets_mask_word() {
	local nome="$1" termo="$2" ctx="${3:-0}"
	[[ -n "$termo" ]] || die "Usage: $PROGRAM $COMMAND <identidade> mask word <termo> [contexto]"
	[[ "$ctx" =~ ^[0-9]+$ ]] || die "$PROGRAM $COMMAND: contexto deve ser inteiro"

	local content
	content=$(_secrets_load "$nome" .mask.gpg) || exit 1

	grep -nE -C"$ctx" --color=auto -- "$termo" <<< "$content"
	local ret=$?
	case $ret in
		0) return 0 ;;
		1) die "$PROGRAM $COMMAND: nenhuma ocorrência de '$termo'" ;;
		*) die "$PROGRAM $COMMAND: erro durante a busca (grep retornou $ret)" ;;
	esac
}

cmd_secrets_mask_list() {
	local nome="$1"
	_secrets_load "$nome" .mask.gpg
}

cmd_secrets_mask_edit() {
	local nome="$1"
	local mapfile
	mapfile=$(_secrets_mapfile "$nome" .mask.gpg) || exit 1
	command -v vim >/dev/null || die "$PROGRAM $COMMAND: vim não encontrado"

	if [[ ! -f "$mapfile" ]]; then
		echo "$PROGRAM $COMMAND: '$mapfile' ainda não existe — vim-gnupg vai pedir o destinatário GPG ao salvar" >&2
	fi

	set_git "$mapfile"
	vim -- "$mapfile"
	local ret=$?

	if [[ -f "$mapfile" ]]; then
		local perms
		perms=$(stat -c '%a' "$mapfile")
		[[ "$perms" == "640" || "$perms" == "600" ]] || \
			echo "$PROGRAM $COMMAND: aviso — permissões de '$mapfile' mudaram para $perms, restaure para 640" >&2
		git_add_file "$mapfile" "Edit mask map for $nome using ${EDITOR:-vi}."
	fi
	return "$ret"
}

cmd_secrets_mask() {
	local nome="$1"; shift
	local sub="$1"; shift 2>/dev/null
	case "$sub" in
		add)  cmd_secrets_mask_add "$nome" "$@" ;;
		dir)  cmd_secrets_mask_dir "$nome" "$@" ;;
		word) cmd_secrets_mask_word "$nome" "$@" ;;
		list) cmd_secrets_mask_list "$nome" "$@" ;;
		edit) cmd_secrets_mask_edit "$nome" "$@" ;;
		*) die "$PROGRAM $COMMAND: subcomando de mask desconhecido '$sub' (use: add|dir|word|edit|list)" ;;
	esac
}

# Audita o .mask.gpg contra a árvore real: cada linha aponta pra um
# DIRETÓRIO (não um arquivo), então a checagem é só "esse diretório
# ainda existe?". Somente leitura — nunca edita nem remove nada, só
# avisa. Roda dentro de check/rebuild, igual a checagem de colisão.
_secrets_check_mask_orphans() {
	local dir="$1"
	local mf="$dir/.mask.gpg"
	[[ -f "$mf" ]] || return 0

	local content
	content=$($GPG -d "${GPG_OPTS[@]}" "$mf" 2>/dev/null) || {
		echo "$PROGRAM $COMMAND: aviso — falha ao decifrar .mask.gpg para checagem de órfãos" >&2
		return 1
	}

	local -a orfas=()
	local linha alvo
	while IFS= read -r linha; do
		[[ "$linha" =~ ^([^=]+)=(.*)$ ]] || continue
		alvo="${BASH_REMATCH[2]# }"
		alvo="${alvo% }"
		[[ -n "$alvo" && -d "$dir/$alvo" ]] || orfas+=("$linha")
	done <<< "$content"

	if [[ ${#orfas[@]} -gt 0 ]]; then
		{
			echo "$PROGRAM $COMMAND: mask — entradas apontando para diretório que não existe mais:"
			printf '  %s\n' "${orfas[@]}"
		} >&2
	fi
}

# ---------------------------------------------------------------------
# Duplicatas de nome real (aviso, não bloqueia)
# ---------------------------------------------------------------------

_secrets_find_duplicates() {
	local content="$1"
	awk -F' = ' '
		$0 !~ / = / { next }
		{
			val = $0
			sub(/^[^=]+= */, "", val)
			gsub(/[[:space:]]+$/, "", val)
			key = $1
			gsub(/[[:space:]]+$/, "", key)
			if (val == "(pendente)") next
			count[val]++
			list[val] = (list[val] == "") ? key : list[val] "," key
		}
		END {
			for (v in count) if (count[v] > 1) print v "|" list[v]
		}
	' <<< "$content"
}

# ---------------------------------------------------------------------
# Colisão de nomes de identidade em qualquer lugar da árvore
# ---------------------------------------------------------------------

# Varre a árvore inteira em busca de identidades (dirs com .gpg-id)
# com o mesmo nome em profundidades diferentes. Detecta preventivamente
# — antes de alguém tentar usar o nome e esbarrar em _secrets_resolve.
_secrets_check_collisions() {
	local -A byname=()
	local d base
	while IFS= read -r -d '' d; do
		base="${d##*/}"
		byname["$base"]="${byname[$base]-}"$'\n'"$d"
	done < <(find "$PREFIX" -type d -exec test -f "{}/.gpg-id" \; -print0 2>/dev/null)

	local nome linhas count
	for nome in "${!byname[@]}"; do
		linhas="${byname[$nome]#$'\n'}"
		count=$(grep -c . <<< "$linhas")
		if [[ "$count" -gt 1 ]]; then
			{
				echo "$PROGRAM $COMMAND: aviso — nome de identidade '$nome' está duplicado na árvore:"
				sed 's/^/  /' <<< "$linhas"
			} >&2
		fi
	done
}

# ---------------------------------------------------------------------
# Scan da árvore real (compartilhado por rebuild e struct)
# ---------------------------------------------------------------------

# Lista os caminhos de codinome (sem .gpg) sob o diretório da
# identidade, parando ao encontrar outra identidade aninhada (não
# atravessa a fronteira de outro .gpg-id). Não decifra nada — é só
# estrutura de arquivo, que já é pública no disco de qualquer forma.
_secrets_scan() {
	local dir="$1"
	local f rel
	while IFS= read -r -d '' f; do
		rel="${f#"$dir"/}"
		rel="${rel%.gpg}"
		printf '%s\n' "$rel"
	done < <(find "$dir" -mindepth 1 \
	            \( -name '.gpg-id' -o -name '.secrets.gpg' -o -name '.mask.gpg' \) -prune -o \
	            -type d -exec test -f "{}/.gpg-id" \; -prune -o \
	            -type f -iname '*.gpg' -print0)
}

# Lista a estrutura real de codinomes de uma identidade — puro scan do
# disco, sem tocar no .secrets.gpg. Substitui o antigo "struct" fixo:
# em vez de uma tabela hardcoded no script, entrega o que já está
# publicamente visível via ls/tree, só organizado.
cmd_secrets_struct() {
	local nome="$1"
	local dir
	dir=$(_secrets_resolve "$nome") || exit 1

	local -a items=()
	local item
	while IFS= read -r item; do items+=("$item"); done < <(_secrets_scan "$dir" | sort)

	if [[ ${#items[@]} -eq 0 ]]; then
		echo "$PROGRAM $COMMAND: '$nome' não tem entradas ainda" >&2
		return 1
	fi
	printf '%s\n' "${items[@]}"
}

# ---------------------------------------------------------------------
# Rebuild reconciliador (scan da árvore real, sem overwrite cego)
# ---------------------------------------------------------------------

cmd_secrets_rebuild() {
	local nome="$1"; shift
	local auto_yes=0 prune=0 dry_run=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--yes) auto_yes=1; shift ;;
			--prune) prune=1; shift ;;
			--dry-run) dry_run=1; shift ;;
			*) die "$PROGRAM $COMMAND: opção desconhecida '$1'" ;;
		esac
	done

	_secrets_check_collisions

	local dir
	dir=$(_secrets_resolve "$nome") || exit 1

	_secrets_check_mask_orphans "$dir"

	local old_content=""
	local mf="$dir/.secrets.gpg"
	[[ -f "$mf" ]] && { old_content=$(_secrets_load "$nome") || exit 1; }

	declare -A old_map=()
	local linha
	while IFS= read -r linha; do
		[[ "$linha" =~ ^([^=]+)=(.*)$ ]] || continue
		local k="${BASH_REMATCH[1]% }"
		old_map["$k"]="${BASH_REMATCH[2]# }"
	done <<< "$old_content"

	# Varre a árvore real, parando ao encontrar outra identidade
	# aninhada (não atravessa a fronteira de outro .gpg-id).
	local -a found=()
	local item
	while IFS= read -r item; do found+=("$item"); done < <(_secrets_scan "$dir")

	local -a new_entries=() orphans=()
	local k f2 ainda
	for k in "${found[@]}"; do
		[[ -n "${old_map[$k]+x}" ]] || new_entries+=("$k")
	done
	for k in "${!old_map[@]}"; do
		ainda=0
		for f2 in "${found[@]}"; do [[ "$f2" == "$k" ]] && { ainda=1; break; }; done
		[[ $ainda -eq 0 ]] && orphans+=("$k")
	done

	local content="$old_content" nome_real caminho
	for caminho in "${new_entries[@]}"; do
		if [[ $auto_yes -eq 1 || $dry_run -eq 1 ]]; then
			nome_real="(pendente)"
		else
			read -r -p "Nome real para '$caminho'? " nome_real
			[[ -n "$nome_real" ]] || nome_real="(pendente)"
		fi
		content="$(printf '%s\n%s = %s' "$content" "$caminho" "$nome_real")"
	done

	if [[ ${#orphans[@]} -gt 0 ]]; then
		{
			echo "$PROGRAM $COMMAND: entradas órfãs (no mapa, não existem mais no disco):"
			printf '  %s\n' "${orphans[@]}"
		} >&2
		if [[ $prune -eq 1 && $dry_run -eq 0 ]]; then
			for caminho in "${orphans[@]}"; do
				content=$(grep -vFx "$caminho = ${old_map[$caminho]}" <<< "$content")
			done
			echo "$PROGRAM $COMMAND: órfãs removidas (--prune)" >&2
		else
			echo "$PROGRAM $COMMAND: mantidas — rode com --prune para remover" >&2
		fi
	fi

	content=$(sed '/^$/d' <<< "$content" | sort -u)

	local dupes
	dupes=$(_secrets_find_duplicates "$content")
	if [[ -n "$dupes" ]]; then
		echo "$PROGRAM $COMMAND: nomes reais duplicados (mesmo nome real em codinomes diferentes):" >&2
		while IFS='|' read -r val keys; do
			echo "  '$val' -> $keys" >&2
		done <<< "$dupes"
	fi

	echo "$PROGRAM $COMMAND: '$nome' — ${#new_entries[@]} novas, ${#orphans[@]} órfãs" >&2
	if [[ $dry_run -eq 1 ]]; then
		echo "$PROGRAM $COMMAND: --dry-run, nada foi salvo" >&2
		return 0
	fi

	_secrets_save "$nome" "$content" "Rebuild secrets map for $nome."
}

# ---------------------------------------------------------------------
# Geração de codinomes
# ---------------------------------------------------------------------

# Gera uma palavra-código pronunciável (consoante/vogal alternado),
# nada de ruído tipo "asdcf". Reaproveita o estilo do script original.
_secrets_generate_word() {
	local len="${1:-5}"
	local consonants="bcdfglmnprstvz"
	local vowels="aeiou"
	local word="" start i

	(( RANDOM % 2 == 0 )) && start=0 || start=1
	for (( i=0; i<len; i++ )); do
		if (( (i + start) % 2 == 0 )); then
			word+="${consonants:RANDOM % ${#consonants}:1}"
		else
			word+="${vowels:RANDOM % ${#vowels}:1}"
		fi
	done
	printf '%s\n' "${word^}"
}

# Gera um codinome livre (sem colisão) dentro de <identidade>/<bloco>.
# Colisão só importa DENTRO da mesma identidade — dois arquivos com o
# mesmo nome na mesma pasta seria sobrescrita real. Repetir o nome
# entre identidades diferentes é aceitável (trade-off aceito: quebrar
# uma árvore não compromete a associação de serviço das demais).
_secrets_free_codename() {
	local dir="$1" bloco="$2" len="$3"
	local tentativas=0 palavra caminho

	while (( tentativas < 50 )); do
		palavra=$(_secrets_generate_word "$len")
		if [[ -n "$bloco" && "$bloco" != "." ]]; then
			caminho="$bloco/$palavra"
		else
			caminho="$palavra"
		fi
		[[ -e "$dir/$caminho.gpg" || -e "$dir/$caminho" ]] || { printf '%s\n' "$caminho"; return 0; }
		(( tentativas++ ))
	done
	die "$PROGRAM $COMMAND: não foi possível gerar um codinome livre após $tentativas tentativas"
}

# Modo manual — só sugere nome(s) livre(s), não cria nada. Útil quando
# você quer decidir na hora o que fazer com o nome (criar via 'pass
# insert', usar em outro lugar, etc).
cmd_secrets_namegen() {
	local nome="$1"; shift
	local bloco="." len=5 qtd=1
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-n) len="$2"; shift 2 ;;
			-u) qtd="$2"; shift 2 ;;
			*) bloco="$1"; shift ;;
		esac
	done
	[[ "$len" =~ ^[0-9]+$ && "$len" -gt 0 ]] || die "$PROGRAM $COMMAND: tamanho inválido"
	[[ "$qtd" =~ ^[0-9]+$ && "$qtd" -gt 0 ]] || die "$PROGRAM $COMMAND: quantidade inválida"

	local dir
	dir=$(_secrets_resolve "$nome") || exit 1

	local i
	for (( i=0; i<qtd; i++ )); do
		_secrets_free_codename "$dir" "$bloco" "$len"
	done
}

# Modo automatizado — gera um codinome livre E já cria a entrada real
# via cmd_generate (a função de verdade do próprio pass, com
# GPG/git/clipboard nativos, não uma reimplementação). NÃO registra a
# associação no .secrets.gpg — isso continua manual via 'add', de
# propósito: você só sabe o nome real depois de decidir o que vai
# guardar ali.
cmd_secrets_generate() {
	local nome="$1"; shift
	local bloco="${1:-.}"
	[[ $# -gt 0 ]] && shift

	local len="$GENERATED_LENGTH"
	if [[ "$1" =~ ^[0-9]+$ ]]; then
		len="$1"
		shift
	fi
	# "$@" daqui pra frente são só flags remanescentes do pass generate
	# (--no-symbols, --clip, --qrcode, etc), repassadas como estão.

	[[ -n "$bloco" && "$bloco" != "." ]] && { _secrets_valid_token "$bloco" || die "$PROGRAM $COMMAND: bloco inválido"; }

	local dir
	dir=$(_secrets_resolve "$nome") || exit 1

	local caminho_relativo
	caminho_relativo=$(_secrets_free_codename "$dir" "$bloco" 5)

	local caminho_pass="${dir#$PREFIX/}/$caminho_relativo"

	cmd_generate "$@" "$caminho_pass" "$len"

	echo "$PROGRAM $COMMAND: codinome gerado — '$caminho_relativo' (em '$nome')" >&2
	echo "$PROGRAM $COMMAND: para registrar a associação: $PROGRAM $COMMAND $nome add '$caminho_relativo' '<nome real>'" >&2
}

# ---------------------------------------------------------------------
# Dispatcher (arquivo é sourced pelo pass com "$@" = args após "secrets")
# ---------------------------------------------------------------------

IDENTIDADE="$1"
shift
SUBCMD="$1"
shift 2>/dev/null

case "$SUBCMD" in
	dir)      cmd_secrets_dir "$IDENTIDADE" "$@" ;;
	word)     cmd_secrets_word "$IDENTIDADE" "$@" ;;
	count)    cmd_secrets_count "$IDENTIDADE" "$@" ;;
	edit)     cmd_secrets_edit "$IDENTIDADE" "$@" ;;
	add)      cmd_secrets_add "$IDENTIDADE" "$@" ;;
	rebuild)  cmd_secrets_rebuild "$IDENTIDADE" "$@" ;;
	check)    cmd_secrets_rebuild "$IDENTIDADE" --dry-run "$@" ;;
	struct)   cmd_secrets_struct "$IDENTIDADE" "$@" ;;
	mask)     cmd_secrets_mask "$IDENTIDADE" "$@" ;;
	namegen)  cmd_secrets_namegen "$IDENTIDADE" "$@" ;;
	generate) cmd_secrets_generate "$IDENTIDADE" "$@" ;;
	version|--version) cmd_secrets_version ;;
	""|-h|--help|help) cmd_secrets_usage; exit 1 ;;
	*) die "$PROGRAM $COMMAND: comando desconhecido '$SUBCMD' (use: dir|word|count|edit|check|struct|add|rebuild|mask|namegen|generate)" ;;
esac
exit 0
