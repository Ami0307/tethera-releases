#!/usr/bin/env python3
"""Helpers for .github/workflows/ios-release.yml (SideStore / AltStore source upkeep).

    sidestore.py inspect --ipa X.ipa [--archive X.xcarchive] --bundle-id ID [--tag v1.2] ...
    sidestore.py notes --message-file tag.txt --sidestore-out a.md --release-out b.md
    sidestore.py update-source --source sidestore/source.json ... --keep-out keep.txt

inspect        Reads version / build / bundle id from the archive's Info.plist
               (ApplicationProperties) when an archive is given, otherwise from the app
               inside the IPA, cross-checks the two, and prints KEY=VALUE lines for
               $GITHUB_OUTPUT. Optionally fails on non-ASCII CFBundleName /
               CFBundleDisplayName (SideStore registers an App ID per extension from
               these names and Apple rejects non-ASCII ones).
notes          Splits an annotated tag message into release notes: the first line is
               the title and is dropped; a line that is exactly `---` ends the part
               shown in SideStore, everything goes into the GitHub Release.
update-source  Adds or replaces this version in source.json (same version: replace in
               place; new version: first), keeps the newest N, refreshes the legacy
               single-version fields and appPermissions, and writes the kept versions.

Standard library only; run with `python3 -I`.
"""
import argparse
import hashlib
import json
import os
import plistlib
import re
import sys
import zipfile

APP_PLIST = re.compile(r"^Payload/[^/]+\.app/Info\.plist$")
BUNDLE_PLIST = re.compile(r"^Payload/[^/]+\.app/(?:(?:PlugIns|Extensions)/[^/]+\.appex/)?Info\.plist$")
NAME_KEYS = ("CFBundleName", "CFBundleDisplayName")


def fail(message):
    print(f"sidestore.py: {message}", file=sys.stderr)
    sys.exit(1)


def version_key(version):
    parts = version.split(".")
    if not all(p.isdigit() for p in parts):
        return None
    return tuple(int(p) for p in parts)


def app_info_from_ipa(ipa):
    with zipfile.ZipFile(ipa) as z:
        names = [n for n in z.namelist() if APP_PLIST.match(n)]
        if len(names) != 1:
            fail(f"{ipa}: expected one Payload/*.app/Info.plist, found {len(names)}")
        return plistlib.loads(z.read(names[0]))


def non_ascii_names(ipa):
    problems = []
    with zipfile.ZipFile(ipa) as z:
        for name in z.namelist():
            if BUNDLE_PLIST.match(name):
                info = plistlib.loads(z.read(name))
                for key in NAME_KEYS:
                    value = info.get(key)
                    if isinstance(value, str) and not value.isascii():
                        problems.append(f"{name}: {key} = {value!r}")
    return problems


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def cmd_inspect(args):
    info = app_info_from_ipa(args.ipa)
    ipa_meta = {
        "version": str(info.get("CFBundleShortVersionString", "")),
        "build": str(info.get("CFBundleVersion", "")),
        "bundle_id": str(info.get("CFBundleIdentifier", "")),
    }
    meta = dict(ipa_meta)
    if args.archive:
        with open(os.path.join(args.archive, "Info.plist"), "rb") as f:
            props = plistlib.load(f).get("ApplicationProperties") or {}
        meta = {
            "version": str(props.get("CFBundleShortVersionString", "")),
            "build": str(props.get("CFBundleVersion", "")),
            "bundle_id": str(props.get("CFBundleIdentifier", "")),
        }
        if meta != ipa_meta:
            fail(f"archive Info.plist {meta} disagrees with the app in the IPA {ipa_meta}")
    for key, value in meta.items():
        if not value:
            fail(f"no {key} in the app's Info.plist")
    if meta["bundle_id"] != args.bundle_id:
        fail(f"bundle id is {meta['bundle_id']}, expected {args.bundle_id}")
    if args.tag and args.require_tag_match:
        tag_version = re.sub(r"^[^0-9]*", "", args.tag)
        if tag_version != meta["version"]:
            fail(f"tag {args.tag} does not match CFBundleShortVersionString {meta['version']}")
    if args.check_ascii:
        problems = non_ascii_names(args.ipa)
        if problems:
            for p in problems:
                print(f"non-ASCII bundle name: {p}", file=sys.stderr)
            fail("bundle names must be ASCII (SideStore cannot register the extension App IDs); "
                 "put localized names in <lang>.lproj/InfoPlist.strings")
    min_os = str(info.get("MinimumOSVersion", ""))
    print(f"version={meta['version']}")
    print(f"build={meta['build']}")
    print(f"bundle_id={meta['bundle_id']}")
    print(f"min_os={min_os}")
    print(f"size={os.path.getsize(args.ipa)}")
    print(f"sha256={sha256_of(args.ipa)}")


