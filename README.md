# pass-secrets

Uma extensão para o [password-store (pass)](https://www.passwordstore.org/) que obscurece a árvore de diretórios e nomes de serviços mantendo a estrutura original do `pass`. 

Diferente do `pass-tomb` (que necessita de volumes criptografados via Loopback e privilégios de superusuário), o **pass-secrets** utiliza mapeamentos criptografados (`.secrets.gpg` e `.mask.gpg`) baseados na chave GPG de cada diretório.

---

## 💡 Como Funciona?

No `pass` tradicional, os nomes de pastas e arquivos são visíveis no sistema de arquivos. O **pass-secrets** permite que você renomeie subdiretórios e entradas reais para codinomes aleatórios (ex: `z8x9/k2p.gpg`) e mantenha um mapa criptografado associando o codinome ao serviço real.

### 🛡️ Identidades e Isolamento de Confiança

Uma **identidade** é qualquer diretório na árvore do `pass` que possua seu próprio arquivo `.gpg-id`, independente da profundidade.

* **Fronteira de Confiança:** Uma identidade aninhada dentro de outra **NÃO herda** as chaves da identidade pai.
* **Isolamento Total:** Se a chave da identidade pai for comprometida, o conteúdo da identidade filha permanece seguro.
* **Unicidade de Nome:** O nome da pasta da identidade deve ser único em toda a árvore do `pass`.

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

Todos os comandos seguem a sintaxe: `pass secrets <identidade> <subcomando> [argumentos]`

### 🔍 Consultas no Mapa (`.secrets.gpg`)

| Comando | Descrição |
| :--- | :--- |
| `pass secrets <id> dir <bloco>` | Lista entradas cujo caminho começa com o bloco informado. |
| `pass secrets <id> word <termo> [contexto]` | Busca um termo no mapa visualizando linhas de contexto (`grep -C`). |
| `pass secrets <id> count <bloco>` | Retorna a contagem de entradas sob o bloco especificado. |
| `pass secrets <id> struct` | Exibe a estrutura real dos codinomes em disco (sem descriptografar). |

### ✏️ Gerenciamento e Reconciliação

| Comando | Descrição |
| :--- | :--- |
| `pass secrets <id> add <caminho> <nome-real>` | Associa manualmente um codinome a um nome real. |
| `pass secrets <id> edit` | Abre o arquivo `.secrets.gpg` no `vim` (requer `vim-gnupg`). |
| `pass secrets <id> check` | Audita o mapa em relação ao disco (somente leitura / `--dry-run`). |
| `pass secrets <id> rebuild [--yes] [--prune]` | Varre o disco, detecta novas entradas e reconcilia o mapa. |

* **Flags do `rebuild`:**
  * `--yes`: Não pergunta interativamente o nome real para novas entradas (insere `(pendente)`).
  * `--prune`: Remove entradas órfãs do mapa (entradas que não existem mais no disco).

### 🎭 Gerenciamento de Aliases e Máscaras (`.mask.gpg`)

O mapa `.mask.gpg` permite associar *aliases* (ex: e-mails descartáveis) a diretórios em uma relação *muitos-para-muitos* (*many-to-many*).

| Comando | Descrição |
| :--- | :--- |
| `pass secrets <id> mask add <alias> <dir>` | Associa um alias de e-mail a um diretório. |
| `pass secrets <id> mask dir <dir>` | Lista todos os aliases associados a um diretório. |
| `pass secrets <id> mask word <termo> [ctx]` | Busca por um termo ou alias dentro do mapa de máscaras. |
| `pass secrets <id> mask list` | Exibe todo o conteúdo descriptografado do arquivo `.mask.gpg`. |

---

## 📂 Formato dos Arquivos Internos

Os arquivos `.secrets.gpg` e `.mask.gpg` são mantidos criptografados em disco usando a chave GPG definida no `.gpg-id` local.

* **Formato de `.secrets.gpg`** (associação 1:1 por caminho):
  ```text
  a1/b2 = Servidor Produção - SSH
  a1/c3 = E-mail Corporativo
  ```

* **Formato de `.mask.gpg`** (associação N:N por alias/diretório):
  ```text
  alias1@domain.com = servicos/financeiro
  alias2@domain.com = servicos/financeiro
  ```

---

## 🔒 Permissões e Segurança

* O script força e valida permissões estritas `640` ou `600` em todos os arquivos de mapeamento criptografados.
* Integração nativa com o Git do `pass`: todas as modificações via script geram commits automáticos no repositório.
* Todas as entradas do usuário passam por checagens de validação de *path traversal* (`check_sneaky_paths`) e sanitização de tokens.

---

## 📄 Licença

Este projeto é disponibilizado sob a mesma licença do projeto [password-store](https://www.passwordstore.org/) (GPLv2+).
