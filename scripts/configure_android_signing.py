#!/usr/bin/env python3
"""Configure local Android signing; run interactively, never through a chat tool."""
from __future__ import annotations

import argparse
import getpass
import os
from pathlib import Path
import shutil
import subprocess
import sys


def escape_properties(value: str) -> str:
    # Java Properties.load reads ISO-8859-1; escaping UTF-16 units also covers
    # leading spaces, backslashes, separators and non-BMP password characters.
    units = value.encode("utf-16-be")
    return "".join("\\u%04x" % int.from_bytes(units[i:i + 2], "big")
                   for i in range(0, len(units), 2))


def configure(root: Path, keystore: Path, alias: str, keytool: str,
              store_password: str, key_password: str) -> Path:
    target = root / "client/android/key.properties"
    if target.exists():
        raise ValueError("Signing configuration already exists; it was not overwritten.")
    if not target.parent.is_dir():
        raise ValueError(f"Client Android directory does not exist: {target.parent}")
    if not keystore.is_file():
        raise ValueError(f"Keystore does not exist or cannot be accessed: {keystore}")
    if not alias or not store_password or not key_password:
        raise ValueError("Alias and both passwords must be nonempty.")
    env = dict(os.environ)
    env["PACTICK_LOCAL_STORE_PASSWORD"] = store_password
    env["PACTICK_LOCAL_KEY_PASSWORD"] = key_password
    # Generating and discarding a CSR proves the alias has an accessible private
    # key. Passwords go only to the child environment, never command arguments.
    result = subprocess.run(
        [keytool, "-J-Duser.language=en", "-certreq", "-alias", alias, "-keystore", str(keystore.resolve()),
         "-storepass:env", "PACTICK_LOCAL_STORE_PASSWORD",
         "-keypass:env", "PACTICK_LOCAL_KEY_PASSWORD"],
        env=env, capture_output=True, timeout=60, check=False,
    )
    if result.returncode:
        diagnostic = ((result.stdout or b"") + (result.stderr or b"")).decode("utf-8", errors="replace").lower()
        if "password was incorrect" in diagnostic or "tampered" in diagnostic:
            reason = "Keystore password is incorrect."
        elif "cannot recover key" in diagnostic or "recover" in diagnostic and "key" in diagnostic:
            reason = "Private-key password is incorrect."
        elif "does not exist" in diagnostic and "alias" in diagnostic:
            reason = "Alias does not exist in this keystore."
        elif "has no key" in diagnostic:
            reason = "Alias has no private key."
        else:
            reason = "Keytool could not validate the key; run keytool -certreq interactively to see its local diagnostic."
        raise ValueError(reason + " Configuration was not written.")
    values = {"storeFile": str(keystore.resolve()), "storePassword": store_password,
              "keyAlias": alias, "keyPassword": key_password}
    contents = "".join(f"{key}={escape_properties(value)}\n" for key, value in values.items())
    descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="ascii", newline="\n") as stream:
        stream.write(contents)
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--keystore", type=Path, required=True)
    parser.add_argument("--alias", default="pactick")
    parser.add_argument("--keytool", default=shutil.which("keytool") or "keytool")
    args = parser.parse_args()
    if not sys.stdin.isatty():
        parser.exit(1, "Run this command in your own interactive terminal; do not send passwords through chat.\n")
    target = args.root / "client/android/key.properties"
    if target.exists():
        parser.exit(1, "Signing configuration already exists; it was not overwritten.\n")
    if not target.parent.is_dir():
        parser.exit(1, f"Client Android directory does not exist: {target.parent}\n")
    if not args.keystore.is_file():
        parser.exit(1, f"Keystore does not exist or cannot be accessed: {args.keystore}\n")
    store_password = getpass.getpass("Keystore password (hidden): ")
    key_password = getpass.getpass("Private-key password (Enter = same as keystore): ") or store_password
    try:
        target = configure(args.root, args.keystore, args.alias, args.keytool,
                           store_password, key_password)
    except ValueError as error:
        parser.exit(1, f"{error}\n")
    except (OSError, subprocess.TimeoutExpired) as error:
        # Do not print subprocess output or values from signing configuration.
        parser.exit(1, f"{type(error).__name__}: signing configuration failed; check paths, alias and passwords.\n")
    print(f"Signing key validated. Configuration saved: {target}")
    print("This file contains passwords. Keep it private and out of source archives.")


if __name__ == "__main__":
    main()
