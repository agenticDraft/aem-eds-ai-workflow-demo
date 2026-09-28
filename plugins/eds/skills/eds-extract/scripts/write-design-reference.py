#!/usr/bin/env python3
# write-design-reference.py image <filename> <mime> <image-path> <out-json>
# write-design-reference.py design_tool <reference-url> <provider-json> <provider-image> <out-json> <out-image> <out-context>
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
# `design_context` follows the same explicit-absence rule. The `design_tool`
# mode copies the provider's `design_context` object and its code file
# byte-for-byte to <out-context>, pointing `code_file` at that copy; a
# provider `design_context` of null (or none) is written as null and no code
# file is written. The `image` mode always writes `design_context: null`.
#
# `viewports` — the provider's list of viewport variants, each
# {name, node_id, width, image, context} — is carried through sorted widest
# first. Each variant's image and context file are copied byte-for-byte to
# their own files next to <out-image> and <out-context>, the node id added to
# the name (`design-reference-1-118.png`, `design-context-1-118.txt`); a null
# context stays null and writes no file. A provider with no `viewports`, or an
# empty list, is a single width: the key is left out, and the record is exactly
# what it was without it. A malformed entry, a missing file or a repeated node
# id exits 2 before anything is written.
#
# `screenshots` — the provider's record of each reference image's size, each
# {node_id, width, height, original_width, original_height, downscaled} — is
# carried through with `node_id` replaced by `image`, the run-context copy that
# node's screenshot became: a variant's own copy, or, when there are no
# variants, <out-image> for the referenced node itself. Entries follow the widest-first order of `viewports`.
# An entry for a node with no image, a non-numeric size, a repeated node, or a
# `downscaled` that contradicts the sizes (at least one pixel smaller on either
# edge) exits 2 before anything is written. No `screenshots`, or an empty list,
# leaves the key out.
#
# Exit codes: 0 on success; 2 for a usage error.

import json
import os
import re
import shutil
import sys

VIEWPORT_KEYS = {"name", "node_id", "width", "image", "context"}
SCREENSHOT_KEYS = {"node_id", "width", "height", "original_width", "original_height", "downscaled"}
SIZE_KEYS = ("width", "height", "original_width", "original_height")
NODE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9:;_-]*$")


def usage_error(msg):
    print(
        "usage: write-design-reference.py image <filename> <mime> <image-path> <out-json>\n"
        "       write-design-reference.py design_tool <reference-url> <provider-json> <provider-image> <out-json> <out-image> <out-context>\n"
        f"{msg}",
        file=sys.stderr,
    )
    sys.exit(2)


def write_json(out_json, record):
    os.makedirs(os.path.dirname(out_json) or ".", exist_ok=True)
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(record, f, indent=2, sort_keys=True)
        f.write("\n")


def validated_viewports(provider_json_path, viewports):
    if viewports is None or viewports == []:
        return []
    where = f"'{provider_json_path}': viewports"
    if not isinstance(viewports, list):
        usage_error(f"{where} must be a list")
    seen = set()
    for entry in viewports:
        if not isinstance(entry, dict) or set(entry) != VIEWPORT_KEYS:
            usage_error(f"{where}: each entry must have exactly {', '.join(sorted(VIEWPORT_KEYS))}")
        node_id = entry["node_id"]
        if not isinstance(entry["name"], str) or not isinstance(node_id, str) or not NODE_ID.match(node_id):
            usage_error(f"{where}: name must be a string and node_id a node id, got {node_id!r}")
        if node_suffix(node_id) in seen:
            usage_error(f"{where}: node_id {node_id!r} appears twice")
        seen.add(node_suffix(node_id))
        width = entry["width"]
        if isinstance(width, bool) or not isinstance(width, (int, float)) or width <= 0:
            usage_error(f"{where}: {node_id} has no numeric width")
        if not isinstance(entry["image"], str) or not os.path.isfile(entry["image"]):
            usage_error(f"{where}: {node_id} image {entry['image']!r} not found")
        context = entry["context"]
        if context is not None and (not isinstance(context, str) or not os.path.isfile(context)):
            usage_error(f"{where}: {node_id} context {context!r} not found")
    return sorted(viewports, key=lambda v: v["width"], reverse=True)


def positive_number(value):
    return not isinstance(value, bool) and isinstance(value, (int, float)) and value > 0


