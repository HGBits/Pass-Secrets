pass-secrets

An extension for password-store (pass)
 that obscures the directory tree and service names while preserving the original pass structure.

Unlike pass-tomb (which requires encrypted volumes via Loopback and superuser privileges), pass-secrets uses encrypted mappings (.secrets.gpg and .mask.gpg) based on the GPG key of each directory. Services and folders use random aliases, while the real association is stored in the identity-based mapping.

Current version: 2.5.1

💡 How Does It Work?

In traditional pass, folder and file names are visible on the filesystem. pass-secrets allows you to rename actual subdirectories and entries to random aliases (e.g. Zovar/Kelip.gpg) while maintaining an encrypted mapping that associates each alias with the real service.

🛡️ Identities and Trust Isolation

An identity is any directory in the pass tree that has its own .gpg-id file, regardless of its depth. Identity names must be unique throughout the entire tree. Two directories with .gpg-id files and the same name make the command ambiguous and are therefore rejected.

Trust Boundary: An identity nested inside another does NOT inherit the keys of its parent identity.
Complete Isolation: Compromising the parent identity's key does not expose the contents of the child identity.
Boundary-Crossing Protection: generate and namegen reject any block/path that crosses the directory of another nested identity — without this check, a password could be encrypted using the wrong identity's key.
🔑 Optional .gpg-id Signature

If PASSWORD_STORE_SIGNING_KEY is configured (the same variable used by native pass), pass-secrets requires a valid .gpg-id.sig before accepting an identity's recipients — preventing replacement or injection of keys into .gpg-id. If the variable is not configured, behavior is identical to plain pass (without verification).

🛠️ Installation
# 1. Create the pass extensions directory (if it does not already exist)
mkdir -p "${PASSWORD_STORE_EXTENSIONS_DIR:-$HOME/.password-store/.extensions}"

# 2. Copy the script to the extensions directory
cp secrets.bash "${PASSWORD_STORE_EXTENSIONS_DIR:-$HOME/.password-store/.extensions}/secrets.bash"

# 3. Make the script executable
chmod +x "${PASSWORD_STORE_EXTENSIONS_DIR:-$HOME/.password-store/.extensions}/secrets.bash"

# 4. Enable extensions in your shell (.bashrc, .zshrc, etc.)
export PASSWORD_STORE_ENABLE_EXTENSIONS=true

🚀 Usage and Commands

All commands follow the syntax: pass secrets <identity> <subcommand> [arguments].

🔍 Map Queries (.secrets.gpg)
Command	Description
pass secrets <id> dir <block>	Lists entries whose path starts with the specified block.
pass secrets <id> word <term> [context]	Searches for a term in the map while displaying context lines (grep -C).
pass secrets <id> count <block>	Returns the number of entries under the specified block.
pass secrets <id> struct	Displays the actual alias structure on disk by scanning the filesystem (without decrypting).
pass secrets <id> version	Displays the installed extension version.
✏️ Management and Reconciliation
Command	Description
pass secrets <id> add <path>	Manually associates an existing alias. The real name is requested via a prompt, never as an argument, to prevent exposure in shell history.
pass secrets <id> edit	Edits .secrets.gpg by decrypting it into a temporary file in memory (via /dev/shm), opening it with $EDITOR, and re-encrypting it. It does not depend on third-party tools (support for vim-gnupg has been removed).
pass secrets <id> check	Audits the map against the actual file tree in read-only mode (equivalent to rebuild --dry-run). In addition to new/orphaned entries, it reports global identity-name collisions, mask entries pointing to non-existent directories, and duplicate real names assigned to different aliases.
pass secrets <id> rebuild [--yes] [--prune]	Scans the actual tree and reconciles the map.
rebuild flags:
--yes: Does not prompt for the real name of new entries (inserts them as (pending)).
--prune: Removes orphaned entries from the map.
🔐 Alias Generation
Command	Description
pass secrets <id> namegen [block] [-n length] [-u count]	Suggests available aliases of the specified length without creating files. Checks for collisions only within the same identity. Blocks that cross nested identities are rejected, using the same protection as generate below.
pass secrets <id> generate [block] [length] [flags]	Generates an available alias and immediately creates the actual entry using the native pass generate command (forwarding the [flags]). It does not record the name association, requiring add to be used afterward. Blocks that cross nested identities are rejected to prevent encryption with the wrong GPG key.
🎭 Alias and Mask Management (.mask.gpg)

The .mask.gpg map allows aliases (e.g. disposable email addresses) to be associated with directories in a many-to-many relationship.

Command	Description
pass secrets <id> mask add <dir>	Associates an email alias with a directory. The alias is requested via an interactive prompt instead of being provided as an argument.
pass secrets <id> mask dir <dir>	Lists the aliases associated with a directory.
pass secrets <id> mask word <term> [ctx]	Searches for an alias or directory in .mask.gpg.
pass secrets <id> mask list	Lists the entire contents of .mask.gpg.
pass secrets <id> mask edit	Edits .mask.gpg using the same secure mechanism as the main edit command.
⚠️ Behavior in Non-Interactive Contexts (Scripts, Cron, Automation)

The real name (add) and alias (mask add) are never accepted as arguments — they are only provided through a prompt, so they do not end up in ~/.bash_history or become visible through ps aux. This has a direct consequence for automation: whenever the script would require genuine human confirmation, it refuses to proceed rather than silently assuming a default answer.

pass secrets <id> add <path> on an already-associated path requires interactive confirmation ([y/N]). Outside a terminal, it is rejected — it never overwrites silently.
pass secrets <id> rebuild without --yes prompts for the real name of each new entry. If the standard input reaches EOF before an answer is provided, the command exits with an error instead of silently recording (pending) — preventing "nobody answered" from being interpreted as "the user accepted the default". Use --yes explicitly for automation.
pass secrets <id> edit / mask edit: if encryption fails (e.g. .gpg-id is corrupted or points to a non-existent key) and the input is not interactive, the command exits immediately instead of repeatedly retrying indefinitely.

In all three cases, normal interactive behavior (prompting and waiting for a response in a real terminal) remains unchanged.

📂 Internal File Format

The .secrets.gpg and .mask.gpg files are kept encrypted on disk using the GPG key defined in the local .gpg-id. The plaintext format, before encryption, is:

.secrets.gpg format (1:1 association by path):

<alias-path-relative-to-identity> = <real-name / description>


(Example: a1/b2 = Production Server - SSH)

.mask.gpg format (N:N association by alias/directory):

<alias> = <directory-path>


(Example: alias1@domain.com = services/finance)

🔒 Permissions and Security
The script audits the filesystem and requires exactly 600 permissions on encrypted map files (it does not accept 640 or any other mode).
The lifecycle of temporary files used during editing (edit and mask edit) is entirely managed by the extension, securely cleaning up traces (via shred/rm tied to a shell trap) without depending on plugins such as vim-gnupg.
The script rejects password-generation paths and blocks that cross directories belonging to nested identities, ensuring that files are never encrypted using an unintended identity's key.
Native integration with pass's Git support: all map modifications made by the script automatically create commits in the repository.
All user input goes through path-traversal checks (check_sneaky_paths) and token sanitization.
📄 License

This project is released under the same license as the password-store
 project (GPLv2+).
