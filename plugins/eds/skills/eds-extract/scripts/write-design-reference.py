#!/usr/bin/env python3
# write-design-reference.py image <filename> <mime> <image-path> <out-json>
# write-design-reference.py design_tool <reference-url> <provider-json> <provider-image> <out-json> <out-image>
#
# Deterministic. Writes this pack's own `design-reference` artifact
# (`pack.yaml`: `.ai/run-context/design-reference.json`), normalising
# whichever design-source form `resolve-design-source.py` decided into one
# fixed shape — never a third-party provider's own JSON returned unchanged
# (core contract §4/D34: "an adapter returns the third-party skill's output
# unchanged" is a reject condition).
#
# The `image` mode is core contract §6.1's consequential case: "from an
# image you can read a comparison target and nothing else." Its output
# marks that explicitly — `has_values: false` and `variables: null` — so a
# reader of this file can tell "no values were possible" apart from a
# design-tool reference that legitimately used zero variables
# (`has_values: true`, `variables: {}`), which is a different fact.
#
# Exit codes: 0 on success; 2 for a usage error.

import json
import os
import shutil
import sys


def usage_error(msg):
    print(
        "usage: write-design-reference.py image <filename> <mime> <image-path> <out-json>\n"
        "       write-design-reference.py design_tool <reference-url> <provider-json> <provider-image> <out-json> <out-image>\n"
        f"{msg}",
        file=sys.stderr,
    )
    sys.exit(2)


def write_json(out_json, record):
    os.makedirs(os.path.dirname(out_json) or ".", exist_ok=True)
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(record, f, indent=2, sort_keys=True)
        f.write("\n")


def main():
    if len(sys.argv) < 2:
        usage_error("expected a mode ('image' or 'design_tool') as the first argument")
    mode = sys.argv[1]

    if mode == "image":
        if len(sys.argv) != 6:
            usage_error("'image' mode expects exactly 4 arguments after the mode")
        _, _, filename, mime, image_path, out_json = sys.argv[:6]
        if not os.path.isfile(image_path):
            usage_error(f"'{image_path}' not found — the image must already be downloaded")
        record = {
            "source_kind": "image",
            "reference": f"{filename} (image attachment)",
            "has_values": False,
            "variables": None,
            "geometry": None,
            "reference_image": image_path,
            "mime": mime,
        }
        write_json(out_json, record)
        print(f"wrote: {out_json}")
        sys.exit(0)

    if mode == "design_tool":
        if len(sys.argv) != 7:
            usage_error("'design_tool' mode expects exactly 5 arguments after the mode")
        _, _, reference_url, provider_json_path, provider_image_path, out_json, out_image = sys.argv[:7]
        if not os.path.isfile(provider_json_path):
            usage_error(f"'{provider_json_path}' not found")
        if not os.path.isfile(provider_image_path):
            usage_error(f"'{provider_image_path}' not found")

        with open(provider_json_path, encoding="utf-8") as f:
            provider = json.load(f)

        os.makedirs(os.path.dirname(out_image) or ".", exist_ok=True)
        shutil.copyfile(provider_image_path, out_image)

        record = {
            "source_kind": "design_tool",
            "reference": reference_url,
            "has_values": True,
            "variables": provider.get("variables", {}),
            "geometry": provider.get("geometry"),
            "reference_image": out_image,
        }
        write_json(out_json, record)
        print(f"wrote: {out_json}")
        sys.exit(0)

    usage_error(f"unknown mode '{mode}' — expected 'image' or 'design_tool'")


if __name__ == "__main__":
    main()
