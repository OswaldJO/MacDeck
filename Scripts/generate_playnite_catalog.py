#!/usr/bin/env python3
"""
Reads Playnite emulator definitions (emulator.yaml) and emits BuiltinEmulatorCatalog.json.
Source: https://github.com/JosefNemec/Playnite (Emulation/Emulators/*/emulator.yaml)
Re-run when updating the vendored catalog from a newer Playnite tree.
"""
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Requires PyYAML: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/Playnite")
    emu_dir = root / "source" / "Playnite" / "Emulation" / "Emulators"
    out = Path(__file__).resolve().parent.parent / "Sources" / "MacGameLibrary" / "Resources" / "BuiltinEmulatorCatalog.json"
    if not emu_dir.is_dir():
        print(f"Missing Playnite emulators dir: {emu_dir}", file=sys.stderr)
        sys.exit(1)

    records = []
    for yaml_path in sorted(emu_dir.glob("*/emulator.yaml")):
        try:
            raw = yaml_path.read_text(encoding="utf-8")
            data = yaml.safe_load(raw)
        except Exception as e:
            print(f"Skip {yaml_path}: {e}", file=sys.stderr)
            continue
        if not isinstance(data, dict):
            continue
        emu_id = data.get("Id") or yaml_path.parent.name
        emu_name = data.get("Name") or emu_id
        website = data.get("Website")
        profiles = data.get("Profiles") or []
        if not isinstance(profiles, list):
            continue
        for prof in profiles:
            if not isinstance(prof, dict):
                continue
            args = prof.get("StartupArguments")
            if not args:
                continue
            args_str = str(args).replace("{ImagePath}", "{rom}")
            pname = prof.get("Name") or "Default"
            platforms = prof.get("Platforms") or []
            if not isinstance(platforms, list):
                platforms = []
            exts = prof.get("ImageExtensions") or []
            if not isinstance(exts, list):
                exts = []
            exe_hint = prof.get("StartupExecutable")
            catalog_id = len(records)
            records.append(
                {
                    "catalogId": catalog_id,
                    "emulatorId": str(emu_id),
                    "emulatorName": str(emu_name),
                    "website": website,
                    "profileName": str(pname),
                    "startupArguments": args_str,
                    "platforms": [str(p) for p in platforms],
                    "imageExtensions": [str(x) for x in exts],
                    "startupExecutableHint": str(exe_hint) if exe_hint else None,
                }
            )

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(records, indent=0, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {len(records)} profiles to {out}")


if __name__ == "__main__":
    main()
