# Cybertechna Resources: Production Templates and PDFs

Branded PDFs from Markdown (Pandoc + LuaLaTeX). Blue/red on navy, Inter type, one look across five document types.

```bash
./pdf-creator.py whitepapers/ciso-strategic-executive.md      # type comes from the folder
./pdf-creator.py notes.md -t briefing -o ~/Desktop/notes.pdf  # or say it
./pdf-creator.py guides/                                      # a whole folder
./pdf-creator.py --list-types | --check
```

PDFs go to `PDFs/<name>.pdf` unless `-o`, `-d`, or `output-file:` in the front matter says otherwise.
Needs `pandoc` 3.8+ and TeX Live (`lualatex`). Options: `-m key=value` (override metadata), `--margins narrow`, `--force`, `--tex`, `--open`.

| Type | Folder | Look |
|---|---|---|
| `whitepaper` | `whitepapers/` | Gradient cover, optional contents, long-form body, back page with author box |
| `briefing` | `briefings/` | 2 to 5 pages. Navy title band, stat tiles, "Bottom line" card, optional call to action |
| `decision` | `decisions/` | Compact title block, dark "Decision" card, options and scoring tables |
| `guide` | `guides/` | Same layout as decision, numbered sections (`numbersections: true`), code blocks |
| `checklist` | `checklists/` | Title bar, tick boxes, write-in fields, sign-off block |
| `slides` | `slides/` | 16:9 pages: gradient title slide, optional agenda, section dividers, columns, closing slide |

`.pandoc/examples/` has one document per type showing every element. Start from those.

## Markdown extras

- Callouts: `::: note`, `::: {.warning title="Watch for"}`, `::: decision` (dark card, once per page). Block quotes become pull quotes.
- Checklists: `- [ ] item`, `- [x] item` (ticked), nested items work. Front matter `fields: [Vendor, Date]` and `signoff: [Owner, Reviewer]`.
- Chips: `[Draft]{.chip}` `[Approved]{.chip-brand}` `[Internal]{.chip-dark}` `[Urgent]{.chip-red}`.
- Open items `[CONFIRM ...]`, `[TBD ...]`, `[VERIFY ...]` print bold red. `::: pagebreak` forces a new page.
- Briefing/decision front matter: `lead`, `abstract`, `stats: [{value, label}]`, `cta`. Decision also `decision`, `owner`, `due-date`.
- Mermaid blocks are drawn with `mmdc` (or use `<file>-mermaid-1.png` beside the Markdown).
- `toc: true` adds contents. Headings work with `#` or `##` as the top level.

## Tables

Pipe tables are drawn as a framed grid: navy header, zebra rows, columns sized to their content. A caption (`: Caption` under the table) prints above it. A column left empty becomes a write-in column.

- **Landscape, automatic:** 6 or more columns (`wide-columns: 5` changes the limit). The heading and the paragraph before it go with the table.
- **Landscape, per table:** a line `<!-- landscape -->` above the table. `<!-- portrait -->` keeps a wide one upright.
- **Landscape, any section:** wrap it in `::: landscape` ... `:::`.
- **Whole document:** `landscape: all` or `landscape: none`.
- Style: `table-header: navy | blue | light`, `table-size: small | footnotesize | normal`, `table-style: plain` for the simple booktabs look.

## Layout

- `pdf-creator.py`: the command
- `.pandoc/templates/`: `cybertechna-common.latex` (palette, fonts, callouts, tables), one template per layout
- `.pandoc/filters/`: `cybertechna.lua` (callouts, checklists, stats), `cybertechna-slides.lua` (slide breaks, columns, notes), `cybertechna-tables.lua` (grid and landscape)
- `.pandoc/defaults/`: pandoc options per type. `.pandoc/assets/`: logos and author photo

The old command still works for whitepapers:
`pandoc doc.md --template=../.pandoc/templates/whitepaper.latex --pdf-engine=lualatex -o out.pdf`
(without the filters you lose callouts and grid tables, so use `pdf-creator.py`).

## Slides

`./pdf-creator.py slides/deck.md` makes a 16:9 PDF (13.33 x 7.5 in) you can present from or send as a file.

- **Slide breaks:** when a deck uses both `#` and `##`, each `#` is a full-bleed section divider and each `##` is a content slide. With one level only, that level is a content slide. A line of `---` starts a continuation slide with no title.
- **Front matter:** `title`, `subtitle`, `author`, `date`, `audience`, `series`, `classification`; `toc: true` adds an agenda slide; `closing:` (and `closing-title:`) adds a closing slide with the contact line.
- **Columns:** a fenced block with `columns` holds `column` blocks. Leave a blank line before and after every fence line, and give widths in braces:

  ```
  ::::: columns

  :::: {.column width="40%"}

  Left side.

  ::::

  :::: {.column}

  Right side (a list, callout, image or table).

  ::::

  :::::
  ```
- **Speaker notes:** `::: notes ... :::` is left out of the PDF.
- **Tables** are drawn in the same grid style and never switch to landscape on a slide.
