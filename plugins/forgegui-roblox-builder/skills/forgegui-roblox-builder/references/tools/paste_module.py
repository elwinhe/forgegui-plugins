"""Make a Luau module pasteable into the Studio MCP's execute_luau.

    python references/tools/paste_module.py references/luau/WorldCheck.luau runner.luau > paste.luau

execute_luau runs in a sandbox that cannot require place modules. This prints the module without
its `--!strict` line and its final `return <Name>`, then the runner, so the runner can use the
module's table by name and return whatever it wants reported.
"""

import re
import sys

RETURN = re.compile(r"return [A-Za-z_][A-Za-z0-9_]*")


def paste(module_source: str, runner_source: str) -> str:
    lines = module_source.rstrip("\n").split("\n")
    if lines and lines[0].startswith("--!"):
        lines = lines[1:]
    if not lines or not RETURN.fullmatch(lines[-1].strip()):
        raise ValueError("the module must end with `return <Name>`")
    body = "\n".join(lines[:-1]).rstrip("\n")
    return f"{body}\n\n{runner_source.strip(chr(10))}\n"


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1], encoding="utf-8") as module, open(sys.argv[2], encoding="utf-8") as runner:
        sys.stdout.write(paste(module.read(), runner.read()))


if __name__ == "__main__":
    main()
