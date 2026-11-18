#!/usr/bin/env python3
"""publish-resource: put one document on the website in a single step.

    ./publish-resource.py whitepapers/ciso-strategic-executive.md            # upload the PDF + write the card
    ./publish-resource.py whitepapers/ciso-strategic-executive.md --build    # rebuild the PDF first (pdf-creator.py)
    ./publish-resource.py whitepapers/ciso-strategic-executive.md --no-upload  # write the card only

What it does:
  1. Reads the `resource:` block in the Markdown front matter (see below). A missing `id` is generated
     (a UUID) and written back into the file once, then never changes.
  2. Uploads the PDF to the PRIVATE R2 bucket as <id>.pdf. Visitors never see that name: the site hands out a
     short-lived signed link, and the file they save is named by `download-name` (default cybertechna_<slug>.pdf).
  3. Writes the card record into the website repo (astro/src/content/resources/<slug>.json). The resources page,
     the homepage carousel and the deploy check all read that one file.

Front matter (pandoc ignores the block):

    resource:
      id: 3f9c...                 # generated for you
      slug: ciso-strategic-executive   # public deep link: /resources?open=<slug>. Default: the Markdown file name
      kind: Whitepaper            # Whitepaper | Checklist | Guide
      title: "Full title shown on the card"
      card-title: "Short name recorded with the lead"
      summary: "One or two sentences for the card."
      cta: "Get the whitepaper"   # button text in the homepage carousel
      order: 10                   # optional, lower shows first
      download-name: cybertechna_ciso-strategic-executive.pdf   # optional
      live-href: /resources/some-page   # optional: a free web version, adds a "Live (FREE)" button

Credentials: an env file outside the repos (default ~/.config/cloudflare/cybertechna-r2.env, override with
CYBERTECHNA_R2_ENV) defining R2_ACCOUNT_ID, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (the bucket-scoped R2 token's
S3 credentials). Needs the AWS CLI and pandoc.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUCKET = "cybertechna-resources"
DEFAULT_SITE = HERE.parent / "cybertechna.com" / "astro"
DEFAULT_ENV = Path(os.environ.get("CYBERTECHNA_R2_ENV", Path.home() / ".config/cloudflare/cybertechna-r2.env"))
KINDS = ("Whitepaper", "Checklist", "Guide")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,80}$")
DOWNLOAD_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,119}\.pdf$")


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def read_meta(md: Path) -> dict:
    """The document's metadata as JSON, parsed by pandoc itself so every YAML form works."""
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as t:
        t.write("$meta-json$")
        template = t.name
    try:
        out = subprocess.run(
            ["pandoc", str(md), "-f", "markdown", "-t", "plain", f"--template={template}"],
            capture_output=True, text=True,
        )
    finally:
        os.unlink(template)
    if out.returncode != 0:
        die(f"pandoc could not read {md}: {out.stderr.strip()}")
    return json.loads(out.stdout)


def ensure_id(md: Path, meta: dict) -> str:
    """Return the resource id, writing a new UUID into the front matter if there isn't one yet."""
    res = meta.get("resource")
    existing = res.get("id") if isinstance(res, dict) else None
    if existing:
        if not UUID_RE.match(str(existing)):
            die(f"resource.id '{existing}' is not a lowercase UUID")
        return str(existing)
    new_id = str(uuid.uuid4())
    lines = md.read_text(encoding="utf-8").split("\n")
    end = next((i for i, ln in enumerate(lines[1:], 1) if ln.strip() in ("---", "...")), None)
    start = next((i for i, ln in enumerate(lines[: end or 0]) if re.match(r"^resource:\s*$", ln)), None)
    if start is None:
        die("no `resource:` block in the front matter. Add one (see ./publish-resource.py --help).")
    # A blank `id:` line (left as a placeholder) is filled in rather than duplicated.
    block_end = next((i for i in range(start + 1, len(lines)) if lines[i].strip() and not lines[i].startswith((" ", "\t"))), len(lines))
    blank = next((i for i in range(start + 1, block_end) if re.match(r"^\s+id:\s*$", lines[i])), None)
    if blank is not None:
        lines[blank] = f"  id: {new_id}"
    else:
        lines.insert(start + 1, f"  id: {new_id}")
    md.write_text("\n".join(lines), encoding="utf-8")
    print(f"generated id {new_id} and wrote it into {md.name}")
    return new_id


