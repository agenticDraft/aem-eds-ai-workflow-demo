---
description: design.fetch_reference — retrieves a Figma node's design values (geometry and variable tokens) and a reference screenshot via the figma marketplace plugin's MCP server. Requires that plugin installed and OAuth-authenticated in this session.
---

# fetch-reference

Implements the `design` role's `fetch_reference` operation: retrieve a Figma node's design
values and a reference screenshot from a real Figma file, through the already-installed `figma`
marketplace plugin's MCP server (`mcp__plugin_figma_figma__*`).

This operation deliberately never calls `get_design_context` or loads the `figma-design-to-code`
skill. Those exist for a different job — generating application code from a design — and bring a
mandatory code-generation workflow this operation has no use for. `get_metadata`,
`get_variable_defs` and `get_screenshot` cover design values and a reference image on their own,
with no such prerequisite.

## Input

One line in the invocation argument:

```
reference: <a figma.com design URL, including a node-id>
```

## Flow

```dot
digraph fetch_reference {
    "Parse the reference URL" [shape=box];
    "URL is a supported Figma design URL with a node id?" [shape=diamond];
    "Load the figma MCP tools" [shape=box];
    "Tools loaded?" [shape=diamond];
    "Fetch node metadata" [shape=box];
    "Metadata fetched?" [shape=diamond];
    "Fetch variable definitions" [shape=box];
    "Variables fetched?" [shape=diamond];
    "Fetch reference screenshot" [shape=box];
    "Screenshot fetched?" [shape=diamond];
    "Classify the tool error" [shape=box];
    "Class is TRANSIENT and attempts remain?" [shape=diamond];
    "Write artifacts" [shape=box];
    "Report pass" [shape=doublecircle];
    "Report fail" [shape=doublecircle];
    "Report question" [shape=doublecircle];

    "Parse the reference URL" -> "URL is a supported Figma design URL with a node id?";
    "URL is a supported Figma design URL with a node id?" -> "Load the figma MCP tools" [label="yes"];
    "URL is a supported Figma design URL with a node id?" -> "Report question" [label="no node-id in the URL"];
    "URL is a supported Figma design URL with a node id?" -> "Report fail" [label="not a supported Figma design URL\nVALIDATION"];
    "Load the figma MCP tools" -> "Tools loaded?";
    "Tools loaded?" -> "Fetch node metadata" [label="yes"];
    "Tools loaded?" -> "Report fail" [label="no\nPERMANENT"];
    "Fetch node metadata" -> "Metadata fetched?";
    "Metadata fetched?" -> "Fetch variable definitions" [label="yes"];
    "Metadata fetched?" -> "Classify the tool error" [label="no"];
    "Fetch variable definitions" -> "Variables fetched?";
    "Variables fetched?" -> "Fetch reference screenshot" [label="yes"];
    "Variables fetched?" -> "Classify the tool error" [label="no"];
    "Fetch reference screenshot" -> "Screenshot fetched?";
    "Screenshot fetched?" -> "Write artifacts" [label="yes"];
    "Screenshot fetched?" -> "Classify the tool error" [label="no"];
    "Classify the tool error" -> "Class is TRANSIENT and attempts remain?";
    "Class is TRANSIENT and attempts remain?" -> "Fetch node metadata" [label="yes — the call that failed"];
    "Class is TRANSIENT and attempts remain?" -> "Fetch variable definitions" [label="yes — the call that failed"];
    "Class is TRANSIENT and attempts remain?" -> "Fetch reference screenshot" [label="yes — the call that failed"];
    "Class is TRANSIENT and attempts remain?" -> "Report fail" [label="no\nTRANSIENT exhausted, or another class"];
    "Write artifacts" -> "Report pass";
}
```

## Node Details

### Parse the reference URL

Take the `reference` value from the input above. Extract:

- **`file_key`** — the path segment right after `/design/`. If the URL instead has the shape
  `.../design/<file_key>/branch/<branch_key>/<file_name>`, use `branch_key` as the `file_key`
  instead (the file key of that branch).
- **`node_id`** — the `node-id` query parameter, exactly as written (e.g. `1-1043`). Every
  `mcp__plugin_figma_figma__*` tool used below accepts a node id in this hyphen form directly, so
  do not convert it.

### URL is a supported Figma design URL with a node id?

