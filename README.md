# pass-secrets
[ENGLISH VERSION](https://github.com/HGBits/Pass-Secrets/blob/184cfcfbdbc8913330866cc13b272114225397f2/README-EN.md)

Uma extensão para o [password-store (pass)](https://www.passwordstore.org/) que obscurece a árvore de diretórios e nomes de serviços mantendo a estrutura original do `pass`.

Diferente do `pass-tomb` (que necessita de volumes criptografados via Loopback e privilégios de superusuário), o **pass-secrets** utiliza mapeamentos criptografados (`.secrets.gpg` e `.mask.gpg`) baseados na chave GPG de cada diretório. Os serviços e pastas usam codinomes aleatórios, e a associação real é guardada no mapa por identidade.

**Versão atual: 2.5.1**

---

## 💡 Como Funciona?

No `pass` tradicional, os nomes de pastas e arquivos são visíveis no sistema de arquivos. O **pass-secrets** permite que você renomeie subdiretórios e entradas reais para codinomes aleatórios (ex: `Zovar/Kelip.gpg`) e mantenha um mapa criptografado associando o codinome ao serviço real.

### 🛡️ Identidades e Isolamento de Confiança

Uma **identidade** é qualquer diretório na árvore do `pass` que possua seu próprio arquivo `.gpg-id`, independente da profundidade. Nomes de identidade devem ser únicos em toda a árvore. Dois diretórios com `.gpg-id` e o mesmo nome tornam o comando ambíguo e são recusados.

* **Fronteira de Confiança:** Uma identidade aninhada dentro de outra **NÃO herda** as chaves da identidade pai.
* **Isolamento Total:** Comprometer a chave da identidade pai não expõe o conteúdo da filha.
* **Proteção contra cruzamento de fronteira:** `generate` e `namegen` recusam qualquer bloco/caminho que atravesse o diretório de outra identidade aninhada — sem essa checagem, uma senha poderia ser cifrada com a chave da identidade errada.

### 🔑 Assinatura de `.gpg-id` (opcional)

Se `PASSWORD_STORE_SIGNING_KEY` estiver configurado (mesma variável usada pelo `pass` nativo), o pass-secrets exige um `.gpg-id.sig` válido antes de aceitar os destinatários de uma identidade — bloqueando substituição ou injeção de chave no `.gpg-id`. Sem a variável configurada, o comportamento é idêntico ao `pass` puro (sem verificação).

---

## 🛠️ Instalação

```bash
# 1. Crie o diretório de extensões do pass (caso não exista)
mkdir -p "${PASSWORD_STORE_EXTENSIONS_DIR:-$HOME/.password-store/.extensions}"

# 2. Copie o script para a pasta de extensões
cp secrets.bash "${PASSWORD_STORE_EXTENSIONS_DIR:-$HOME/.password-store/.extensions}/secrets.bash"

# 3. Torne o script executável
chmod +x "${PASSWORD_STORE_EXTENSIONS_DIR:-$HOME/.password-store/.extensions}/secrets.bash"

# 4. Habilite extensões no seu shell (.bashrc, .zshrc, etc.)
export PASSWORD_STORE_ENABLE_EXTENSIONS=true
```

---

## 🚀 Uso e Comandos

Todos os comandos seguem a sintaxe: `pass secrets <identidade> <subcomando> [argumentos]`.

### 🔍 Consultas no Mapa (`.secrets.gpg`)

| Comando | Descrição |
| :--- | :--- |
| `pass secrets <id> dir <bloco>` | Lista entradas cujo caminho começa com o bloco informado. |
| `pass secrets <id> word <termo> [contexto]` | Busca um termo no mapa visualizando linhas de contexto (`grep -C`). |
| `pass secrets <id> count <bloco>` | Retorna a contagem de entradas sob o bloco especificado. |
| `pass secrets <id> struct` | Exibe a estrutura real de codinomes em disco via scan (sem decifrar). |
| `pass secrets <id> version` | Exibe a versão instalada da extensão. |

### ✏️ Gerenciamento e Reconciliação

| Comando | Descrição |
| :--- | :--- |
| `pass secrets <id> add <caminho>` | Associa manualmente um codinome já existente. O nome real é pedido via prompt, nunca por argumento, para evitar exposição no histórico do shell. |
| `pass secrets <id> edit` | Edita o `.secrets.gpg` decifrando para um arquivo temporário na memória (via `/dev/shm`), abre com o seu `$EDITOR` e recifra. Não depende de ferramentas de terceiros (o suporte via `vim-gnupg` foi removido). |
| `pass secrets <id> check` | Audita o mapa contra a árvore real de arquivos, como somente leitura (equivale a `rebuild --dry-run`). Além de novas/órfãs, reporta colisão global de nomes de identidade, entradas de `mask` apontando pra diretório inexistente, e nomes reais duplicados entre codinomes diferentes. |
| `pass secrets <id> rebuild [--yes] [--prune]` | Varre a árvore real e reconcilia o mapa. |

* **Flags do `rebuild`:**
  * `--yes`: Não pergunta o nome real para novas entradas (insere como `(pendente)`).
  * `--prune`: Remove entradas órfãs do mapa.

### 🔐 Geração de Codinomes

| Comando | Descrição |
| :--- | :--- |
| `pass secrets <id> namegen [bloco] [-n tamanho] [-u quantidade]` | Sugere codinomes livres de um tamanho especificado, sem criar arquivos. Checa colisões apenas dentro da mesma identidade. Blocos que atravessam identidades aninhadas são recusados, mesma proteção do `generate` abaixo. |
| `pass secrets <id> generate [bloco] [tamanho] [flags]` | Gera um codinome livre e já cria a entrada real via comando nativo `pass generate` (repassando as `[flags]`). Não registra a associação de nome, exigindo o uso de `add` posteriormente. Blocos que atravessam identidades aninhadas são recusados para evitar cifrar com a chave GPG errada. |

### 🎭 Gerenciamento de Aliases e Máscaras (`.mask.gpg`)

O mapa `.mask.gpg` permite associar *aliases* (ex: e-mails descartáveis) a diretórios em uma relação *muitos-para-muitos* (*many-to-many*).

| Comando | Descrição |
| :--- | :--- |
| `pass secrets <id> mask add <dir>` | Associa um alias de e-mail a um diretório. O alias é pedido via prompt interativo em vez de argumento. |
| `pass secrets <id> mask dir <dir>` | Lista os aliases associados a um diretório. |
| `pass secrets <id> mask word <termo> [ctx]` | Busca um alias ou diretório no `.mask.gpg`. |
| `pass secrets <id> mask list` | Lista todo o conteúdo do `.mask.gpg`. |
| `pass secrets <id> mask edit` | Edita o `.mask.gpg` utilizando o mesmo mecanismo seguro do comando `edit` principal. |

---

## ⚠️ Comportamento em contexto não-interativo (scripts, cron, automação)

O nome real (`add`) e o alias (`mask add`) **nunca são aceitos como argumento** — só via prompt, para não ficarem em `~/.bash_history` ou visíveis via `ps aux`. Isso tem uma consequência direta em automação: onde o script precisaria de uma confirmação humana real, ele **recusa prosseguir** em vez de assumir uma resposta padrão silenciosamente.

* `pass secrets <id> add <caminho>` sobre um caminho **já associado**: exige confirmação interativa (`[y/N]`). Fora de um terminal, é **recusado** — nunca sobrescreve silenciosamente.
* `pass secrets <id> rebuild` **sem** `--yes`: pergunta o nome real de cada entrada nova. Se a entrada padrão terminar (EOF) antes de responder, o comando **morre com erro** em vez de gravar `(pendente)` silenciosamente — evita confundir "ninguém respondeu" com "usuário aceitou o padrão". Use `--yes` explicitamente para automação.
* `pass secrets <id> edit` / `mask edit`: se a cifragem falhar (ex.: `.gpg-id` corrompido ou apontando pra chave inexistente) e a entrada não for interativa, o comando morre imediatamente em vez de ficar tentando de novo indefinidamente.

Em todos os três casos, o comportamento interativo normal (perguntar e esperar sua resposta num terminal de verdade) não muda em nada.

---

## 📂 Formato dos Arquivos Internos

Os arquivos `.secrets.gpg` e `.mask.gpg` são mantidos criptografados em disco usando a chave GPG definida no `.gpg-id` local. O formato em texto plano, antes da cifra, segue:

* **Formato de `.secrets.gpg`** (associação 1:1 por caminho):
  ```text
  <caminho-do-codinome-relativo-a-identidade> = <nome real / descrição>
  ```
  *(Exemplo: `a1/b2 = Servidor Produção - SSH`)*

* **Formato de `.mask.gpg`** (associação N:N por alias/diretório):
  ```text
  <alias> = <caminho-dir>
  ```
  *(Exemplo: `alias1@domain.com = servicos/financeiro`)*

---

## 🔒 Permissões e Segurança

* O script audita o sistema de arquivos e exige permissão **exatamente `600`** nos arquivos de mapa criptografados (não aceita `640` nem qualquer outro valor).
* O ciclo de vida dos arquivos temporários nas edições (`edit` e `mask edit`) é inteiramente gerenciado pela extensão, limpando o rastro com segurança (via `shred`/`rm` atrelado a um `trap` do shell) sem depender de plugins como o `vim-gnupg`.
* O script recusa caminhos e blocos de geração de senhas que atravessam diretórios de identidades aninhadas, garantindo que arquivos nunca sejam cifrados pela chave de uma identidade indesejada.
* Integração nativa com o Git do `pass`: todas as modificações nos mapas via script geram commits automáticos no repositório.
* Todas as entradas do usuário passam por checagens de validação de *path traversal* (`check_sneaky_paths`) e sanitização de tokens.

---

## 📄 Licença

Este projeto é disponibilizado sob a mesma licença do projeto [password-store](https://www.passwordstore.org/) (GPLv2+).
