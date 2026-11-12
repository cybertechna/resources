#!/usr/bin/env python3
"""Build Cybertechna-branded PDFs from Markdown with Pandoc + LuaLaTeX.

    ./pdf-creator.py FILE_OR_DIR... [-t TYPE] [-o OUT | -d OUTDIR] [options] [-- pandoc args]

Examples:
    ./pdf-creator.py whitepapers/cyber-risk-management-governance.md      type inferred from the folder
    ./pdf-creator.py notes.md -t briefing -o ~/Desktop/notes.pdf          explicit type and output file
    ./pdf-creator.py guides/                                              every .md in a folder, in parallel
    ./pdf-creator.py checklist.md -t checklist -m status=Final --open
    ./pdf-creator.py --list-types | --check

Types and the folder that implies them: whitepaper (whitepapers/), briefing (briefings/), decision (decisions/),
guide (guides/), checklist (checklists/), slides (slides/). PDFs go to PDFs/<name>.pdf unless -o, -d or the document's own
`output-file:` (front matter, relative to the Markdown file) says otherwise.
Files whose PDF is newer than the Markdown, templates, filters and this script are skipped; use --force to rebuild.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PANDOC_DIR = ROOT / ".pandoc"
ASSETS = PANDOC_DIR / "assets"
MIN_PANDOC = (3, 8)  # `syntax-highlighting:` in the defaults files needs 3.8
FONTS = ("Inter-Regular.otf", "CascadiaCode-Regular.otf")
SKIP_NAMES = {"README.md", "CLAUDE.md", "CHANGELOG.md"}


@dataclass(frozen=True)
class DocType:
    summary: str
    folders: tuple[str, ...]


TYPES = {
    "whitepaper": DocType("White paper: gradient cover, optional contents, long-form body, branded back page", ("whitepapers",)),
    "briefing": DocType("Briefing: 2 to 5 pages, navy title band, stat tiles, bottom-line card", ("briefings",)),
    "decision": DocType("Decision record: compact title block, decision card, options tables", ("decisions",)),
    "guide": DocType("Guide / how-to: compact title block, numbered sections, code blocks", ("guides",)),
    "slides": DocType("Slides: 16:9 pages, gradient title slide, section dividers, columns, closing slide", ("slides",)),
    "checklist": DocType("Checklist: title bar, tick boxes, write-in fields, sign-off block", ("checklists",)),
}

# ---- Mermaid charts ----------------------------------------------------------------------------------------------
# GitHub draws a ```mermaid block as a chart; pandoc does not. Before the build each block is replaced by a picture:
# the author's own image if one sits next to the Markdown file (<file>-mermaid-<n>.png/.pdf/.jpg, n from 1), else a chart
# drawn by the Mermaid CLI (mmdc, `npm install -g @mermaid-js/mermaid-cli`) and cached in PDFs/.mermaid-cache/.
MERMAID_IMAGE_EXTS = (".pdf", ".png", ".jpg", ".jpeg")
MERMAID_OPEN = re.compile(r"^ {0,3}(`{3,}|~{3,})\s*\{?\.?mermaid\}?\s*$")
ANY_OPEN = re.compile(r"^ {0,3}(`{3,}|~{3,})")


class MermaidError(Exception):
    pass


def find_mermaid_blocks(text: str) -> list[tuple[int, int, str]]:
    """(first line, closing line, source) of each fenced mermaid block; lines are 0-based."""
    lines = text.split("\n")
    blocks: list[tuple[int, int, str]] = []
    i = 0
    while i < len(lines):
        m = ANY_OPEN.match(lines[i])
        if not m:
            i += 1
            continue
        fence = m.group(1)
        is_mermaid = bool(MERMAID_OPEN.match(lines[i]))
        j = i + 1
        while j < len(lines) and not re.match(rf"^ {{0,3}}{re.escape(fence[0])}{{{len(fence)},}}\s*$", lines[j]):
            j += 1
        if is_mermaid:
            blocks.append((i, min(j, len(lines) - 1), "\n".join(lines[i + 1:j])))
        i = j + 1
    return blocks


def find_mmdc() -> str | None:
    env = os.environ.get("CYBERTECHNA_MMDC")
    if env and Path(env).exists():
        return env
    found = shutil.which("mmdc")
    if found:
        return found
    npm = shutil.which("npm")
    if npm:  # mermaid-filter (npm -g) carries its own copy
        root = subprocess.run([npm, "root", "-g"], text=True, capture_output=True).stdout.strip()
        for cand in (Path(root) / "@mermaid-js/mermaid-cli/src/cli.js", Path(root) / "mermaid-filter/node_modules/.bin/mmdc"):
            if cand.exists():
                return str(cand)
    return None


def browser_config(cache: Path) -> Path | None:
    """mmdc needs a Chrome: puppeteer's own if it has one, else the Chrome app on a Mac."""
    if os.environ.get("PUPPETEER_EXECUTABLE_PATH") or (Path.home() / ".cache/puppeteer").exists():
        return None
    chrome = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    if not chrome.exists():
        return None
    cfg = cache / "puppeteer-config.json"
    cfg.write_text(json.dumps({"executablePath": str(chrome)}))
    return cfg


