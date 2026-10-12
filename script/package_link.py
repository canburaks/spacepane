"""Locate library objects from the selected SwiftPM output for CLT host tools."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def package_objects(bin_dir: Path) -> list[Path]:
    package = json.loads(subprocess.check_output([
        "/usr/bin/xcrun", "swift", "package", "--package-path",
        str(ROOT / "Packages/PreviewCore"), "dump-package",
    ]))
    targets = {target["name"]: target for target in package["targets"]}
    ordered = []
    visited = set()

    def include(name):
        if name in visited:
            return
        visited.add(name)
        target = targets.get(name)
        if target is None or target["type"] != "regular":
            raise SystemExit(f"Unsupported package link target: {name}")
        for dependency in target["dependencies"]:
            reference = dependency.get("byName") or dependency.get("target")
            if not reference:
                raise SystemExit(f"Add explicit external product linking for {name}")
            include(reference[0])
        ordered.append(name)

    for product in package["products"]:
        for name in product["targets"]:
            include(name)
    description_path = bin_dir / "description.json"
    commands = json.loads(description_path.read_text()).get("swiftCommands", {}) if description_path.is_file() else {}
    objects = []
    for target in ordered:
        aggregate = bin_dir / f"{target}.o"
        target_dir = bin_dir / f"{target}.build"
        output_map = target_dir / "output-file-map.json"
        emitted = [command for command in commands.values() if command.get("moduleName") == target]
        if emitted:
            # Release output maps may contain both per-source paths and an inactive whole-module
            # placeholder. The current build description records which objects the compiler emits.
            # Existing files are not a mode detector: old emission modes can remain in the cache.
            if len(emitted) != 1 or not isinstance(emitted[0].get("objects"), list):
                raise SystemExit(f"Invalid current object inventory for {target} in {bin_dir}.")
            target_objects = list(dict.fromkeys(Path(path) for path in emitted[0]["objects"]))
            if any(not path.is_file() for path in target_objects):
                raise SystemExit(f"Missing current objects for {target} in {bin_dir}. Build the package first.")
        elif output_map.is_file():
            # Incremental SwiftPM builds keep .o files for removed/renamed sources. The active
            # compiler map, including its whole-module entry, is the link inventory; a glob can
            # accidentally resurrect deleted code or pull an old unresolved dependency into a host.
            entries = json.loads(output_map.read_text())
            target_objects = list(dict.fromkeys(Path(entry["object"]) for entry in entries.values()
                                                if "object" in entry))
            if any(not path.is_file() for path in target_objects):
                raise SystemExit(f"Missing current objects for {target} in {bin_dir}. Build the package first.")
        else:
            # Older aggregate layouts and the small Clang shim targets do not emit a Swift map.
            target_objects = [aggregate] if aggregate.is_file() else sorted(target_dir.rglob("*.o"))
        if not target_objects:
            raise SystemExit(f"No linkable objects for {target} in {bin_dir}. Build the package first.")
        objects.extend(target_objects)
    return list(dict.fromkeys(objects))


def package_module_flags(bin_dir: Path) -> list[str]:
    # SwiftPM emits top-level maps for C targets; Swift generated-header maps live
    # in include/ and must not be imported as a second copy of their Swift module.
    flags = []
    for module_map in sorted(bin_dir.glob('*.build/module.modulemap')):
        flags.extend(['-Xcc', f'-fmodule-map-file={module_map}'])
    return flags


if __name__ == '__main__':
    import sys
    print('\n'.join(package_module_flags(Path(sys.argv[1]))))
