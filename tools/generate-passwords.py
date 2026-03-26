#!/usr/bin/env python3
"""Generate cryptographically secure passwords for Offline Box.

Reads a YAML file (default: ansible/group_vars/passwords.yml),
fills every key whose value is empty with a random password,
and writes the result back.

Usage:
    python3 tools/generate-passwords.py                        # default file
    python3 tools/generate-passwords.py path/to/passwords.yml  # custom file
    python3 tools/generate-passwords.py --init                 # copy example → passwords.yml & fill

If specific password-format requirements are known for a key,
they are respected (see SPECIAL_RULES below).
"""

import secrets
import string
import sys
import shutil
from pathlib import Path

# ── character sets ──────────────────────────────────────────────
ALPHA_DIGITS = string.ascii_letters + string.digits
# PostgreSQL-safe: no single-quotes or backslashes
PG_SAFE = ALPHA_DIGITS + "!@#%^&*()-_=+[]{}|:,.<>?"


# ── per-key rules ──────────────────────────────────────────────
# (length, charset, description)
SPECIAL_RULES: dict[str, tuple[int, str, str]] = {
    # Secret keys / tokens — extra long
    "paperless_ngx_secret_key":   (64, ALPHA_DIGITS, "Django SECRET_KEY"),
    "gitea_secret_key":           (64, ALPHA_DIGITS, "Gitea internal token"),
    "searxng_secret_key":         (64, ALPHA_DIGITS, "SearXNG secret"),
    "vaultwarden_admin_token":    (64, ALPHA_DIGITS, "Vaultwarden admin token"),
    "bigbluebutton_secret_key":   (64, ALPHA_DIGITS, "BBB security salt"),
    "opencloud_secret_key":       (64, ALPHA_DIGITS, "OpenCloud secret key"),
    # DB passwords — avoid shell-unsafe chars
    "bigbluebutton_db_password":  (32, ALPHA_DIGITS, "PostgreSQL password"),
    # Mattermost
    "mattermost_admin_password":  (32, ALPHA_DIGITS, "Mattermost admin password"),
    # Dendrite
    "dendrite_admin_password":    (32, ALPHA_DIGITS, "Dendrite admin password"),
}

DEFAULT_LENGTH = 32
DEFAULT_CHARSET = ALPHA_DIGITS


def generate(length: int, charset: str) -> str:
    """Return a cryptographically random string."""
    return "".join(secrets.choice(charset) for _ in range(length))


def load_yaml_preserving_comments(path: Path) -> tuple[list[str], dict[str, str]]:
    """Minimal YAML reader that preserves comments and blank lines.

    Returns (original_lines, {key: value}).
    Only handles flat key: "value" or key: '' mappings (which is all
    passwords.yml needs).
    """
    lines = path.read_text().splitlines(keepends=True)
    data: dict[str, str] = {}
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("---"):
            continue
        if ":" in stripped:
            key, _, val = stripped.partition(":")
            key = key.strip()
            val = val.strip().strip("\"'")
            data[key] = val
    return lines, data


def write_yaml_preserving_comments(
    path: Path,
    lines: list[str],
    data: dict[str, str],
) -> None:
    """Write back the YAML file, updating values while keeping structure."""
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and not stripped.startswith("---") and ":" in stripped:
            key, _, _ = stripped.partition(":")
            key = key.strip()
            if key in data:
                indent = line[: len(line) - len(line.lstrip())]
                out.append(f'{indent}{key}: "{data[key]}"\n')
                continue
        out.append(line if line.endswith("\n") else line + "\n")
    path.write_text("".join(out))


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    default_file = repo_root / "ansible" / "group_vars" / "passwords.yml"
    example_file = repo_root / "ansible" / "group_vars" / "passwords.example.yml"

    # Handle --init flag
    if "--init" in sys.argv:
        if not example_file.exists():
            print(f"ERROR: {example_file} not found", file=sys.stderr)
            sys.exit(1)
        shutil.copy2(example_file, default_file)
        print(f"Copied {example_file.name} → {default_file.name}")
        target = default_file
    elif len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        target = Path(sys.argv[1])
    else:
        target = default_file

    if not target.exists():
        print(f"ERROR: {target} not found.", file=sys.stderr)
        print(f"  Run:  python3 {sys.argv[0]} --init", file=sys.stderr)
        sys.exit(1)

    lines, data = load_yaml_preserving_comments(target)

    generated = 0
    for key, val in data.items():
        if val:  # already has a value — skip
            continue
        length, charset, desc = SPECIAL_RULES.get(
            key, (DEFAULT_LENGTH, DEFAULT_CHARSET, "")
        )
        data[key] = generate(length, charset)
        label = f" ({desc})" if desc else ""
        print(f"  Generated {key}{label}: {length} chars")
        generated += 1

    if generated == 0:
        print("All keys already have values — nothing to do.")
    else:
        write_yaml_preserving_comments(target, lines, data)
        print(f"\n  {generated} password(s) written to {target}")

    # Remind about gitignore
    if target == default_file:
        print("\n  NOTE: passwords.yml is in .gitignore — never commit it.")


if __name__ == "__main__":
    main()
