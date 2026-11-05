#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JESS_BIN="${JESS_BIN:-$(command -v jess || true)}"
[[ -n "$JESS_BIN" ]] || { echo 'set JESS_BIN to run archive safety tests' >&2; exit 1; }
JESS_BIN="$(readlink -f "$JESS_BIN")"
cd "$ROOT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/good/openmw-1.0-Linux-64Bit" "$TMP/artifacts"
for file in openmw openmw.x86_64; do
    cat > "$TMP/good/openmw-1.0-Linux-64Bit/$file" <<'BIN'
#!/bin/sh
printf 'OpenMW test fixture\n'
exit 0
BIN
    chmod +x "$TMP/good/openmw-1.0-Linux-64Bit/$file"
done
tar czf "$TMP/artifacts/good.tar.gz" -C "$TMP/good" openmw-1.0-Linux-64Bit

"$JESS_BIN" workspace run --trusted forge -- smoke --archive "$TMP/artifacts/good.tar.gz" \
    > "$TMP/good.log"
grep -F 'All checks passed' "$TMP/good.log" >/dev/null
compgen -G "$TMP/artifacts/RESULTS_*.tar.gz" > /dev/null

# Entries unsafe to extract: the legacy smoke-test guard must reject them
# before tar is invoked for extraction.
python3 - "$TMP" <<'PY'
import io, tarfile, pathlib, sys
root = pathlib.Path(sys.argv[1])
for name, member in [('parent', '../outside.txt'), ('absolute', '/tmp/outside.txt')]:
    with tarfile.open(root / f'{name}.tar.gz', 'w:gz') as archive:
        directory = tarfile.TarInfo('openmw-1.0-Linux-64Bit/')
        directory.type = tarfile.DIRTYPE
        archive.addfile(directory)
        contents = b'no'
        entry = tarfile.TarInfo(member)
        entry.size = len(contents)
        archive.addfile(entry, io.BytesIO(contents))
with tarfile.open(root / 'symlink.tar.gz', 'w:gz') as archive:
    directory = tarfile.TarInfo('openmw-1.0-Linux-64Bit/')
    directory.type = tarfile.DIRTYPE
    archive.addfile(directory)
    link = tarfile.TarInfo('openmw-1.0-Linux-64Bit/escape')
    link.type = tarfile.SYMTYPE
    link.linkname = '../../etc/passwd'
    archive.addfile(link)
PY

for kind in parent absolute symlink; do
    if "$JESS_BIN" workspace run --trusted forge -- smoke --archive "$TMP/$kind.tar.gz" \
        > "$TMP/$kind.log" 2>&1; then
        echo "FAIL: unsafe archive $kind was accepted" >&2
        exit 1
    fi
    if [[ "$kind" == symlink ]]; then
        grep -Eq 'symlink escapes package tree' "$TMP/$kind.log"
    else
        grep -Eq 'unsafe or empty archive entry' "$TMP/$kind.log"
    fi
done
printf 'PASS: 4 archive tests (valid package, traversal, absolute path, escaping link)\n'
