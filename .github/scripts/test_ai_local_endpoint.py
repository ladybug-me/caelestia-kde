#!/usr/bin/env python3
"""Tests for the OpenAI-compatible endpoint URL built from a host and port.

`Paths.openaiCompatBase()` in shell/utils/Paths.qml assembles the base URL that
both the AI sidebar and the AI settings page use to reach a user-supplied
llama.cpp llama-server (or any other OpenAI-compatible endpoint). It is
deliberately forgiving about what people paste into the host field, which is
exactly the kind of string handling that fails quietly: a doubled /v1 path or a
literal ":undefined" only shows up much later as a request that never succeeds.

The functions are extracted from the real QML and executed by a JS engine, so
these tests exercise the shipped code rather than a copy of it. If a function is
renamed or moved, extraction fails loudly instead of the suite quietly passing
against stale expectations.

Skipped when no JS engine is installed, so a minimal container reports "not
checked" rather than a failure unrelated to the code under test.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any, Optional, Sequence

ROOT = Path(__file__).resolve().parents[2]
PATHS_QML = ROOT / "shell" / "utils" / "Paths.qml"

# (label, host, port, expected URL)
Case = Sequence[Any]

# A case list is [label, host, port, expected]; the host and port may be None to
# stand for an unset config field.
PREAMBLE = r"""
const fs = require("fs");
// argv[0] is the interpreter and argv[1] this script, so the arguments the caller
// appended start at argv[2].
const qml = fs.readFileSync(process.argv[2], "utf8");

// The QML singleton's own id, so a body that calls another function through
// `root.` resolves to the real one. Filled in as functions are extracted.
const singleton = {};

function extract(name) {
    const start = qml.indexOf("function " + name + "(");
    if (start === -1)
        throw new Error(name + "() not found in Paths.qml");
    const braceStart = qml.indexOf("{", start);
    let depth = 0;
    let end = braceStart;
    for (; end < qml.length; end++) {
        if (qml[end] === "{") depth++;
        else if (qml[end] === "}") {
            depth--;
            if (depth === 0) {
                end++;
                break;
            }
        }
    }
    // QML allows `name: type` annotations that plain JS does not.
    const sig = qml
        .slice(start + ("function " + name).length, braceStart)
        .replace(/: string/g, "")
        .replace(/: int/g, "")
        .replace(/: bool/g, "")
        .replace(/: url/g, "");
    const src = "return function " + name + sig + qml.slice(braceStart, end);
    return new Function("root", src)(singleton);
}

const RUNNER = process.argv[3];
const cases = JSON.parse(process.argv[4]);
const failures = [];

if (RUNNER === "hostPort") {
    const hostPort = extract("hostPort");
    for (const [label, host, port, expected] of cases) {
        const actual = hostPort(host, port);
        if (actual !== expected)
            failures.push(label + ": expected " + expected + ", got " + actual);
    }
} else {
    singleton.hostPort = extract("hostPort");
    const openaiCompatBase = extract("openaiCompatBase");
    for (const [label, host, port, expected] of cases) {
        const actual = openaiCompatBase(host, port);
        if (actual !== expected)
            failures.push(label + ": expected " + expected + ", got " + actual);
    }
}