def render_mermaid(chart: str, cache: Path) -> Path:
    out = cache / (hashlib.sha1(chart.encode()).hexdigest()[:16] + ".pdf")
    if out.exists():
        return out
    mmdc = find_mmdc()
    if not mmdc:
        raise MermaidError("mmdc not found")
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        src, tmp_out = Path(tmp) / "chart.mmd", Path(tmp) / "chart.pdf"
        src.write_text(chart)
        cmd = [mmdc, "-i", str(src), "-o", str(tmp_out), "-e", "pdf", "--pdfFit", "-b", "transparent"]
        cfg = browser_config(cache)
        if cfg:
            cmd += ["-p", str(cfg)]
        proc = subprocess.run(cmd, text=True, capture_output=True, timeout=180)
        if proc.returncode or not tmp_out.exists():
            raise MermaidError("the Mermaid tool could not draw the chart:\n" + (proc.stderr or proc.stdout).strip())
        shutil.move(str(tmp_out), out)
    return out


def prepare_mermaid(src: Path, workdir: Path) -> Path:
    """The Markdown file to give pandoc: the original, or a copy in workdir with each chart replaced by a picture."""
    text = src.read_text(encoding="utf-8")
    blocks = find_mermaid_blocks(text)
    if not blocks:
        return src
    lines = text.split("\n")
    for n, (first, last, chart) in reversed(list(enumerate(blocks, 1))):
        own = next((src.with_name(f"{src.stem}-mermaid-{n}{ext}") for ext in MERMAID_IMAGE_EXTS
                    if src.with_name(f"{src.stem}-mermaid-{n}{ext}").exists()), None)
        if own:
            image = own
        else:
            try:
                image = render_mermaid(chart, ROOT / "PDFs" / ".mermaid-cache")
            except MermaidError as e:
                where = f"chart {n} of {len(blocks)}, starting at line {first + 1}"
                if str(e) == "mmdc not found":
                    raise MermaidError(
                        f"There is a Mermaid chart in this file ({where}) and the Mermaid tool (mmdc) is not installed. "
                        f"Install it (npm install -g @mermaid-js/mermaid-cli), or save a picture of the chart next to the "
                        f"Markdown file as '{src.stem}-mermaid-{n}.png' (or .pdf, .jpg) and build again.") from None
                raise MermaidError(f"Mermaid chart in this file ({where}): {e}\n"
                                   f"Check the chart syntax, or save a picture of it next to the Markdown file as "
                                   f"'{src.stem}-mermaid-{n}.png' and build again.") from None
        local = workdir / f"mermaid-{n}{image.suffix}"
        shutil.copy(image, local)
        lines[first:last + 1] = ["", f"![Diagram]({local})", ""]
    out = workdir / src.name
    out.write_text("\n".join(lines), encoding="utf-8")
    return out


# ---- Environment, inputs, front matter -----------------------------------------------------------------------------------
def infer_type(path: Path) -> str | None:
    parts = {p.lower() for p in path.resolve().parts}
    for name, t in TYPES.items():
        if parts & set(t.folders):
            return name
    return None


