# pass-secrets

Uma extensão para o [password-store (pass)](https://www.passwordstore.org/) que obscurece a árvore de diretórios e nomes de serviços mantendo a estrutura original do `pass`.

Diferente do `pass-tomb` (que necessita de volumes criptografados via Loopback e privilégios de superusuário), o **pass-secrets** utiliza mapeamentos criptografados (`.secrets.gpg` e `.mask.gpg`) baseados na chave GPG de cada diretório. Os serviços e pastas usam codinomes aleatórios, e a associação real é guardada no mapa por identidade.

---

## 💡 Como Funciona?

No `pass` tradicional, os nomes de pastas e arquivos são visíveis no sistema de arquivos. O **pass-secrets** permite que você renomeie subdiretórios e entradas reais para codinomes aleatórios (ex: `z8x9/k2p.gpg`) e mantenha um mapa criptografado associando o codinome ao serviço real.

### 🛡️ Identidades e Isolamento de Confiança

Uma **identidade** é qualquer diretório na árvore do `pass` que possua seu próprio arquivo `.gpg-id`, independente da profundidade. Nomes de identidade devem ser únicos em toda a árvore. Dois diretórios com `.gpg-id` e o mesmo nome tornam o comando ambíguo e são recusados.

* **Fronteira de Confiança:** Uma identidade aninhada dentro de outra **NÃO herda** as chaves da identidade pai.
* **Isolamento Total:** Comprometer a chave da identidade pai não expõe o conteúdo da filha.

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
*(Instalação conforme detalhada no repositório original.)*

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

### ✏️ Gerenciamento e Reconciliação

| Comando | Descrição |
| :--- | :--- |
| `pass secrets <id> add <caminho>` | Associa manualmente um codinome já existente. O nome real é pedido via prompt, nunca por argumento, para evitar exposição no histórico do shell. |
| `pass secrets <id> edit` | Edita o `.secrets.gpg` decifrando para um arquivo temporário na memória (via `/dev/shm`), abre com o seu `$EDITOR` e recifra. Não depende de ferramentas de terceiros (o suporte restrito via `vim-gnupg` foi removido). |
| `pass secrets <id> check` | Audita o mapa contra a árvore real de arquivos como somente leitura. |
| `pass secrets <id> rebuild [--yes] [--prune]` | Varre a árvore real e reconcilia o mapa. |

* **Flags do `rebuild`:**
  * `--yes`: Não pergunta o nome real para novas entradas (insere como `(pendente)`).
  * `--prune`: Remove entradas órfãs do mapa.

### 🔐 Geração de Codinomes

| Comando | Descrição |
| :--- | :--- |
| `pass secrets <id> namegen [bloco] [-n tamanho] [-u quantidade]` | Sugere codinomes livres de um tamanho especificado, sem criar arquivos. Checa colisões apenas dentro da mesma identidade. |
| `pass secrets <id> generate [bloco] [tamanho] [flags]` | Gera um codinome livre e já cria a entrada real via comando nativo `pass generate` (repassando as `[flags]`). Não registra a associação de nome, exigindo o uso de `add` posteriormente. Blocos que atravessam identidades aninhadas são recusados para evitar uso acidental da chave GPG errada. |

### 🎭 Gerenciamento de Aliases e Máscaras (`.mask.gpg`)

O mapa `.mask.gpg` permite associar *aliases* (ex: e-mails descartáveis) a diretórios em uma relação *muitos-para-muitos* (*many-to-many*). 

| Comando | Descrição |
| :--- | :--- |
| `pass secrets <id> mask add <dir>` | Associa um alias de e-mail a um diretório. O alias é pedido via prompt interativo em vez de argumento. |
| `pass secrets <id> mask dir <dir>` | Lista os aliases associados a um diretório. |
| `pass secrets <id> mask word <termo> [ctx]` | Busca um alias ou diretório no `.mask.gpg`. |
| `pass secrets <id> mask list` | Lista todo o conteúdo do `.mask.gpg`. |
| `pass secrets <id> mask edit` | Edita o `.mask.gpg` utilizando o mesmo mecanismo seguro e sem dependências externas do comando `edit` principal. |

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

* O script audita o sistema de arquivos e exige permissões estritas `600` nos arquivos de mapa criptografados (não aceita `640`).
* O ciclo de vida dos arquivos temporários nas edições (`edit` e `mask edit`) é inteiramente gerenciado pela extensão, limpando o rastro com segurança (via `shred`/`rm` atrelado a um `trap` do shell) sem depender de plugins como o `vim-gnupg`.
* O script recusa caminhos e blocos de geração de senhas que atravessam diretórios de identidades aninhadas, garantindo rigorosamente que arquivos nunca sejam cifrados pela chave de uma identidade indesejada.
* Integração nativa com o Git do `pass`: todas as modificações nos mapas via script geram commits automáticos no repositório.
* Todas as entradas do usuário passam por checagens de validação de *path traversal* (`check_sneaky_paths`) e sanitização de tokens.

---

## 📄 Licença

Este projeto é disponibilizado sob a mesma licença do projeto [password-store](https://www.passwordstore.org/) (GPLv2+).
