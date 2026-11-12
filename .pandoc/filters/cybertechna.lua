-- Cybertechna Pandoc filter, shared by every document type.
--  1. Titles: a leading "# Heading" that repeats the front-matter title is dropped; with no front matter it becomes the
--     title (and a leading italic paragraph becomes the lead). Headings are then shifted so the top level used in the
--     document is always a section (so a document written with "##" sections works the same as one written with "#").
--  2. Fenced divs  ::: note | warning | decision | pagebreak  become callout cards and page breaks.
--  3. `[Draft]{.chip}` (also .chip-brand, .chip-dark, .chip-red) renders a pill tag.
--  4. Task lists ("- [ ] item", "- [x] item") become checklist rows with drawn boxes.
--  5. `stats:` in the front matter becomes a row of stat tiles (stats-tex, used by briefing and decision).
--  6. Inline code and class-less code blocks wrap instead of running off the page.
--  7. Status emoji are drawn (Inter has none): green/yellow/red dots, check, cross, warning triangle.
--  8. [CONFIRM ...], [TBD ...], [VERIFY ...] print in bold red so open items are never missed.

local function latex_escape(s)
  local map = {
    ['\\'] = '\\textbackslash{}', ['{'] = '\\{', ['}'] = '\\}', ['$'] = '\\$',
    ['&'] = '\\&', ['#'] = '\\#', ['^'] = '\\^{}', ['_'] = '\\_', ['%'] = '\\%',
    ['~'] = '\\~{}',
  }
  return (s:gsub('[\\{}$&#^_%%~]', map))
end