- The URL's host is `figma.com` or `www.figma.com` and its path contains `/design/` — otherwise go
  to **Report fail** with `error_class: VALIDATION` (`/file/`, `/board/`, `/slides/` and `/make/`
  URLs are not supported by this operation). The reference itself is wrong, so re-running it
  unchanged cannot succeed.
- The URL has a `node-id` query parameter — otherwise go to **Report question**: a file-only URL
  does not name which frame or node is the reference.
- Both hold — continue to **Load the figma MCP tools**.

### Load the figma MCP tools

Run `ToolSearch` with `query: "select:mcp__plugin_figma_figma__get_metadata,mcp__plugin_figma_figma__get_variable_defs,mcp__plugin_figma_figma__get_screenshot"`.

### Tools loaded?

All three tools resolved to full schemas — continue to **Fetch node metadata**. Any of them still
unresolved means the `figma` plugin is not installed, or is installed but has not completed its
OAuth flow in this session (an unauthenticated connection only exposes `authenticate` and
`complete_authentication`, never the tools above) — go to **Report fail** with
`error_class: PERMANENT`, naming that the `figma` plugin must be installed and authenticated before
this operation can run. Nothing about the request is wrong; this operation cannot run here at all.

### Fetch node metadata

Call `mcp__plugin_figma_figma__get_metadata` with the parsed `file_key` and `node_id`. This
confirms the node exists and returns its name and geometry (`x`, `y`, `width`, `height`) as XML
attributes on the matching element.

### Metadata fetched?

The call returned the node's XML element — continue to **Fetch variable definitions**. The call
errored (file or node not found, no access, or any other tool error) — **Classify the tool error**
below, then go to **Report fail**, naming the error exactly as returned, never guessed or reworded
into something more general.

### Fetch variable definitions

Call `mcp__plugin_figma_figma__get_variable_defs` with the same `file_key` and `node_id`. It
returns a flat map of variable name to value (colors, spacing, or any other token the node uses).
An **empty** map is a normal, successful result — most nodes use no variables at all — and is not
itself a reason to go to **Report fail**.

### Variables fetched?

The call returned (even an empty map) — continue to **Fetch reference screenshot**. The call
errored — **Classify the tool error** below, then go to **Report fail**, naming the error exactly as
returned.

### Fetch reference screenshot

Call `mcp__plugin_figma_figma__get_screenshot` with the same `file_key` and `node_id`. It returns
a short-lived `image_url` plus `width`/`height`. That URL is treated like a secret, per the tool's
own description — never write it into the envelope, a log, or any other file; it exists only long
enough for the next step's download.

### Screenshot fetched?

The call returned an `image_url` — continue to **Write artifacts**. The call errored — **Classify
the tool error** below, then go to **Report fail**, naming the error exactly as returned.

### Classify the tool error

The three tool calls above reach this node by the same edge, and the class is read off what
the tool actually returned — never off which call it was, and never off what usually goes wrong.
Match in this order and stop at the first that holds:

1. The error names a rate limit, a quota or credit window, or a timeout — `429`, `rate limit`,
   `quota`, `credit limit`, `timed out`. → **`TRANSIENT`**. The request is well formed and the file
   is reachable; the provider is refusing right now and could accept the same call later.
2. The error names the file or the node as not found, or the node id as malformed — `not found`,
   `no such node`, `invalid node`. → **`VALIDATION`**. The reference names something the provider
   has no record of, so re-running it unchanged cannot succeed.
3. The error names authentication, authorization or access — `401`, `403`, `unauthorized`,
   `forbidden`, `no access`, `token expired`. → **`PERMANENT`**. The credential this session holds
   cannot reach this resource, and retrying does not change that.
4. Anything else. → **`PERMANENT`**, the class that permits no recovery, because an unrecognised
   error is not evidence that retrying is safe. Quote the error verbatim in the escalation text
   above the block so a reader can see what the classification was made from.

Carry the class to **Class is TRANSIENT and attempts remain?**.

`../../../agentic-core/shared/error-handling.md` is the authority on what each class means and what
recovery each one permits; this node applies it, it does not restate it.

### Class is TRANSIENT and attempts remain?