def load_env(path: Path) -> dict:
    if not path.is_file():
        die(f"missing credentials file: {path}")
    creds: dict = {}
    for line in path.read_text().splitlines():
        m = re.match(r"^\s*(?:export\s+)?([A-Z0-9_]+)=(.*)$", line)
        if m:
            creds[m.group(1)] = m.group(2).strip().strip("'\"")
    for k in ("R2_ACCOUNT_ID", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"):
        if not creds.get(k):
            die(f"{k} missing in {path}")
    return creds


def build_card(md: Path, meta: dict, rid: str) -> tuple[str, dict]:
    res = meta.get("resource")
    if not isinstance(res, dict):
        die("no `resource:` block in the front matter")

    def need(key: str) -> str:
        val = res.get(key)
        if not isinstance(val, str) or not val.strip():
            die(f"resource.{key} is required")
        return val.strip()

    slug = str(res.get("slug") or md.stem)
    if not SLUG_RE.match(slug):
        die(f"slug '{slug}' must be lowercase letters, digits and hyphens")
    kind = need("kind")
    if kind not in KINDS:
        die(f"resource.kind must be one of {', '.join(KINDS)}")
    download_name = str(res.get("download-name") or f"cybertechna_{slug}.pdf")
    if not DOWNLOAD_NAME_RE.match(download_name):
        die(f"download-name '{download_name}' must be letters, digits, . _ - and end in .pdf")

    card: dict = {
        "resourceId": rid,
        "kind": kind,
        "title": need("title"),
        "cardTitle": need("card-title"),
        "summary": need("summary"),
        "cta": need("cta"),
        "order": int(res.get("order") or 100),
        "downloadName": download_name,
    }
    if res.get("live-href"):
        card["liveHref"] = str(res["live-href"])
    return slug, card


def pdf_path(md: Path, meta: dict) -> Path:
    spec = meta.get("output-file") or meta.get("output")
    if not spec:
        return HERE / "PDFs" / f"{md.stem}.pdf"
    p = Path(str(spec)).expanduser()
    return (p if p.is_absolute() else md.parent / p).resolve()


def main() -> None:
    ap = argparse.ArgumentParser(description="Upload a document's PDF to private R2 and write its website card.")
    ap.add_argument("markdown", type=Path)
    ap.add_argument("--build", action="store_true", help="rebuild the PDF with pdf-creator.py first")
    ap.add_argument("--no-upload", action="store_true", help="write the card only; skip the upload")
    ap.add_argument("--site", type=Path, default=DEFAULT_SITE, help=f"website astro folder (default {DEFAULT_SITE})")
    ap.add_argument("--env-file", type=Path, default=DEFAULT_ENV)
    args = ap.parse_args()

    md = args.markdown.resolve()
    if not md.is_file():
        die(f"{args.markdown} not found")
    cards_dir = args.site.resolve() / "src" / "content" / "resources"
    if not cards_dir.parent.is_dir():
        die(f"{args.site} does not look like the site's astro folder (no src/content). Use --site.")

    meta = read_meta(md)
    rid = ensure_id(md, meta)
    meta = read_meta(md)
    slug, card = build_card(md, meta, rid)

    if not args.no_upload:
        if args.build:
            print(f"building {md.name} ...")
            if subprocess.run([sys.executable, str(HERE / "pdf-creator.py"), str(md)]).returncode != 0:
                die("PDF build failed")
        pdf = pdf_path(md, meta)
        if not pdf.is_file():
            die(f"{pdf} not found. Build it first, or pass --build.")
        if pdf.read_bytes()[:5] != b"%PDF-":
            die(f"{pdf} is not a PDF")
        if md.stat().st_mtime > pdf.stat().st_mtime + 1:
            print(f"warning: {md.name} is newer than {pdf.name}; re-run with --build to publish the latest text")

        creds = load_env(args.env_file)
        endpoint = f"https://{creds['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com"
        env = {**os.environ, "AWS_ACCESS_KEY_ID": creds["AWS_ACCESS_KEY_ID"], "AWS_SECRET_ACCESS_KEY": creds["AWS_SECRET_ACCESS_KEY"]}
        key = f"{rid}.pdf"
        base = ["--endpoint-url", endpoint, "--region", "auto"]
        exists = subprocess.run(
            ["aws", "s3api", "head-object", "--bucket", BUCKET, "--key", key, *base],
            env=env, capture_output=True,
        ).returncode == 0
        # The download name travels with the object, so the site never trusts a name from the browser.
        up = subprocess.run(
            ["aws", "s3", "cp", str(pdf), f"s3://{BUCKET}/{key}", *base,
             "--content-type", "application/pdf", "--metadata", f"download-name={card['downloadName']}", "--no-progress"],
            env=env,
        )
        if up.returncode != 0:
            die("upload failed")
        print(f"{'replaced' if exists else 'uploaded'} {key} in {BUCKET} (private)")

    cards_dir.mkdir(parents=True, exist_ok=True)
    out = cards_dir / f"{slug}.json"
    out.write_text(json.dumps(card, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote card {out}")
    print(f"deep link: /resources?open={slug}   visitors save the file as {card['downloadName']}")
    print("next: commit both repos (this one for the new id, the site for the card), then deploy the site.")


if __name__ == "__main__":
    main()