console.log(JSON.stringify(failures));
process.exit(failures.length === 0 ? 0 : 1);
"""


def find_engine() -> Optional[list[str]]:
    for name in ("node", "qjs"):
        if shutil.which(name) is None:
            continue
        result = subprocess.run([name, "-e", "0"], capture_output=True, text=True)
        if result.returncode == 0:
            return [name]
    return None


class OpenAiCompatEndpointTests(unittest.TestCase):
    def setUp(self) -> None:
        engine = find_engine()
        if engine is None:
            self.skipTest("no JS engine (node/qjs) installed to run the Paths.qml functions")
        self.engine: list[str] = engine
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        harness = Path(self._tmp.name) / "harness.js"
        harness.write_text(PREAMBLE, encoding="utf-8")
        self.harness = harness

    def assert_urls(self, runner: str, cases: Sequence[Case]) -> None:
        result = subprocess.run(
            [*self.engine, str(self.harness), str(PATHS_QML), runner, json.dumps(cases)],
            capture_output=True,
            text=True,
        )
        # A non-zero exit with nothing on stdout means the harness could not even
        # extract the function (renamed, moved, or a syntax the engine rejects).
        # That is a failure, not a list of mismatches to print.
        if result.returncode != 0 and not result.stdout.strip():
            self.fail(f"harness could not run {runner}():\n{result.stderr.strip()}")
        failures = json.loads(result.stdout or "[]")
        self.assertEqual(failures, [], "\n".join(failures))

    def test_a_typed_host_and_port_resolve_to_that_endpoint(self) -> None:
        """The ordinary case: a bare host, including a non-default port."""
        self.assert_urls("openaiCompatBase", [
            ["router on loopback", "127.0.0.1", 8989, "http://127.0.0.1:8989/v1"],
            ["router by name", "localhost", 8989, "http://localhost:8989/v1"],
            ["router on the LAN", "192.168.0.126", 8989, "http://192.168.0.126:8989/v1"],
            ["llama-server default", "localhost", 8080, "http://localhost:8080/v1"],
        ])

    def test_a_pasted_url_never_doubles_the_port_or_the_v1_path(self) -> None:
        """People paste whole URLs; none of these may end up with a doubled suffix."""
        self.assert_urls("openaiCompatBase", [
            ["scheme and port kept", "http://192.168.0.126:8989", 8080, "http://192.168.0.126:8989/v1"],
            ["already ends in /v1", "http://192.168.0.126:8989/v1", 8080, "http://192.168.0.126:8989/v1"],
            ["slash after /v1", "192.168.0.126:8989/v1/", 8080, "http://192.168.0.126:8989/v1"],
            ["slash after host:port", "192.168.0.126:8989/", 8080, "http://192.168.0.126:8989/v1"],
            ["https kept", "https://example.com:8443", 8080, "https://example.com:8443/v1"],
        ])

    def test_a_blank_field_falls_back_instead_of_building_a_broken_url(self) -> None:
        """An empty host or port must never produce ':undefined' or ':0'."""
        self.assert_urls("openaiCompatBase", [
            ["empty host", "", 8080, "http://localhost:8080/v1"],
            ["whitespace host", "   ", 8080, "http://localhost:8080/v1"],
            ["unset host", None, 8080, "http://localhost:8080/v1"],
            ["zero port", "localhost", 0, "http://localhost:8080/v1"],
            ["unset port", "localhost", None, "http://localhost:8080/v1"],
            ["host that is only /v1", "localhost/v1", 8080, "http://localhost:8080/v1"],
        ])

    def test_an_ipv6_literal_keeps_the_port_inside_the_brackets(self) -> None:
        """The port belongs inside [], or the resulting URL is unparseable."""
        self.assert_urls("openaiCompatBase", [
            ["bracketed literal", "[::1]", 8989, "http://[::1]:8989/v1"],
            ["bracketed with a port", "[::1]:8989", 8080, "http://[::1]:8989/v1"],
            ["longer literal", "[fe80::1]", 8989, "http://[fe80::1]:8989/v1"],
            # An unbracketed literal is left exactly as typed rather than mangled.
            ["unbracketed left alone", "::1", 8989, "http://::1/v1"],
        ])

    def test_host_port_does_not_replace_a_port_the_user_already_gave(self) -> None:
        """hostPort() backs the base URL, so its own rules are worth pinning."""
        self.assert_urls("hostPort", [
            ["bare host gains the port", "localhost", 8080, "localhost:8080"],
            ["existing port kept", "example.com:9999", 8080, "example.com:9999"],
            ["empty host falls back", "", 8080, "localhost:8080"],
            ["bracketed literal", "[::1]", 8080, "[::1]:8080"],
            ["bracketed literal with a port", "[::1]:9999", 8080, "[::1]:9999"],
            ["surrounding whitespace trimmed", "  example.com  ", 8080, "example.com:8080"],
        ])


if __name__ == "__main__":
    unittest.main()
