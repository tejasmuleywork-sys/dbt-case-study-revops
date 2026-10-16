#!/usr/bin/env python3
"""
Project rules dbt itself does not enforce. Reads target/manifest.json (from `dbt parse`), so it needs
no warehouse connection and runs in seconds on every PR.

    python scripts/ci/check_project_rules.py target/manifest.json [--state prod-state/manifest.json]

Errors fail the PR. Warnings are shown as annotations on the PR but do not block.
Every rule exists because breaking it caused (or would cause) a real incident: see the RULES list.
"""
import argparse
import json
import re
import sys

# Layer of a node, from its folder. Lower rank = further upstream.
LAYERS = [
    # (path prefix,               layer,          rank, naming regex)
    ("models/staging/",           "staging",      1, r"^stg_[a-z0-9]+__[a-z0-9_]+$"),
    ("snapshots/",                "snapshot",     2, r"^snap_[a-z0-9]+__[a-z0-9_]+$"),
    ("models/intermediate/",      "intermediate", 3, r"^int_[a-z0-9_]+__[a-z0-9_]+$"),
    ("models/marts/core/",        "core",         4, r"^(dim|fct)_[a-z0-9_]+$"),
    ("models/marts/revops/",      "revops",       5, r"^mart_revops__[a-z0-9_]+$"),
    ("models/audit/",             "audit",        6, r"^audit_[a-z0-9_]+$"),
]
SAME_LAYER_REFS_OK = {"intermediate", "core", "revops", "audit"}   # staging is 1:1 with a source: no stg -> stg
SOURCE_ALLOWED = {"staging", "audit"}                              # audit reconciles marts back to RAW on purpose
DOCUMENTED_LAYERS = {"core", "revops", "audit"}                    # BI-facing: description + PK test required
GOOD_SCHEMA_CHANGE = {"append_new_columns", "sync_all_columns", "fail"}
HARDCODED_DB = re.compile(r"\b(raw|gold|analytics|gold_ci)\s*\.\s*\"?[a-z_][a-z0-9_]*\"?\s*\.", re.I)

errors, warnings = [], []


def report(level, node, msg):
    path = node.get("original_file_path", "")
    (errors if level == "error" else warnings).append((path, f"{node['name']}: {msg}"))


def layer_of(node):
    path = node.get("original_file_path", "")
    for prefix, layer, rank, naming in LAYERS:
        if path.startswith(prefix):
            return layer, rank, naming
    if node["resource_type"] == "seed":
        return "seed", 0, None
    return None, None, None


def strip_comments(sql):
    sql = re.sub(r"\{#.*?#\}", "", sql, flags=re.S)
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    return re.sub(r"--[^\n]*", "", sql)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("--state", help="prod manifest.json, enables change-aware warnings")
    args = ap.parse_args()

    manifest = json.load(open(args.manifest))
    nodes = manifest["nodes"]
    prod_nodes = json.load(open(args.state))["nodes"] if args.state else {}

    project = manifest["metadata"].get("project_name")
    own = {uid: n for uid, n in nodes.items()
           if n.get("package_name", project) == project and n["resource_type"] in ("model", "snapshot", "seed")}

    # tests attached to each node (unique / unique_combination_of_columns = a primary key is declared)
    pk_tested = set()
    for n in nodes.values():
        if n["resource_type"] != "test":
            continue
        name = (n.get("test_metadata") or {}).get("name")
        if name in ("unique", "unique_combination_of_columns"):
            attached = n.get("attached_node") or next(iter(n["depends_on"]["nodes"]), None)
            pk_tested.add(attached)

    exposed = set()
    for e in manifest.get("exposures", {}).values():
        exposed.update(e["depends_on"]["nodes"])

    for uid, node in own.items():
        if node["resource_type"] == "seed":
            continue
        layer, rank, naming = layer_of(node)
        cfg = node.get("config", {})

        # R1 every model lives in a known layer and follows its naming convention
        if layer is None:
            report("error", node, "is outside the known layer folders (staging/intermediate/marts/core|revops/audit)")
            continue
        if naming and not re.match(naming, node["name"]):
            report("error", node, f"name does not match the {layer} convention {naming}")

        # R2 dependencies only flow downstream (the bug we hit: an intermediate model reading a mart)
        for dep in node["depends_on"]["nodes"]:
            if dep.startswith("source."):
                # R3 raw data is read in exactly one place
                if layer not in SOURCE_ALLOWED:
                    report("error", node, f"reads {dep} directly; only staging (and audit) may use source()")
                continue
            parent = nodes.get(dep)
            if parent is None or parent.get("package_name", project) != project:
                continue
            p_layer, p_rank, _ = layer_of(parent)
            if p_rank is None:
                continue
            if p_rank > rank or (p_rank == rank and layer not in SAME_LAYER_REFS_OK):
                report("error", node, f"{layer} model depends on {p_layer} model {parent['name']} (dependencies must flow downstream)")

        # R4 hard-coded database names break dev/CI isolation and environment promotion
        if HARDCODED_DB.search(strip_comments(node.get("raw_code", ""))):
            report("error", node, "hard-coded database.schema reference: use ref()/source()")

        # R5 incremental models must be safe to re-run and to evolve
        if cfg.get("materialized") == "incremental":
            if not cfg.get("unique_key"):
                report("error", node, "incremental without unique_key: re-runs and the lookback window would duplicate rows")
            if cfg.get("on_schema_change", "ignore") not in GOOD_SCHEMA_CHANGE:
                report("error", node, "incremental with on_schema_change=ignore: a new column would silently never appear")

        if node["resource_type"] != "model":
            continue

        # R6 BI-facing models are documented and declare a primary key
        if layer in DOCUMENTED_LAYERS:
            if not (node.get("description") or "").strip():
                report("error", node, "BI-facing model has no description")
            if uid not in pk_tested:
                report("error", node, "no unique / unique_combination_of_columns test: grain is not guaranteed")
        elif not (node.get("description") or "").strip():
            report("warning", node, "no description")

        # R7 anything a dashboard reads should have a contract (names and types cannot drift)
        if uid in exposed and not (cfg.get("contract") or {}).get("enforced"):
            report("warning", node, "is used by an exposure but has no enforced contract")

        # R8 change-aware: a protected (full_refresh=false) model was edited -> history cannot be rebuilt
        if prod_nodes and cfg.get("full_refresh") is False and uid in prod_nodes:
            if prod_nodes[uid].get("checksum", {}).get("checksum") != node.get("checksum", {}).get("checksum"):
                report("warning", node,
                       "is full_refresh=false and was changed: its history cannot be rebuilt. "
                       "Add a migration note to the PR (new columns only append; type changes need a manual plan).")

    for path, msg in warnings:
        print(f"::warning file={path},title=dbt project rule::{msg}")
    for path, msg in errors:
        print(f"::error file={path},title=dbt project rule::{msg}")
    print(f"\nProject rules: {len(errors)} error(s), {len(warnings)} warning(s), {len(own)} nodes checked.")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