local function is_lead_note(block)
  if block.t ~= 'Para' then return false end
  local first, last = block.content[1], block.content[#block.content]
  return first ~= nil and first.t == 'Emph' and last.t == 'Emph'
end

local MARGINS = { normal = '1in', narrow = '0.5in' }

-- `margins:` in the front matter: normal (1 in), narrow (0.5 in) or a length such as 0.75in (left and right).
local function margins_from_meta(meta)
  if not meta.margins or meta['margin-x'] or meta.margin then return end
  local v = pandoc.utils.stringify(meta.margins):lower()
  local dim = MARGINS[v] or v
  local num, unit = dim:match('^([%d.]+)%s*(%a+)$')
  if num and tonumber(num) and (unit == 'in' or unit == 'cm' or unit == 'mm' or unit == 'pt') then
    meta['margin-x'] = pandoc.MetaString(num .. unit)
  else
    io.stderr:write("cybertechna: margins: expected normal, narrow or a length like 0.75in, got '" .. v .. "'; using the template's margins\n")
  end
end

local function shift_headings(blocks)
  local min
  blocks:walk({ Header = function(h) if not min or h.level < min then min = h.level end end })
  if not min or min <= 1 then return blocks end
  return blocks:walk({ Header = function(h) h.level = h.level - (min - 1); return h end })
end

local function stats_row(meta)
  if not meta.stats or pandoc.utils.type(meta.stats) ~= 'List' then return end
  local n = #meta.stats
  if n == 0 then return end
  local parts = {}
  for _, s in ipairs(meta.stats) do
    local value = latex_escape(pandoc.utils.stringify(s.value or ''))
    local label = latex_escape(pandoc.utils.stringify(s.label or ''))
    parts[#parts + 1] = string.format('\\begin{minipage}[t]{\\dimexpr(\\linewidth-10pt*%d)/%d\\relax}\\cybstat{%s}{%s}\\end{minipage}',
      n - 1, n, value, label)
  end
  meta['stats-tex'] = pandoc.MetaBlocks({ pandoc.RawBlock('latex', '\\noindent ' .. table.concat(parts, '\\hspace{10pt}') .. '\\par') })
end

-- `fields: [Organization, Assessor, Date]` becomes a row of labelled blank lines to write on (checklist).
local function fields_row(meta)
  if not meta.fields or pandoc.utils.type(meta.fields) ~= 'List' or #meta.fields == 0 then return end
  local n = #meta.fields
  local parts = {}
  for _, f in ipairs(meta.fields) do
    parts[#parts + 1] = string.format(
      '\\begin{minipage}[t]{\\dimexpr(\\linewidth-14pt*%d)/%d\\relax}{\\color{cybermuted}\\cybcapsfont\\fontsize{6.5}{8}\\selectfont\\MakeUppercase{%s}\\par}\\vspace{17pt}{\\color{cybgrid}\\hrule height 0.6pt}\\end{minipage}',
      n - 1, n, latex_escape(pandoc.utils.stringify(f)))
  end
  meta['fields-tex'] = pandoc.MetaBlocks({ pandoc.RawBlock('latex', '\\noindent ' .. table.concat(parts, '\\hspace{14pt}') .. '\\par') })
end

-- `signoff: [Completed by, Reviewed by]` (or `signoff: true`) becomes a sign-off table: Role, Name, Signature, Date.
local function signoff_block(meta)
  local roles = {}
  if meta.signoff and pandoc.utils.type(meta.signoff) == 'List' then
    for _, r in ipairs(meta.signoff) do roles[#roles + 1] = pandoc.utils.stringify(r) end
  elseif meta.signoff == true then
    roles = { 'Completed by', 'Reviewed by' }
  else
    return
  end
  if #roles == 0 then return end
  local function col(share) return string.format('p{%.3f\\dimexpr\\linewidth-8\\tabcolsep-5\\arrayrulewidth\\relax}', share) end
  local rows = {
    '{\\small\\arrayrulecolor{cybgrid}\\setlength{\\arrayrulewidth}{0.5pt}',
    '\\begin{tabular}{|' .. col(0.22) .. '|' .. col(0.27) .. '|' .. col(0.33) .. '|' .. col(0.18) .. '|}',
    '\\hline',
    '\\rowcolor{darkblue}{\\bfseries\\color{white} Role} & {\\bfseries\\color{white} Name} & {\\bfseries\\color{white} Signature} & {\\bfseries\\color{white} Date} \\\\ \\hline',
  }
  for k, r in ipairs(roles) do
    rows[#rows + 1] = (k % 2 == 0 and '\\rowcolor{lightgray}' or '') .. '\\rule{0pt}{30pt}\\raggedright ' .. latex_escape(r) .. ' & & & \\\\ \\hline'
  end
  rows[#rows + 1] = '\\end{tabular}}'
  meta['signoff-tex'] = pandoc.MetaBlocks({ pandoc.RawBlock('latex', table.concat(rows, '\n')) })
end

local function front_page(doc)
  local meta, blocks = doc.meta, doc.blocks

  local first = blocks[1]
  local lift = first and first.t == 'Header' and first.level == 1
    and (not meta.title or pandoc.utils.stringify(first.content) == pandoc.utils.stringify(meta.title))
  if lift then
    if not meta.title then
      -- "# Guide — Renewing certificates": the words before the first spaced dash are the kind of document.
      local at
      for i, el in ipairs(first.content) do
        if el.t == 'Str' and (el.text == '\u{2014}' or el.text == '\u{2013}') and i > 2 and i < #first.content - 1
          and first.content[i - 1].t == 'Space' and first.content[i + 1].t == 'Space' then at = i; break end
      end
      if at then
        local kind, rest = {}, {}
        for i = 1, at - 2 do kind[#kind + 1] = first.content[i] end
        for i = at + 2, #first.content do rest[#rest + 1] = first.content[i] end
        meta['doc-type'] = pandoc.MetaInlines(kind)
        meta.title = pandoc.MetaInlines(rest)
      else
        meta.title = pandoc.MetaInlines(first.content)
      end
    end
    table.remove(blocks, 1)
    if not meta.lead and blocks[1] and is_lead_note(blocks[1]) then
      local plain = blocks[1]:walk({ Emph = function(e) return e.content end })
      meta.lead = pandoc.MetaInlines(plain.content)
      table.remove(blocks, 1)
    end
  end
  blocks = shift_headings(blocks)

  if not meta.date then
    local found = meta.lead and pandoc.utils.stringify(meta.lead):match('%d%d%d%d%-%d%d%-%d%d')
    meta.date = found or os.date('%Y-%m-%d')
  end

  if not meta.title then
    io.stderr:write('cybertechna: this document has no title (front matter `title:` or a leading "# Heading")\n')
    meta.title = pandoc.MetaString('Untitled')
  end

  -- The running header carries a short title; a long one runs into the label beside it.
  if meta.title and not meta.shorttitle then
    local t = pandoc.utils.stringify(meta.title)
    if utf8.len(t) and utf8.len(t) > 48 then
      local cut = t:sub(1, utf8.offset(t, 46) - 1):gsub('[%s,;:%(%-]*[^%s]*$', '')
      if #cut < 12 then cut = t:sub(1, utf8.offset(t, 46) - 1) end
      meta.shorttitle = pandoc.MetaString(cut .. '\u{2026}')
    end
  end

  margins_from_meta(meta)
  stats_row(meta)
  fields_row(meta)
  signoff_block(meta)
  return pandoc.Pandoc(blocks, meta)
end

local callouts = {
  note = 'cybnote', callout = 'cybnote', info = 'cybnote', tip = 'cybnote',
  warning = 'cybwarning', caution = 'cybwarning', risk = 'cybwarning',
  decision = 'cybdecision', keypoint = 'cybdecision', recommendation = 'cybdecision',
}

local function div(el)
  for _, c in ipairs(el.classes) do
    local env = callouts[c]
    if env then
      local title = el.attributes['title'] or ''
      local out = pandoc.List({ pandoc.RawBlock('latex', '\\begin{' .. env .. '}[{' .. latex_escape(title) .. '}]') })
      out:extend(el.content)
      out:insert(pandoc.RawBlock('latex', '\\end{' .. env .. '}'))
      return out
    end
    if c == 'pagebreak' then return pandoc.RawBlock('latex', '\\clearpage') end
  end
end

local chips = { chip = 'cybchip', ['chip-brand'] = 'cybchipbrand', ['chip-dark'] = 'cybchipdark', ['chip-red'] = 'cybchipred' }

local function span(el)
  for _, c in ipairs(el.classes) do
    local cmd = chips[c]
    if cmd then
      local out = pandoc.List({ pandoc.RawInline('latex', '\\' .. cmd .. '{') })
      out:extend(el.content)
      out:insert(pandoc.RawInline('latex', '}'))
      return out
    end
  end
end

local function code(el)
  if #el.classes > 0 then return nil end
  local out = {}
  for ch in el.text:gmatch('.') do
    out[#out + 1] = latex_escape(ch)
    if ch:match('[/%.%-_:@=]') then out[#out + 1] = '\\allowbreak{}' end
  end
  return pandoc.RawInline('latex', '\\texttt{' .. table.concat(out) .. '}')
end

local function code_block(el)
  if #el.classes > 0 then return nil end
  return pandoc.RawBlock('latex',
    '\\begin{Shaded}\n\\begin{Verbatim}[breaklines,breakanywhere,fontsize=\\footnotesize]\n'
    .. el.text .. '\n\\end{Verbatim}\n\\end{Shaded}')
end

-- Task lists. pandoc turns "[ ]" / "[x]" into a leading "☐" / "☒" word; draw a real box instead.
local function task_mark(item)
  local b = item[1]
  if b and (b.t == 'Plain' or b.t == 'Para') then
    local f = b.content[1]
    if f and f.t == 'Str' and (f.text == '\u{2610}' or f.text == '\u{2612}') then return f.text end
  end
  return nil
end

local function bullet_list(el)
  local any = false
  for _, item in ipairs(el.content) do if task_mark(item) then any = true; break end end
  if not any then return nil end
  local out = { '\\begin{cybchecklist}' }
  for _, item in ipairs(el.content) do
    local mark = task_mark(item)
    local blocks = pandoc.List()
    for _, b in ipairs(item) do blocks:insert(b:clone()) end
    local label = ''
    if mark then
      blocks[1].content:remove(1)
      if blocks[1].content[1] and blocks[1].content[1].t == 'Space' then blocks[1].content:remove(1) end
      label = (mark == '\u{2612}') and '\\cybboxdone' or '\\cybbox'
    end
    local s = pandoc.write(pandoc.Pandoc(blocks), 'latex'):gsub('%s+$', ''):gsub('\\tightlist\n?', '')
    out[#out + 1] = '\\item[' .. label .. '] ' .. s
  end
  out[#out + 1] = '\\end{cybchecklist}'
  return pandoc.RawBlock('latex', table.concat(out, '\n'))
end

local function dot(color) return '\\tikz[baseline=-0.55ex]\\fill[' .. color .. '] (0,0) circle (0.55ex);' end
local EMOJI = {
  [0x1F7E2] = dot('green!55!black'), [0x1F7E1] = dot('yellow!85!orange'), [0x1F7E0] = dot('orange'),
  [0x1F534] = dot('red!80!black'), [0x1F535] = dot('blue!70!black'), [0x26AA] = dot('gray!55'), [0x26AB] = dot('black'),
  [0x2705] = '\\tikz[baseline=-0.4ex]\\draw[green!45!black,line width=1.1pt,line cap=round,line join=round] (0,0) -- (0.32em,-0.42em) -- (0.95em,0.5em);',
  [0x274C] = '\\tikz[baseline=-0.4ex]\\draw[red!80!black,line width=1.1pt,line cap=round] (0,-0.45em) -- (0.8em,0.45em) (0,0.45em) -- (0.8em,-0.45em);',
  [0x26A0] = '\\tikz[baseline=-0.45ex]{\\draw[orange!90!black,line width=0.9pt,line join=round] (0,-0.5em) -- (0.9em,-0.5em) -- (0.45em,0.4em) -- cycle; \\fill[orange!90!black] (0.45em,-0.3em) circle (0.05em);}',
}

local function emoji(el)
  if not el.text:find('[\xE2\xF0]') then return nil end
  local out, buf, changed = {}, {}, false
  local function flush()
    if #buf > 0 then out[#out + 1] = pandoc.Str(table.concat(buf)); buf = {} end
  end
  for _, c in utf8.codes(el.text) do
    if c == 0xFE0F then
      changed = true
    elseif EMOJI[c] then
      flush(); out[#out + 1] = pandoc.RawInline('latex', '\\NoCaseChange{' .. EMOJI[c] .. '}'); changed = true
    elseif c >= 0x1F300 and c <= 0x1FAFF then
      io.stderr:write(string.format('cybertechna: emoji U+%X is not supported and was left out\n', c)); changed = true
    else
      buf[#buf + 1] = utf8.char(c)
    end
  end
  if not changed then return nil end
  flush()
  return out
end

-- [CONFIRM ...] / [TBD ...] / [VERIFY ...] markers, written as plain text in square brackets.
local function markers(inlines)
  local out, i, changed = pandoc.List(), 1, false
  while i <= #inlines do
    local el = inlines[i]
    if el.t == 'Str' and el.text:match('^%[(%u+)') and (el.text:match('^%[CONFIRM') or el.text:match('^%[TBD') or el.text:match('^%[VERIFY')) then
      local j, found = i, nil
      while j <= #inlines do
        local e = inlines[j]
        if e.t == 'Str' and e.text:find(']', 1, true) then found = j; break end
        j = j + 1
      end
      if found then
        out:insert(pandoc.RawInline('latex', '\\cybopen{'))
        for k = i, found do out:insert(inlines[k]) end
        out:insert(pandoc.RawInline('latex', '}'))
        i = found + 1; changed = true
        goto continue
      end
    end
    out:insert(el); i = i + 1
    ::continue::
  end
  if changed then return out end
end

return {
  { Pandoc = front_page },
  { Div = div, Span = span, Code = code, CodeBlock = code_block, BulletList = bullet_list },
  { Inlines = markers },
  { Str = emoji },
}