def pandoc_version() -> tuple[int, ...] | None:
    try:
        out = subprocess.run(["pandoc", "--version"], text=True, capture_output=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    m = re.search(r"pandoc(?:\.exe)? (\d+(?:\.\d+)*)", out)
    return tuple(int(x) for x in m.group(1).split(".")) if m else None


def check_environment(verbose: bool = True) -> bool:
    ok = True

    def report(good: bool, msg: str) -> None:
        nonlocal ok
        ok &= good
        if verbose or not good:
            print(("ok       " if good else "MISSING  ") + msg)

    v = pandoc_version()
    need = ".".join(map(str, MIN_PANDOC))
    report(v is not None and v >= MIN_PANDOC,
           f"pandoc {'.'.join(map(str, v))} (need {need}+)" if v else f"pandoc {need}+ (brew install pandoc)")
    lua = shutil.which("lualatex")
    report(bool(lua), f"lualatex ({lua or 'install MacTeX or TeX Live'})")
    kpse = shutil.which("kpsewhich")
    for font in FONTS:
        found = subprocess.run([kpse, font], text=True, capture_output=True).stdout.strip() if kpse else ""
        report(bool(found), f"font {font}" + ("" if found else " (ships with TeX Live)"))
    for asset in ("cybertechna_logo_banner_tagline.png", "cybertechna_banner_logo.png", "kevin.png"):
        report((ASSETS / asset).exists(), f".pandoc/assets/{asset}")
    mmdc = find_mmdc()
    if verbose:
        print(f"ok       mmdc, draws Mermaid charts ({mmdc})" if mmdc else
              "optional mmdc not found: Markdown with Mermaid charts needs it, or a picture of each chart next to the file")
    return ok


def collect_inputs(args: list[str], recursive: bool) -> list[Path]:
    files: list[Path] = []
    for a in args:
        p = Path(a).expanduser()
        if p.is_dir():
            found = sorted(p.rglob("*.md") if recursive else p.glob("*.md"))
            found = [f for f in found if f.name not in SKIP_NAMES and not f.name.startswith(".")]
            if not found:
                sys.exit(f"pdf-creator: no Markdown files in {p}")
            files += found
        elif p.is_file():
            files.append(p)
        else:
            sys.exit(f"pdf-creator: no such file: {a}")
    return files


def newest_dependency(doc_type: str) -> float:
    deps = [PANDOC_DIR / "defaults" / f"{doc_type}.yaml", Path(__file__).resolve()]
    for sub in ("templates", "filters"):
        deps += [p for p in (PANDOC_DIR / sub).iterdir() if p.is_file() and not p.name.startswith(".")]
    return max(p.stat().st_mtime for p in deps)


def read_front_matter(src: Path) -> dict[str, str]:
    """The simple `key: value` lines of the YAML front matter (not a YAML parser; enough for `output-file:`)."""
    meta: dict[str, str] = {}
    lines = src.read_text(encoding="utf-8").splitlines()
    if lines and lines[0].strip() == "---":
        for ln in lines[1:]:
            if ln.strip() in ("---", "..."):
                break
            m = re.match(r"^([A-Za-z][\w-]*):[ \t]*(.*)$", ln)
            if not m:
                continue
            key, val = m.group(1), m.group(2).strip()
            if val[:1] in ("'", '"'):
                end = val.find(val[0], 1)
                val = val[1:end] if end > 0 else val[1:]
            else:
                val = re.split(r"\s+#", val)[0].strip()
            meta[key] = val
    return meta


def output_path(src: Path, args: argparse.Namespace, fm: dict[str, str]) -> Path:
    """-o, then -d, then the document's `output-file:` (relative to the Markdown file), then PDFs/<name>.pdf."""
    if args.output:
        return args.output.expanduser().resolve()
    if args.outdir:
        return (args.outdir.expanduser() / f"{src.stem}.pdf").resolve()
    spec = fm.get("output-file") or fm.get("output")
    if spec:
        path = Path(spec).expanduser()
        path = path if path.is_absolute() else src.parent / path
        if path.suffix.lower() != ".pdf":
            path = path / f"{src.stem}.pdf"
        return path.resolve()
    return ROOT / "PDFs" / f"{src.stem}.pdf"


@dataclass
class Job:
    src: Path
    doc_type: str
    out: Path


def run_job(job: Job, set_meta: list[str], extra: list[str], tex: bool, force: bool) -> tuple[Job, str, float, str]:
    """Returns (job, status, seconds, log); status is built | skipped | failed."""
    target = job.out.with_suffix(".tex") if tex else job.out
    if not force and target.exists():
        if target.stat().st_mtime > max(job.src.stat().st_mtime, newest_dependency(job.doc_type)):
            return job, "skipped", 0.0, ""
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        try:
            md = prepare_mermaid(job.src, Path(tmp))
        except MermaidError as e:
            return job, "failed", 0.0, str(e)
        cmd = ["pandoc", str(md), "--defaults", f"defaults/{job.doc_type}.yaml",
               "--resource-path", os.pathsep.join([str(job.src.parent), str(ASSETS)]), "-o", str(target)]
        if tex:
            cmd += ["--standalone", "--to", "latex"]
        for var, name in (("cyber-logo", "cybertechna_logo_banner_tagline.png"),
                          ("cyber-logo-small", "cybertechna_banner_logo.png"),
                          ("cyber-photo", "kevin.png")):
            if (ASSETS / name).exists():
                cmd += ["--variable", f"{var}={ASSETS / name}"]
        for kv in set_meta:
            cmd += ["--metadata", kv]
        cmd += extra
        start = time.monotonic()
        proc = subprocess.run(cmd, cwd=PANDOC_DIR, text=True, capture_output=True)
        secs = time.monotonic() - start
        if proc.returncode:
            return job, "failed", secs, (proc.stderr or proc.stdout).strip()
        return job, "built", secs, proc.stderr.strip()


def parse_args(argv: list[str]) -> tuple[argparse.Namespace, list[str]]:
    p = argparse.ArgumentParser(
        prog="pdf-creator", description="Build Cybertechna-branded PDFs from Markdown.",
        epilog="Anything after -- (or any unrecognized option) is passed to pandoc.")
    p.add_argument("inputs", nargs="*", metavar="FILE_OR_DIR", help="Markdown files, or folders of them")
    p.add_argument("-t", "--type", choices=sorted(TYPES), help="document type (default: inferred from the folder)")
    p.add_argument("-o", "--output", type=Path, help="output file (single input only)")
    p.add_argument("-d", "--outdir", type=Path, help="output folder (default: PDFs/)")
    p.add_argument("-r", "--recursive", action="store_true", help="include subfolders when an input is a folder")
    p.add_argument("-j", "--jobs", type=int, default=min(4, os.cpu_count() or 1), help="parallel builds (default %(default)s)")
    p.add_argument("-f", "--force", action="store_true", help="rebuild even if the PDF is up to date")
    p.add_argument("-m", "--set", action="append", default=[], metavar="KEY=VALUE",
                   help="override a metadata field, e.g. -m status=Final -m landscape=all (repeatable)")
    p.add_argument("--margins", choices=("normal", "narrow"), help="left and right margins: normal = 1 in, narrow = 0.5 in")
    p.add_argument("--tex", action="store_true", help="write the .tex source instead of a PDF (for debugging)")
    p.add_argument("--open", action="store_true", help="open the result when done (macOS)")
    p.add_argument("-q", "--quiet", action="store_true", help="print only failures")
    p.add_argument("--list-types", action="store_true", help="show document types and how they are inferred")
    p.add_argument("--check", action="store_true", help="check that pandoc, lualatex, the fonts and the logos are present")
    return p.parse_known_args(argv)


def main(argv: list[str]) -> int:
    passthrough: list[str] = []
    if "--" in argv:
        i = argv.index("--")
        argv, passthrough = argv[:i], argv[i + 1:]
    args, unknown = parse_args(argv)
    passthrough = unknown + passthrough

    if args.list_types:
        for name, t in TYPES.items():
            print(f"{name:11} {t.summary}\n{'':11} inferred from: {', '.join(f'*/{f}/*' for f in t.folders)}")
        return 0
    if args.check:
        return 0 if check_environment() else 1
    if not args.inputs:
        parse_args(["--help"])
    if not check_environment(verbose=False):
        return 1

    margin_x = {"normal": "1in", "narrow": "0.5in"}.get(args.margins)
    if margin_x:
        args.set = [f"margin-x={margin_x}"] + args.set
    args.force = args.force or bool(args.set)  # a changed option changes the output, which the timestamp check cannot see

    srcs = collect_inputs(args.inputs, args.recursive)
    if args.output and len(srcs) != 1:
        sys.exit("pdf-creator: -o takes a single input; use -d for several")

    jobs: list[Job] = []
    for src in srcs:
        doc_type = args.type or infer_type(src)
        if not doc_type:
            if len(srcs) > 1 and any(Path(a).is_dir() for a in args.inputs):
                print(f"skip     {src} (cannot infer type; pass -t)", file=sys.stderr)
                continue
            sys.exit(f"pdf-creator: can't infer the type of {src}; pass -t {{{'|'.join(TYPES)}}}")
        fm = read_front_matter(src)
        fm.update({k: v for k, v in (kv.split("=", 1) for kv in args.set if "=" in kv)})
        jobs.append(Job(src.resolve(), doc_type, output_path(src, args, fm)))

    results = []
    with ThreadPoolExecutor(max_workers=max(1, min(args.jobs, len(jobs) or 1))) as pool:
        futures = [pool.submit(run_job, j, args.set, passthrough, args.tex, args.force) for j in jobs]
        for fut in as_completed(futures):
            job, status, secs, log = fut.result()
            results.append((job, status))
            target = job.out.with_suffix(".tex") if args.tex else job.out
            if status == "failed":
                print(f"FAILED   {job.src}\n{log}\n", file=sys.stderr)
            elif not args.quiet:
                print(f"{status:8} {target}" + (f"  ({secs:.1f}s)" if status == "built" else ""))
                if log and status == "built":
                    print(log, file=sys.stderr)

    failed = [j for j, s in results if s == "failed"]
    if len(jobs) > 1 and not args.quiet:
        built = sum(s == "built" for _, s in results)
        print(f"{built} built, {sum(s == 'skipped' for _, s in results)} up to date, {len(failed)} failed")
    if args.open and not failed and shutil.which("open"):
        subprocess.run(["open", *[str(j.out.with_suffix('.tex') if args.tex else j.out) for j, _ in results]])
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
