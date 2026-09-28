#!/usr/bin/env python3
"""Download the assets a design-context code block references, and record them.

Run: python3 plugins/figma/skills/fetch-reference/scripts/fetch-assets.py fetch <context-out> <assets-dir> <assets-out> < code
     python3 plugins/figma/skills/fetch-reference/scripts/fetch-assets.py list <assets-out>...

fetch reads one design-context code block on stdin. The block declares its
assets as constants, either a whole URL or a template on a prefix constant:

  const assetPathPrefix = "https://…";
  const imgHeroImage = `${assetPathPrefix}/aa824.png`;

Every constant whose value resolves to a URL, other than a prefix another
constant interpolates, is an asset. Each asset is downloaded into memory,
its format named from its bytes by sniff-asset.py (never from the URL), and
written to <assets-dir>/<first 16 hex digits of its SHA-256>.<extension>.
Identical bytes are one file. A file already at that name is kept when its
bytes are identical, and refused when they differ, so no earlier file is ever
replaced.

The asset's node is the element that uses the constant: that element's own
data-node-id, or else the nearest enclosing element's. One entry is recorded
per node and asset, in code order; an asset no element uses is recorded once
with node_id null.

<context-out> receives the code block with each asset constant's value
replaced by its local file and each prefix constant's value by <assets-dir>;
every other byte is unchanged. <assets-out> receives the JSON array
[{"node_id", "file", "mime"}]. A URL never reaches a file, stdout or stderr:
the result is refused if any asset URL, prefix, or asset endpoint path
remains in it.

Only https URLs are fetched; file URLs too when FETCH_ASSETS_ALLOW_FILE=1.

list prints the JSON array of every <assets-out> given, each
(node_id, file) pair once, in first-seen order.

Exit codes: 0 written or printed; 2 usage, a refused URL, bytes of no known
image format, a name already holding other bytes, an asset URL left in the
result, or a malformed list; 3 a download failed. Nothing is written on 2 or 3.
"""

import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys

CONST = re.compile(
    r'^[ \t]*const[ \t]+([A-Za-z_$][\w$]*)[ \t]*=[ \t]*'
    r'(?:"([^"\n]*)"|\'([^\'\n]*)\'|`([^`\n]*)`)[ \t]*;?[ \t]*$',
    re.MULTILINE,
)
INTERPOLATION = re.compile(r"\$\{([A-Za-z_$][\w$]*)\}")
URL = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*://")
NODE_ATTR = re.compile(r'\bdata-node-id="([^"]*)"')
TAG_NAME = re.compile(r"</?\s*([A-Za-z][\w.:-]*)?")
NODE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9:;_-]*$")
ENDPOINT = "/api/mcp/asset"
ENTRY_KEYS = {"node_id", "file", "mime"}


def die(message, code=2):
    print("fetch-assets: " + message, file=sys.stderr)
    sys.exit(code)


