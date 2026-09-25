"""Make a Luau module pasteable into the Studio MCP's execute_luau.

    python references/tools/paste_module.py references/luau/WorldCheck.luau runner.luau > paste.luau
    python references/tools/paste_module.py references/luau/A.luau references/luau/B.luau runner.luau > paste.luau

execute_luau runs in a sandbox that cannot require place modules. With one module this prints the
module without its `--!strict` line and its final `return <Name>`, then the runner, so the runner can
use the module's table by name and return whatever it wants reported.

With several modules (the last argument is always the runner) each module is wrapped as
`local <Name> = (function() ... return <Name> end)()`, so their top-level locals and types cannot
collide; `export type` becomes a plain `type`, since exports are only allowed at the top level.
"""

import re
import sys

RETURN = re.compile(r"return ([A-Za-z_][A-Za-z0-9_]*)")
EXPORT = re.compile(r"^export type ", re.MULTILINE)


def _split(module_source: str) -> tuple[str, str]:
    """(body without the mode line and the final return, module name)."""
    lines = module_source.rstrip("\n").split("\n")
    if lines and lines[0].startswith("--!"):
        lines = lines[1:]
    match = RETURN.fullmatch(lines[-1].strip()) if lines else None
    if not match:
        raise ValueError("the module must end with `return <Name>`")
    return "\n".join(lines[:-1]).rstrip("\n"), match.group(1)


def paste(module_source: str, runner_source: str) -> str:
    body, _ = _split(module_source)
    return f"{body}\n\n{runner_source.strip(chr(10))}\n"


def paste_many(module_sources: list[str], runner_source: str) -> str:
    if len(module_sources) == 1:
        return paste(module_sources[0], runner_source)
    parts = []
    for source in module_sources:
        body, name = _split(source)
        parts.append(f"local {name} = (function()\n{EXPORT.sub('type ', body)}\n\nreturn {name}\nend)()\n")
    return "\n".join(parts) + f"\n{runner_source.strip(chr(10))}\n"


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    sources = []
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8") as handle:
            sources.append(handle.read())
    sys.stdout.write(paste_many(sources[:-1], sources[-1]))


if __name__ == "__main__":
    main()
