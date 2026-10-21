#!/usr/bin/env python3
"""Emit a graphql_lab/schema.py with a chosen subset of hardening controls.

Used only by the validation harness to test each control in isolation and in
combination. The learner never sees this; they edit the real schema.py by hand.

Usage: gen_schema.py [introspection] [suggestions] [alias] [depth]
With no flags it prints the pristine, fully-vulnerable schema.
"""
import sys

flags = set(sys.argv[1:])

ext_imports = []
extensions = []
if "introspection" in flags:
    ext_imports.append("DisableIntrospection")
    extensions.append("DisableIntrospection()")
if "alias" in flags:
    ext_imports.append("AddValidationRules")
    extensions.append("AddValidationRules([MaxAliasCountRule])")
if "depth" in flags:
    ext_imports.append("QueryDepthLimiter")
    extensions.append("QueryDepthLimiter(max_depth=5)")

lines = ["import strawberry"]
if "alias" in flags:
    lines.extend([
        "from graphql import GraphQLError",
        "from graphql.validation import ValidationRule",
    ])
if ext_imports:
    inner = ", ".join(sorted(ext_imports))
    lines.append(f"from strawberry.extensions import {inner}")
if "suggestions" in flags:
    lines.append("from strawberry.schema.config import StrawberryConfig")
lines.append("")
lines.append("from blog.schema import Mutation, Query")
if "alias" in flags:
    lines.extend([
        "",
        "MAX_ALIASES = 15",
        "",
        "",
        "class MaxAliasCountRule(ValidationRule):",
        "    def __init__(self, context):",
        "        super().__init__(context)",
        "        self.alias_count = 0",
        "",
        "    def enter_field(self, node, *_args):",
        "        if node.alias is None:",
        "            return",
        "        self.alias_count += 1",
        "        if self.alias_count > MAX_ALIASES:",
        "            self.report_error(",
        "                GraphQLError(",
        '                    f"Too many aliases: {self.alias_count} exceeds the "',
        '                    f"limit of {MAX_ALIASES}.",',
        "                    node,",
        "                )",
        "            )",
    ])
    lines.append("")
lines.append("")

args = ["    query=Query,", "    mutation=Mutation,"]
if "suggestions" in flags:
    args.append("    config=StrawberryConfig(disable_field_suggestions=True),")
if extensions:
    args.append("    extensions=[")
    for e in extensions:
        args.append(f"        {e},")
    args.append("    ],")

lines.append("schema = strawberry.Schema(")
lines.extend(args)
lines.append(")")

print("\n".join(lines))