def cmd_notes(args):
    with open(args.message_file, encoding="utf-8") as f:
        lines = f.read().splitlines()
    # A signed tag carries its signature at the end of the message.
    for i, line in enumerate(lines):
        if line.startswith("-----BEGIN ") and "SIGNATURE-----" in line:
            lines = lines[:i]
            break
    body = lines[1:]
    release = "\n".join(body).strip()
    sidestore = release
    for i, line in enumerate(body):
        if line.strip() == "---":
            sidestore = "\n".join(body[:i]).strip()
            break
    if not sidestore:
        fail("the tag message has no notes below its first line; tag with "
             "`git tag -a vX.Y -F notes.md` (first line = title, then a blank line and the notes)")
    with open(args.sidestore_out, "w", encoding="utf-8") as f:
        f.write(sidestore + "\n")
    with open(args.release_out, "w", encoding="utf-8") as f:
        f.write(release + "\n")


def entitlements(ipa_path):
    """Union of the entitlement keys signed into every executable of the IPA."""
    found = set()
    with zipfile.ZipFile(ipa_path) as z:
        names = set(z.namelist())
        bundles = [n[: -len("Info.plist")] for n in names if BUNDLE_PLIST.match(n)]
        for b in sorted(bundles):
            info = plistlib.loads(z.read(b + "Info.plist"))
            exe = b + info.get("CFBundleExecutable", "")
            if exe not in names:
                continue
            data = z.read(exe)
            start = 0
            while (i := data.find(b"\xfa\xde\x71\x71", start)) >= 0:
                start = i + 4
                length = int.from_bytes(data[i + 4:i + 8], "big")
                blob = data[i + 8:i + length]
                if blob.lstrip().startswith(b"<?xml"):
                    try:
                        found.update(plistlib.loads(blob).keys())
                    except Exception:
                        pass
    # AltStore says these two never need listing.
    return sorted(found - {"application-identifier", "com.apple.developer.team-identifier"})


