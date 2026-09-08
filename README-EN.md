# pass-secrets
[VERSÃO EM PORTUGUÊS](README.md)

An extension for [password-store (pass)](https://www.passwordstore.org/) that obscures the directory tree and service names while keeping `pass`'s original structure.

Unlike `pass-tomb` (which requires encrypted volumes via Loopback and superuser privileges), **pass-secrets** uses encrypted mappings (`.secrets.gpg` and `.mask.gpg`) based on the GPG key of each directory. Services and folders use random codenames, and the real association is kept in the map per identity.

**Current version: 2.6.0**

---

## 💡 How Does It Work?

In traditional `pass`, folder and file names are visible on the filesystem. **pass-secrets** lets you rename subdirectories and real entries to random codenames (e.g. `Zovar/Kelip.gpg`) and keep an encrypted map associating the codename with the real service.

### 🛡️ Identities and Trust Isolation

An **identity** is any directory in the `pass` tree that has its own `.gpg-id` file, regardless of depth. Identity names must be unique across the whole tree. Two directories with a `.gpg-id` and the same name make the command ambiguous and are refused.

* **Trust Boundary:** An identity nested inside another does **NOT inherit** the parent identity's keys.
* **Total Isolation:** Compromising the parent identity's key does not expose the child's contents.
* **Boundary-crossing protection:** `generate` and `namegen` refuse any block/path that crosses into another nested identity's directory — without this check, a password could end up encrypted with the wrong identity's key.

### 🔑 `.gpg-id` Signing (optional)

If `PASSWORD_STORE_SIGNING_KEY` is set (the same variable used by native `pass`), pass-secrets requires a valid `.gpg-id.sig` before accepting an identity's recipients — blocking key substitution or injection in the `.gpg-id`. Without the variable set, the behavior is identical to plain `pass` (no verification).

---

## 🛠️ Installation

```bash
# 1. Create the pass extensions directory (if it doesn't exist)
mkdir -p "${PASSWORD_STORE_EXTENSIONS_DIR:-$HOME/.password-store/.extensions}"

# 2. Copy the script into the extensions folder
cp secrets.bash "${PASSWORD_STORE_EXTENSIONS_DIR:-$HOME/.password-store/.extensions}/secrets.bash"

# 3. Make the script executable
chmod +x "${PASSWORD_STORE_EXTENSIONS_DIR:-$HOME/.password-store/.extensions}/secrets.bash"

# 4. Enable extensions in your shell (.bashrc, .zshrc, etc.)
export PASSWORD_STORE_ENABLE_EXTENSIONS=true
```

---

## 🚀 Usage and Commands

All commands follow this syntax: `pass secrets <identity> <subcommand> [arguments]`.

### 🔍 Map Queries (`.secrets.gpg`)

| Command | Description |
| :--- | :--- |
| `pass secrets <id> dir <block>` | Lists entries whose path starts with the given block. |
| `pass secrets <id> word <term> [context]` | Searches for a term in the map, showing context lines (`grep -C`). |
| `pass secrets <id> count <block>` | Returns the number of entries under `<block>`. |
| `pass secrets <id> struct` | Shows the real codename structure on disk via a scan (without decrypting). |
| `pass secrets <id> version` | Shows the installed extension version. |

### ✏️ Management and Reconciliation

| Command | Description |
| :--- | :--- |
| `pass secrets <id> add <path>` | Manually associates an already-existing codename. The real name is requested via prompt, never as an argument, to avoid exposure in shell history. |
| `pass secrets <id> edit` | Edits `.secrets.gpg` by decrypting it to a temporary file in memory (via `/dev/shm`), opening it with your `$EDITOR`, and re-encrypting it. Does not depend on third-party tools (the old `vim-gnupg` support was removed). |
| `pass secrets <id> check` | Audits the map against the real file tree, read-only (equivalent to `rebuild --dry-run`). Besides new/orphaned entries, it also reports global identity-name collisions, `mask` entries pointing to a nonexistent directory, and duplicate real names across different codenames. |
| `pass secrets <id> rebuild [--yes] [--prune]` | Scans the real tree and reconciles the map. |

* **`rebuild` flags:**
  * `--yes`: Doesn't ask for the real name of new entries (inserts them as `(pending)`).
  * `--prune`: Removes orphaned entries from the map.

### 🔐 Codename Generation

| Command | Description |
| :--- | :--- |
| `pass secrets <id> namegen [block] [-n length] [-u count]` | Suggests free codename(s) of a given length, without creating any files. Collisions are checked only within the same identity. Blocks that cross into a nested identity are refused, same protection as `generate` below. |
| `pass secrets <id> generate [block] [length] [flags]` | Generates a free codename and immediately creates the real entry via `pass`'s native `generate` command (passing through `[flags]`). Does not register the name association — use `add` afterward. Blocks that cross into a nested identity are refused, to avoid encrypting with the wrong GPG key. |

### 🎭 Alias and Mask Management (`.mask.gpg`)

The `.mask.gpg` map lets you associate *aliases* (e.g. disposable emails) with directories in a *many-to-many* relationship.

| Command | Description |
| :--- | :--- |
| `pass secrets <id> mask add <dir>` | Associates an email alias with a directory. The alias is requested via an interactive prompt instead of an argument. |
| `pass secrets <id> mask dir <dir>` | Lists the aliases associated with a directory. |
| `pass secrets <id> mask word <term> [ctx]` | Searches for a term or directory inside `.mask.gpg`. |
| `pass secrets <id> mask list` | Lists the entire decrypted content of `.mask.gpg`. |
| `pass secrets <id> mask edit` | Edits `.mask.gpg` using the same secure mechanism as the main `edit` command. |

---

## ⚠️ Behavior in Non-Interactive Contexts (scripts, cron, automation)

The real name (`add`) and the alias (`mask add`) are **never accepted as an argument** — only via prompt, so they never end up in `~/.bash_history` or visible via `ps aux`. This has a direct consequence for automation: wherever the script would need a genuine human confirmation, it **refuses to proceed** instead of silently assuming a default answer.

* `pass secrets <id> add <path>` on a path that's **already associated**: requires interactive confirmation (`[y/N]`). Outside a terminal, it's **refused** — it never silently overwrites.
* `pass secrets <id> rebuild` **without** `--yes`: asks for the real name of each new entry. If standard input reaches EOF before answering, the command **dies with an error** instead of silently writing `(pending)` — this avoids confusing "nobody answered" with "the user accepted the default". Use `--yes` explicitly for automation.
* `pass secrets <id> edit` / `mask edit`: if encryption fails (e.g. a corrupted `.gpg-id` or one pointing to a nonexistent key) and the input isn't interactive, the command dies immediately instead of retrying forever.

In all three cases, normal interactive behavior (asking and waiting for your answer in a real terminal) doesn't change at all.

---

## 📂 Internal File Format

`.secrets.gpg` and `.mask.gpg` are kept encrypted on disk using the GPG key defined in the local `.gpg-id`. The plaintext format, before encryption, is:

* **`.secrets.gpg` format** (1:1 association per path):
  ```text
  <codename-path-relative-to-identity> = <real name / description>
  ```
  *(Example: `a1/b2 = Production Server - SSH`)*

* **`.mask.gpg` format** (N:N association by alias/directory):
  ```text
  <alias> = <dir-path>
  ```
  *(Example: `alias1@domain.com = finance/services`)*

---

## 🔒 Permissions and Security

* The script audits the filesystem and requires **exactly `600`** permissions on the encrypted map files (it does not accept `640` or any other value).
* The lifecycle of temporary files during edits (`edit` and `mask edit`) is entirely managed by the extension, cleaning up securely (via `shred`/`rm` tied to a shell `trap`) without depending on plugins like `vim-gnupg`.
* The script refuses password-generation paths/blocks that cross into nested identity directories, ensuring files are never encrypted with an unintended identity's key.
* Native Git integration via `pass`: every map modification made through the script generates an automatic commit in the repository.
* All user input goes through *path traversal* validation (`check_sneaky_paths`) and token sanitization.

---

## 🤝 How to Help / How to Contribute

### Translating or fixing a language

Every pass-secrets message lives in simple source files, one per language, in the [`i18n/`](i18n/) folder (`pt.json`, `en.json`, `es.json`, `ru.json`). These are plain JSON files — you don't need to know bash or understand the script internals to translate.

**To fix an existing translation:**
1. Open that language's `.json` in any text editor.
2. Edit the text between quotes for the key you want to fix. Keep the same number of `%s` as the original — those are placeholders filled in at runtime (identity name, path, etc.).
3. Run `python3 tools/gen-i18n.py secrets.bash` to apply the change inside the script.
4. Run `bash -n secrets.bash` to confirm the syntax is still valid.
5. Open a Pull Request.

**To add a language that doesn't exist yet:**
1. Copy `i18n/en.json` to `i18n/<language-code>.json` (e.g. `i18n/fr.json` for French) as a starting point.
2. Translate the values — it doesn't have to be all at once. Any key you leave untranslated automatically falls back to English (and then Portuguese) until someone completes it.
3. Don't forget the special `_usage_full` key — it's the full `--help` text for that language. Use `{PROG}` in place of "pass secrets" (this gets substituted automatically at runtime).
4. Run `python3 tools/gen-i18n.py secrets.bash` — it detects the new file on its own, nothing else needs editing.
5. Test with `PASS_SECRETS_LANG=<code> pass secrets <identity> ...` and confirm translated keys come out right and missing ones fall back correctly.
6. Open a Pull Request with the new `.json` and the regenerated `secrets.bash`.

None of these steps require any bash knowledge. `tools/gen-i18n.py` only needs Python 3 (no external dependencies) and is the only tool needed to go from a translated `.json` to the final `secrets.bash`.

### Other ways to contribute

* **Report bugs and unexpected behavior** — especially in non-interactive contexts (scripts, cron), boundaries between nested identities, and anything that looks like an uncovered edge case.
* **Review security** — the project's entire threat model (per-identity isolation, `.gpg-id` signature verification, path traversal validation) is open to scrutiny; a PR with practical proof of a flaw (not just theory) is always welcome.
* **Review existing translations** — even without being an "official" translator for a language, flagging an odd or incorrect translation via an issue already helps.

---

## 📄 License

This project is distributed under the same license as [password-store](https://www.passwordstore.org/) (GPLv2+).