def validated_screenshots(provider_json_path, screenshots, node_id, viewports, out_image):
    if screenshots is None or screenshots == []:
        return []
    where = f"'{provider_json_path}': screenshots"
    if not isinstance(screenshots, list):
        usage_error(f"{where} must be a list")
    images = {node_suffix(v["node_id"]): per_variant(out_image, v["node_id"]) for v in viewports}
    if not viewports and isinstance(node_id, str):
        images[node_suffix(node_id)] = out_image
    carried = {}
    for entry in screenshots:
        if not isinstance(entry, dict) or set(entry) != SCREENSHOT_KEYS:
            usage_error(f"{where}: each entry must have exactly {', '.join(sorted(SCREENSHOT_KEYS))}")
        node = entry["node_id"]
        if not isinstance(node, str) or node_suffix(node) not in images:
            usage_error(f"{where}: {node!r} is neither the referenced node nor a viewport variant")
        if node_suffix(node) in carried:
            usage_error(f"{where}: {node!r} appears twice")
        if not all(positive_number(entry[k]) for k in SIZE_KEYS):
            usage_error(f"{where}: {node} sizes must be positive numbers")
        smaller = (entry["width"] + 1 <= entry["original_width"]
                   or entry["height"] + 1 <= entry["original_height"])
        if entry["downscaled"] is not smaller:
            usage_error(f"{where}: {node} downscaled is {entry['downscaled']!r} but its sizes say {smaller!r}")
        carried[node_suffix(node)] = dict({"image": images[node_suffix(node)]},
                                          **{k: entry[k] for k in SIZE_KEYS}, downscaled=smaller)
    return [carried[n] for n in images if n in carried]


def node_suffix(node_id):
    return node_id.replace(":", "-")


def per_variant(path, node_id):
    stem, ext = os.path.splitext(path)
    return f"{stem}-{node_suffix(node_id)}{ext}"


def copy_viewport(entry, out_image, out_context):
    image = per_variant(out_image, entry["node_id"])
    shutil.copyfile(entry["image"], image)
    context = None
    if entry["context"] is not None:
        context = per_variant(out_context, entry["node_id"])
        shutil.copyfile(entry["context"], context)
    return {
        "name": entry["name"],
        "node_id": entry["node_id"],
        "width": entry["width"],
        "image": image,
        "context": context,
    }


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
            "design_context": None,
            "reference_image": image_path,
            "mime": mime,
        }
        write_json(out_json, record)
        print(f"wrote: {out_json}")
        sys.exit(0)

    if mode == "design_tool":
        if len(sys.argv) != 8:
            usage_error("'design_tool' mode expects exactly 6 arguments after the mode")
        _, _, reference_url, provider_json_path, provider_image_path, out_json, out_image, out_context = sys.argv[:8]
        if not os.path.isfile(provider_json_path):
            usage_error(f"'{provider_json_path}' not found")
        if not os.path.isfile(provider_image_path):
            usage_error(f"'{provider_image_path}' not found")

        with open(provider_json_path, encoding="utf-8") as f:
            provider = json.load(f)

        provider_context = provider.get("design_context")
        if provider_context is not None:
            if not isinstance(provider_context, dict) or not isinstance(provider_context.get("code_file"), str):
                usage_error(f"'{provider_json_path}': design_context must be null or an object with a code_file path")
            if not os.path.isfile(provider_context["code_file"]):
                usage_error(f"'{provider_context['code_file']}' not found — design_context names it as the code file")

        viewports = validated_viewports(provider_json_path, provider.get("viewports"))
        screenshots = validated_screenshots(
            provider_json_path, provider.get("screenshots"), provider.get("node_id"), viewports, out_image)

        os.makedirs(os.path.dirname(out_image) or ".", exist_ok=True)
        shutil.copyfile(provider_image_path, out_image)

        design_context = None
        if provider_context is not None:
            os.makedirs(os.path.dirname(out_context) or ".", exist_ok=True)
            shutil.copyfile(provider_context["code_file"], out_context)
            design_context = dict(provider_context)
            design_context["code_file"] = out_context

        record = {
            "source_kind": "design_tool",
            "reference": reference_url,
            "has_values": True,
            "variables": provider.get("variables", {}),
            "geometry": provider.get("geometry"),
            "design_context": design_context,
            "reference_image": out_image,
        }
        if viewports:
            record["viewports"] = [copy_viewport(v, out_image, out_context) for v in viewports]
        if screenshots:
            record["screenshots"] = screenshots
        write_json(out_json, record)
        print(f"wrote: {out_json}")
        sys.exit(0)

    usage_error(f"unknown mode '{mode}' — expected 'image' or 'design_tool'")


if __name__ == "__main__":
    main()
