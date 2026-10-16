#!/usr/bin/env python3
"""MCP end to end through `querya-mcp`, the way a client such as Claude Desktop
uses it: spawn the bridge, speak MCP over its stdio, read the shared fixture
connection and run SQL on it.

    mcp_stdio_check.py --mcp PATH --connection NAME

Needs the app to be running with its MCP server on and QUERYA_MCP_ENDPOINT
pointing at its endpoint file (scripts/dev/headless_mcp_check.sh sets it up).
Exit code 0: every check passed; 1: a check failed.
"""
import argparse
import json
import subprocess
import sys
import threading

failures = []


def check(name, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} {name}" + (f": {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(name)


class Client:
    def __init__(self, exe):
        self.proc = subprocess.Popen(
            [exe], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, bufsize=1)
        self.next_id = 1
        self.stderr = []
        threading.Thread(
            target=lambda: self.stderr.extend(self.proc.stderr), daemon=True).start()

    def send(self, message):
        self.proc.stdin.write(json.dumps(message) + "\n")
        self.proc.stdin.flush()

    def request(self, method, params=None, timeout=30):
        rid = self.next_id
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}})
        result = {}

        def read():
            for line in self.proc.stdout:
                try:
                    message = json.loads(line)
                except ValueError:
                    continue
                if message.get("id") == rid:
                    result["message"] = message
                    return

        reader = threading.Thread(target=read, daemon=True)
        reader.start()
        reader.join(timeout)
        if "message" not in result:
            raise TimeoutError(f"{method}: no answer in {timeout}s; bridge stderr: {''.join(self.stderr)}")
        return result["message"]

    def tool(self, name, arguments=None):
        message = self.request("tools/call", {"name": name, "arguments": arguments or {}})
        if "error" in message:
            return True, message["error"].get("message", "")
        result = message["result"]
        text = "".join(c.get("text", "") for c in result.get("content", []))
        return bool(result.get("isError")), text

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


def as_list(payload, key):
    """The tools answer JSON text: a list, or an object holding the list."""
    value = json.loads(payload)
    if isinstance(value, dict):
        value = value.get(key, [])
    return value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mcp", required=True, help="path to querya-mcp")
    parser.add_argument("--connection", required=True, help="name of the shared fixture connection")
    parser.add_argument("--unshared-id", type=int, required=True,
                        help="id of a connection that exists but is not shared")
    args = parser.parse_args()

    client = Client(args.mcp)
    try:
        init = client.request("initialize", {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "headless-check", "version": "1"},
        })
        check("initialize", "result" in init, json.dumps(init)[:300])
        client.send({"jsonrpc": "2.0", "method": "notifications/initialized"})

        tools = client.request("tools/list")
        names = {t["name"] for t in tools.get("result", {}).get("tools", [])}
        check("tools/list has the SQL tools",
              {"list_connections", "list_tables", "describe_table", "run_query"} <= names,
              f"got {sorted(names)}")

        is_error, text = client.tool("list_connections")
        connections = [] if is_error else as_list(text, "connections")
        mine = [c for c in connections if c.get("name") == args.connection]
        check("list_connections shows only the shared connection",
              not is_error and len(connections) == 1 and len(mine) == 1,
              text[:300])
        if not mine:
            return
        cid = mine[0]["id"]

        is_error, text = client.tool("list_tables", {"connection_id": cid})
        tables = [] if is_error else as_list(text, "tables")
        check("list_tables finds the fixture table",
              not is_error and any(t.get("name") == "items" for t in tables), text[:300])

        is_error, text = client.tool("describe_table", {"connection_id": cid, "table": "items"})
        check("describe_table lists the columns",
              not is_error and "price" in text, text[:300])

        is_error, text = client.tool(
            "run_query", {"connection_id": cid, "sql": "SELECT count(*) AS n, sum(price) AS total FROM items"})
        ok = False
        if not is_error:
            data = json.loads(text)
            rows = data.get("rows", [])
            ok = len(rows) == 1 and [int(float(v)) for v in rows[0]] == [3, 60]
        check("run_query returns the fixture data (3 rows, total 60)", ok, text[:300])

        is_error, text = client.tool(
            "run_query", {"connection_id": cid, "sql": "DELETE FROM items"})
        check("run_query refuses a write", is_error, text[:300])

        is_error, text = client.tool(
            "run_query", {"connection_id": cid, "sql": "SELECT count(*) AS n FROM items"})
        still = False
        if not is_error:
            still = int(float(json.loads(text)["rows"][0][0])) == 3
        check("the refused DELETE changed nothing", still, text[:300])

        is_error, text = client.tool(
            "run_query", {"connection_id": args.unshared_id, "sql": "SELECT count(*) FROM items"})
        check("a connection that is not shared is refused", is_error, text[:300])
    finally:
        client.close()


if __name__ == "__main__":
    main()
    print(f"{len(failures)} failed" if failures else "all passed")
    sys.exit(1 if failures else 0)
