#!/usr/bin/env python3
"""Name an asset's image format from its bytes alone.

Run: python3 plugins/figma/skills/fetch-reference/scripts/sniff-asset.py <file>

Prints `<extension><TAB><mime>` for the file's format, decided from its
leading bytes and never from its name or any URL:

  png   image/png      89 50 4E 47 0D 0A 1A 0A
  jpg   image/jpeg     FF D8 FF
  gif   image/gif      GIF87a or GIF89a
  webp  image/webp     RIFF, four size bytes, WEBP
  svg   image/svg+xml  UTF-8 text whose first element is <svg>, after an
                       optional byte-order mark, whitespace, XML
                       declaration, comments and doctype

Exit codes: 0 printed; 2 usage, an unreadable or empty file, or bytes that are
none of the formats above.
"""

import codecs
import re
import sys

FORMATS = {
    "png": "image/png",
    "jpg": "image/jpeg",
    "gif": "image/gif",
    "webp": "image/webp",
    "svg": "image/svg+xml",
}

SVG_PROLOGUE = re.compile(
    r"\A(?:\s+|<\?xml\b[^>]*\?>|<!--.*?-->|<!DOCTYPE\b[^>]*>)*<svg[\s>/]",
    re.DOTALL,
)


def sniff(data):
    """Return (extension, mime) for the bytes, or None when unrecognised."""
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png", FORMATS["png"]
    if data.startswith(b"\xff\xd8\xff"):
        return "jpg", FORMATS["jpg"]
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "gif", FORMATS["gif"]
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp", FORMATS["webp"]
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    try:
        text = codecs.getincrementaldecoder("utf-8")().decode(data[:4096], final=False)
    except UnicodeDecodeError:
        return None
    if SVG_PROLOGUE.match(text):
        return "svg", FORMATS["svg"]
    return None


def main():
    if len(sys.argv) != 2:
        print("usage: sniff-asset.py <file>", file=sys.stderr)
        sys.exit(2)
    try:
        with open(sys.argv[1], "rb") as f:
            data = f.read()
    except OSError as e:
        print(f"sniff-asset: cannot read '{sys.argv[1]}': {e.strerror}", file=sys.stderr)
        sys.exit(2)
    if not data:
        print(f"sniff-asset: '{sys.argv[1]}' is empty", file=sys.stderr)
        sys.exit(2)
    found = sniff(data)
    if found is None:
        print(f"sniff-asset: '{sys.argv[1]}' is not PNG, JPEG, GIF, WebP or SVG", file=sys.stderr)
        sys.exit(2)
    print(f"{found[0]}\t{found[1]}")


if __name__ == "__main__":
    main()