def cmd_update_source(args):
    with open(args.notes_file, encoding="utf-8") as f:
        notes = f.read().strip()
    info = app_info_from_ipa(args.ipa)
    privacy = {k: v for k, v in sorted(info.items()) if k.endswith("UsageDescription")}

    if os.path.exists(args.source):
        with open(args.source, encoding="utf-8") as f:
            source = json.load(f)
    else:
        source = {
            "name": args.app_name,
            "identifier": f"{args.bundle_id}.source",
            "iconURL": args.icon_url,
            "apps": [],
            "news": [],
        }

    apps = source.setdefault("apps", [])
    matches = [a for a in apps if a.get("bundleIdentifier") == args.bundle_id]
    if len(matches) > 1:
        fail(f"source lists {len(matches)} apps with bundle id {args.bundle_id}")
    if matches:
        app = matches[0]
    else:
        if args.template and os.path.exists(args.template):
            with open(args.template, encoding="utf-8") as f:
                app = json.load(f)
        else:
            app = {"name": args.app_name, "localizedDescription": args.app_name, "iconURL": args.icon_url}
        app["bundleIdentifier"] = args.bundle_id
        apps.append(app)
        featured = source.setdefault("featuredApps", [])
        if args.bundle_id not in featured:
            featured.append(args.bundle_id)

    versions = list(app.get("versions", []))
    index = next((i for i, v in enumerate(versions) if v.get("version") == args.version), None)
    new_key = version_key(args.version)
    for v in versions:
        if v.get("version") == args.version:
            continue
        other = version_key(str(v.get("version", "")))
        newer = bool(new_key and other and other > new_key)
        if newer and index is None:
            fail(f"source already has newer version {v['version']}; refusing to add {args.version} on top")
        if not (str(v.get("buildVersion", "")).isdigit() and args.build.isdigit()):
            continue
        other_build, build = int(v["buildVersion"]), int(args.build)
        if newer and other_build <= build:
            fail(f"build {args.build} of {args.version} is not below build {other_build} of the newer {v['version']}")
        if not newer and other_build >= build:
            fail(f"build {args.build} is not above build {other_build} of {v['version']}; "
                 "SideStore would not offer it as an update")

    prev = versions[index] if index is not None else None
    same_build = prev is not None and prev.get("buildVersion") == args.build \
        and prev.get("size") == args.size
    entry = {
        "version": args.version,
        "buildVersion": args.build,
        # Re-running for the same build keeps its original date, so nothing changes.
        "date": prev["date"] if same_build and prev.get("date") else args.now,
        "localizedDescription": notes,
        "downloadURL": args.download_url,
        "size": args.size,
        "sha256": args.sha256,
        "minOSVersion": args.min_os,
    }
    if index is not None:
        versions[index] = entry
    else:
        versions.insert(0, entry)
    dropped = versions[args.keep:] if args.keep > 0 else []
    if args.keep > 0:
        versions = versions[:args.keep]

    app["versions"] = versions
    permissions = app.setdefault("appPermissions", {})
    permissions["entitlements"] = entitlements(args.ipa)
    permissions["privacy"] = privacy
    # Legacy single-version fields, read by older SideStore / AltStore builds.
    newest = versions[0]
    app["version"] = newest["version"]
    app["versionDate"] = newest["date"]
    app["versionDescription"] = newest["localizedDescription"]
    app["downloadURL"] = newest["downloadURL"]
    app["size"] = newest["size"]

    os.makedirs(os.path.dirname(os.path.abspath(args.source)), exist_ok=True)
    with open(args.source, "w", encoding="utf-8") as f:
        f.write(json.dumps(source, ensure_ascii=False, indent=2) + "\n")
    with open(args.keep_out, "w", encoding="utf-8") as f:
        f.write("".join(f"{v['version']}\n" for v in versions))
    print(f"versions in source: {', '.join(v['version'] for v in versions)}"
          + (f"; dropping {', '.join(v['version'] for v in dropped)}" if dropped else ""))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("inspect")
    p.add_argument("--ipa", required=True)
    p.add_argument("--archive", default="")
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--tag", default="")
    p.add_argument("--require-tag-match", action="store_true")
    p.add_argument("--check-ascii", action="store_true")
    p.set_defaults(func=cmd_inspect)

    p = sub.add_parser("notes")
    p.add_argument("--message-file", required=True)
    p.add_argument("--sidestore-out", required=True)
    p.add_argument("--release-out", required=True)
    p.set_defaults(func=cmd_notes)

    p = sub.add_parser("update-source")
    for name in ("source", "bundle-id", "app-name", "version", "build", "min-os", "sha256",
                 "download-url", "notes-file", "ipa", "icon-url", "now", "keep-out"):
        p.add_argument(f"--{name}", required=True)
    p.add_argument("--size", type=int, required=True)
    p.add_argument("--keep", type=int, default=0)
    p.add_argument("--template", default="")
    p.set_defaults(func=cmd_update_source)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
