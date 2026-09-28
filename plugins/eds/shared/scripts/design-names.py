#!/usr/bin/env python3
"""Name the designs that share a base name, independent of their order (D525).

A library, loaded by the scripts that name a file or unit after a design:

  content_key(data)        SHA-256 hex of a file's bytes
  component_key(values)    SHA-256 hex of a component's canonical values: JSON
                           with sorted keys and no whitespace, so key order and
                           formatting never tell two components apart
  split_names(designs, held=None)
                           designs: (base, key) pairs, key a 64-hex SHA-256.
                           held(name) returns the key the project already holds
                           under name, or None.
                           Returns {(base, key): name}.

A base used by one key, and held by no other, keeps the base. A base shared by
different keys, or held by another key, is split: every key under it gets
<base>-<hash4>, the first 4 hex of its key, the first occurrence included. Two
keys equal in their first 4 hex both widen to 8. A <base>-<hash4> held by
another key widens that one key to 8. A held base is never renamed, and nothing
here decides between two keys: an 8-wide name still taken is returned as is,
and the caller's own existing-file check reports it.
"""

import hashlib
import json


def content_key(data):
    return hashlib.sha256(data).hexdigest()


def component_key(values):
    canonical = json.dumps(values, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def split_names(designs, held=None):
    held = held or (lambda name: None)
    groups = {}
    for base, key in designs:
        groups.setdefault(base, set()).add(key)
    names = {}
    for base in sorted(groups):
        keys = sorted(groups[base])
        holder = held(base)
        if len(keys) == 1 and holder in (None, keys[0]):
            names[(base, keys[0])] = base
            continue
        for key in keys:
            width = 8 if any(k != key and k[:4] == key[:4] for k in keys) else 4
            name = f"{base}-{key[:width]}"
            if width == 4 and held(name) not in (None, key):
                name = f"{base}-{key[:8]}"
            names[(base, key)] = name
    return names