def load_sniffer():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sniff-asset.py")
    spec = importlib.util.spec_from_file_location("sniff_asset", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def constants(code):
    """Return [(name, value, start, end, template)] in declaration order, values resolved."""
    found, values = [], {}
    for m in CONST.finditer(code):
        name = m.group(1)
        template = m.group(4) is not None
        raw = next(g for g in m.groups()[1:] if g is not None)
        value = INTERPOLATION.sub(lambda i: values.get(i.group(1), i.group(0)), raw) if template else raw
        values[name] = value
        found.append((name, value, raw, m.start(), m.end()))
    return found


def tags(code):
    """Yield (start, end, text) for each JSX tag, skipping braces and quoted values."""
    i, n = 0, len(code)
    while i < n:
        if code[i] != "<" or i + 1 >= n or not (code[i + 1].isalpha() or code[i + 1] in "/>"):
            i += 1
            continue
        j, depth, quote = i + 1, 0, None
        while j < n:
            c = code[j]
            if quote:
                if c == quote:
                    quote = None
            elif c == "{":
                depth += 1
            elif c == "}":
                depth = max(0, depth - 1)
            elif depth == 0 and c in "\"'":
                quote = c
            elif depth == 0 and c == ">":
                break
            j += 1
        yield i, j + 1, code[i:j + 1]
        i = j + 1


def usages(code, names, declared_end):
    """Return [(node_id or None, name)] in code order, each pair once."""
    if not names:
        return []
    word = re.compile(r"(?<![\w$])(" + "|".join(re.escape(n) for n in names) + r")(?![\w$])")
    stack, seen, found = [], set(), []
    for start, _end, text in tags(code):
        if start < declared_end:
            continue
        closing = text.startswith("</")
        m = TAG_NAME.match(text)
        tag = (m.group(1) or "") if m else ""
        if closing:
            for k in range(len(stack) - 1, -1, -1):
                if stack[k][0] == tag:
                    del stack[k:]
                    break
            continue
        own = NODE_ATTR.search(text)
        node = own.group(1) if own else next((s[1] for s in reversed(stack) if s[1]), None)
        for u in word.finditer(text):
            pair = (node, u.group(1))
            if pair not in seen:
                seen.add(pair)
                found.append(pair)
        if not text.endswith("/>"):
            stack.append((tag, own.group(1) if own else None))
    return found


def download(url, label):
    protocols = "=https,file" if os.environ.get("FETCH_ASSETS_ALLOW_FILE") == "1" else "=https"
    try:
        done = subprocess.run(
            ["curl", "-sS", "-L", "--fail", "--max-time", "60", "--proto", protocols,
             "--proto-redir", "=https", "-o", "-", url],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
        )
    except OSError:
        die(f"asset {label}: the downloader could not be started", 3)
    if done.returncode != 0 or not done.stdout:
        die(f"asset {label}: download failed (exit {done.returncode}, {len(done.stdout)} bytes)", 3)
    return done.stdout


def fetch(context_out, assets_dir, assets_out):
    code = sys.stdin.read()
    sniffer = load_sniffer()
    allow_file = os.environ.get("FETCH_ASSETS_ALLOW_FILE") == "1"

    decls = constants(code)
    url_decls = [d for d in decls if URL.match(d[1])]
    interpolated = {i.group(1) for d in decls for i in INTERPOLATION.finditer(d[2])}
    prefixes = [d for d in url_decls if d[0] in interpolated]
    assets = [d for d in url_decls if d[0] not in interpolated]

    for name, value, *_ in url_decls:
        scheme = value.split("://", 1)[0].lower()
        if scheme != "https" and not (scheme == "file" and allow_file):
            die(f"asset {name}: only https URLs are fetched")

    files, blobs = {}, {}
    by_url = {}
    for name, value, *_ in assets:
        if value not in by_url:
            data = download(value, name)
            found = sniffer.sniff(data)
            if found is None:
                die(f"asset {name}: its bytes are not PNG, JPEG, GIF, WebP or SVG")
            ext, mime = found
            path = os.path.join(assets_dir, hashlib.sha256(data).hexdigest()[:16] + "." + ext)
            if os.path.exists(path):
                with open(path, "rb") as f:
                    if f.read() != data:
                        die(f"asset {name}: '{path}' already holds other bytes")
            by_url[value] = (path, mime)
            blobs[path] = data
        files[name] = by_url[value]

    declared_end = max((d[4] for d in decls), default=0)
    entries, used = [], set()
    for node, name in usages(code, list(files), declared_end):
        path, mime = files[name]
        entries.append({"node_id": node, "file": path, "mime": mime})
        used.add(name)
    for name, *_ in assets:
        if name not in used:
            path, mime = files[name]
            entries.append({"node_id": None, "file": path, "mime": mime})
            used.add(name)

    rewritten, cursor = [], 0
    replacements = {d[0]: files[d[0]][0] for d in assets}
    replacements.update({d[0]: assets_dir for d in prefixes})
    for name, _value, _raw, start, end in decls:
        if name in replacements:
            line = code[start:end]
            indent = line[: len(line) - len(line.lstrip(" \t"))]
            rewritten.append(code[cursor:start])
            rewritten.append(f"{indent}const {name} = {json.dumps(replacements[name])};")
            cursor = end
    rewritten.append(code[cursor:])
    result = "".join(rewritten)

    secrets = [d[1] for d in url_decls]
    listing = json.dumps(entries, indent=2)
    for text in [result, listing] + [b.decode("utf-8", "replace") for b in blobs.values()]:
        if ENDPOINT in text or any(s and s in text for s in secrets):
            die("an asset URL would be written; nothing was written")

    os.makedirs(assets_dir, exist_ok=True)
    for path, data in blobs.items():
        if not os.path.exists(path):
            with open(path, "xb") as f:
                f.write(data)
    for out, text in ((context_out, result), (assets_out, listing + "\n")):
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        with open(out, "w", encoding="utf-8", newline="") as f:
            f.write(text)
    print(f"assets: {len(entries)} entries, {len(blobs)} files")


def merged(paths):
    sniffer = load_sniffer()
    mimes = set(sniffer.FORMATS.values())
    seen, out = set(), []
    for path in paths:
        try:
            with open(path, encoding="utf-8") as f:
                entries = json.load(f)
        except (OSError, ValueError) as e:
            die(f"'{path}' is not a readable JSON list: {e}")
        if not isinstance(entries, list):
            die(f"'{path}' is not a list")
        for e in entries:
            if not isinstance(e, dict) or set(e) != ENTRY_KEYS:
                die(f"'{path}': each entry must have exactly file, mime, node_id")
            node, file, mime = e["node_id"], e["file"], e["mime"]
            if node is not None and (not isinstance(node, str) or not NODE_ID.match(node)):
                die(f"'{path}': node_id {node!r} is not a node id")
            if not isinstance(file, str) or not file or "://" in file:
                die(f"'{path}': file must be a local path")
            if mime not in mimes:
                die(f"'{path}': mime {mime!r} is not one the sniffer names")
            if (node, file) not in seen:
                seen.add((node, file))
                out.append({"node_id": node, "file": file, "mime": mime})
    return out


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "fetch" and len(sys.argv) == 5:
        fetch(*sys.argv[2:5])
    elif len(sys.argv) >= 3 and sys.argv[1] == "list":
        print(json.dumps(merged(sys.argv[2:]), indent=2))
    else:
        die("usage: fetch-assets.py fetch <context-out> <assets-dir> <assets-out> < code\n"
            "       fetch-assets.py list <assets-out>...")


if __name__ == "__main__":
    main()