`TRANSIENT` is the only class that permits a retry, and it permits exactly two — back off 2 seconds,
then 4 seconds. Fewer than two retries have run and the class is `TRANSIENT`: go back to whichever
of **Fetch node metadata**, **Fetch variable definitions** or **Fetch reference screenshot** raised
the error, and re-run only that call. Otherwise — the class is `VALIDATION` or `PERMANENT`, or the
third `TRANSIENT` attempt has just failed — go to **Report fail**, carrying the class determined
above.

An exhausted `TRANSIENT` reports `fail`, not a question of this operation's own. This operation
cannot see whether the stage that called it has an alternative source available, so a question
raised from here would ask a human for something the caller could still have resolved by itself.
The stage raises it, at its own boundary, if it has nothing left.

### Write artifacts

1. Ensure `.ai/figma/` exists at the project root (`mkdir -p .ai/figma`).
2. Download the screenshot immediately, before doing anything else, to
   `.ai/figma/<file_key>-<node_id>.png` — e.g. `curl -sS -L -o ".ai/figma/<file_key>-<node_id>.png" "<image_url>"`.
3. Write `.ai/figma/<file_key>-<node_id>.json`, an object with: `reference` (the original input
   URL), `file_key`, `node_id`, `node_name` (from the metadata step), `geometry` (the `x`/`y`/
   `width`/`height` from the metadata step), and `variables` (the map from the variable-defs step,
   verbatim — including an empty object when it was empty).
4. Continue to **Report pass**.

### Report pass

Emit the `## Result` block as plain `key: value` lines per `../../../agentic-core/shared/result-envelope.md` — never as a bulleted or backtick-wrapped list, with `verdict:` as the very next line, nothing between it and the heading, and never followed by anything else — not even a summary explicitly labeled as commentary or "not part of the envelope"; if that's worth writing, put it before the heading instead, where it is already sanctioned. Fields:

- `verdict: pass`
- `summary`: one sentence, 200 characters or fewer (the envelope's hard cap — an oversized summary fails validation and takes the whole run to `failed`) naming the node and the Figma file the reference came from.
- `artifacts` (always a YAML list — `artifacts:` then `  - <path>` per line; even a single path is a list, never an inline scalar): both files written above, `.ai/figma/<file_key>-<node_id>.json` and
  `.ai/figma/<file_key>-<node_id>.png`.
- `next_action: none`
- `metrics: variables=<count of entries in the variable map>`

### Report fail

Emit the `## Result` block as plain `key: value` lines per `../../../agentic-core/shared/result-envelope.md` — never as a bulleted or backtick-wrapped list, with `verdict:` as the very next line, nothing between it and the heading, and never followed by anything else — not even a summary explicitly labeled as commentary or "not part of the envelope"; if that's worth writing, put it before the heading instead, where it is already sanctioned. Fields:

- `verdict: fail`
- `summary`: one sentence, 200 characters or fewer (the envelope's hard cap — an oversized summary fails validation and takes the whole run to `failed`) naming what went wrong — the unsupported URL shape, the missing/
  unauthenticated `figma` plugin, or the tool error that was returned. Never a guess at the cause.
- `artifacts: []`
- `next_action: none`
- `error_class`: the class that brought the flow here, on **every** path into this node and never
  omitted — `VALIDATION` from **URL is a supported Figma design URL with a node id?**, `PERMANENT`
  from **Tools loaded?**, and whatever **Classify the tool error** determined for the three tool
  calls. The caller branches on this, so it is read off what actually failed, never off what
  usually fails.

### Report question

Emit the `## Result` block as plain `key: value` lines per `../../../agentic-core/shared/result-envelope.md` — never as a bulleted or backtick-wrapped list, with `verdict:` as the very next line, nothing between it and the heading, and never followed by anything else — not even a summary explicitly labeled as commentary or "not part of the envelope"; if that's worth writing, put it before the heading instead, where it is already sanctioned. Fields:

- `verdict: question`
- `summary`: one sentence, 200 characters or fewer (the envelope's hard cap — an oversized summary fails validation and takes the whole run to `failed`) — the given URL has no node-id.
- `artifacts: []`
- `next_action: none`
- `question`: ask which frame or node in the file should be the design reference.
- `blocker`: the reference URL has no `node-id`.

This node reports no `error_class`: a URL with no node id is a clarification the item's author can
answer, not a classified failure of this operation.
