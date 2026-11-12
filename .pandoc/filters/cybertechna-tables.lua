-- Cybertechna tables. Run after cybertechna.lua. Two jobs:
--
--  1. Style: every pipe table is drawn as a framed grid: a navy header row with white bold text, alternating white and
--     light-gray rows, hairline borders on every cell, and columns sized to their content (each at least as wide as its
--     longest word) so a "#" or "Owner" column stays narrow. A caption (": Caption" under the table) prints above it.
--     Front matter:  table-style: grid (default) | plain      table-header: navy (default) | blue | light
--                    table-size: small | footnotesize | normal (default: small, or footnotesize for tables of 5+ columns)
--     A table with merged cells, several bodies or a footer cannot be drawn as a grid and is left as pandoc draws it.
--
--  2. Landscape: a table is moved to a landscape page, together with its heading and the paragraph before it, when
--       - it has `wide-columns` or more columns (default 6; front matter `wide-columns: 5` changes it), or
--       - the line just above it is  <!-- landscape -->   (HTML comment on its own line, blank lines around it).
--     <!-- portrait -->  keeps a wide table on a portrait page. `landscape:` in the front matter sets the whole document:
--     default (the rules above), all (every table landscape) or none (every table portrait; beats the markers).
--     Any section can also be put on a landscape page with a fenced div:   ::: landscape  ...  :::
--
-- The page is switched with \newgeometry plus \pagewidth/\pageheight (geometry's `landscape` option is not allowed there, and
-- pdflscape would print the header and footer sideways), so the running header and page number stay where they are.
-- geometry warns that the right margin is negative; that is expected.

local threshold = 6
local style = 'grid'
local header_mode = 'navy'
local size_override = nil
local mode = 'default'

function Meta(meta)
  if meta['wide-columns'] then
    threshold = tonumber(pandoc.utils.stringify(meta['wide-columns'])) or threshold
  end
  if meta.landscape ~= nil then
    local v = pandoc.utils.stringify(meta.landscape):lower()
    if v == 'true' then v = 'all' elseif v == 'false' then v = 'none' end
    if v == 'all' or v == 'none' or v == 'default' then
      mode = v
    else
      io.stderr:write("cybertechna-tables: landscape: expected all, none or default, got '" .. v .. "'; using default\n")
    end
  end
  if meta['table-header'] then
    local v = pandoc.utils.stringify(meta['table-header']):lower()
    if v == 'navy' or v == 'blue' or v == 'light' then header_mode = v end
  end
  if meta['table-size'] then
    local v = pandoc.utils.stringify(meta['table-size']):lower()
    if v == 'small' or v == 'footnotesize' or v == 'normal' then size_override = v end
  end
  if meta['table-style'] then style = pandoc.utils.stringify(meta['table-style']) end
end

local function text_of(cell) return pandoc.utils.stringify(cell.contents) end

local function longest_word(cell)
  local m = 0
  for w in text_of(cell):gmatch('%S+') do m = math.max(m, #w) end
  return m
end

local function all_rows(tbl)
  local rows = {}
  for _, r in ipairs(tbl.head.rows) do rows[#rows + 1] = r end
  for _, body in ipairs(tbl.bodies) do
    for _, r in ipairs(body.body) do rows[#rows + 1] = r end
  end
  return rows
end

-- Column shares: the author's own widths if they differ from each other, else sized by content.
local function column_shares(tbl)
  local n = #tbl.colspecs
  local given, equal = true, true
  local w1 = tbl.colspecs[1][2]
  for i = 1, n do
    local w = tbl.colspecs[i][2]
    if type(w) ~= 'number' then given = false end
    if type(w) == 'number' and type(w1) == 'number' and math.abs(w - w1) > 1e-6 then equal = false end
  end
  local shares = {}
  if given and not equal then
    local total = 0
    for i = 1, n do total = total + tbl.colspecs[i][2] end
    for i = 1, n do shares[i] = tbl.colspecs[i][2] / total end
    return shares
  end
  local len, word, filled = {}, {}, {}
  for i = 1, n do len[i] = 0; word[i] = 0; filled[i] = false end
  for _, row in ipairs(all_rows(tbl)) do
    for i, cell in ipairs(row.cells) do
      if i <= n then
        len[i] = math.max(len[i], math.min(#text_of(cell), 70))
        word[i] = math.max(word[i], math.min(longest_word(cell), 14))
      end
    end
  end
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do
      for i, cell in ipairs(row.cells) do
        if i <= n and text_of(cell):match('%S') then filled[i] = true end
      end
    end
  end
  -- A column with nothing in it is a fill-in column (Notes, Initials): give it room, unless most columns are empty (a grid to tick).
  local blank = 0
  for i = 1, n do if not filled[i] then blank = blank + 1 end end
  local blank_floor = (blank * 3 <= n) and 22 or 12
  local total = 0
  for i = 1, n do
    len[i] = math.max(len[i], word[i] + 5, 8)
    if not filled[i] and #tbl.bodies[1].body > 0 then len[i] = math.max(len[i], blank_floor) end
    total = total + len[i]
  end
  for i = 1, n do shares[i] = len[i] / total end
  return shares
end

local function supported(tbl)
  if #tbl.bodies ~= 1 or #tbl.foot.rows > 0 then return false end
  for _, row in ipairs(all_rows(tbl)) do
    for _, cell in ipairs(row.cells) do
      if cell.col_span > 1 or cell.row_span > 1 then return false end
    end
  end
  return true
end

local function cell_tex(cell, header)
  local blocks = pandoc.List()
  for _, b in ipairs(cell.contents) do blocks:insert(b:clone()) end
  local s = pandoc.write(pandoc.Pandoc(blocks), 'latex'):gsub('%s+$', '')
  s = s:gsub('\\tightlist\n?', '')
  if header and s ~= '' then
    local color = (header_mode == 'light') and 'darkblue' or 'white'
    s = '{\\bfseries\\color{' .. color .. '} ' .. s .. '}'
  end
  return s
end

local align_prefix = {
  AlignLeft = '\\raggedright\\arraybackslash',
  AlignDefault = '\\raggedright\\arraybackslash',
  AlignRight = '\\raggedleft\\arraybackslash',
  AlignCenter = '\\centering\\arraybackslash',
}

local header_fill = { navy = '\\rowcolor{darkblue}', blue = '\\rowcolor{cyberblue}', light = '\\rowcolor{cyberblue50}' }

local function latex_escape(s)
  return (s:gsub('[\\{}$&#^_%%~]', function(c)
    if c == '\\' then return '\\textbackslash{}' end
    if c == '^' then return '\\^{}' end
    if c == '~' then return '\\~{}' end
    return '\\' .. c
  end))
end

local function grid_table(tbl, landscape)
  local n = #tbl.colspecs
  local shares = column_shares(tbl)
  local spec = {}
  for i = 1, n do
    spec[#spec + 1] = string.format('>{%s}p{%.4f\\dimexpr\\linewidth-%d\\tabcolsep-%d\\arrayrulewidth\\relax}',
      align_prefix[tbl.colspecs[i][1]] or align_prefix.AlignDefault, shares[i], 2 * n, n + 1)
  end
  local size = size_override or ((n >= 5 and not landscape) and 'footnotesize' or 'small')
  if size == 'normal' then size = 'normalsize' end
  local out = {}
  out[#out + 1] = '{\\' .. size .. '\\setlength{\\tabcolsep}{6pt}\\renewcommand{\\arraystretch}{1.3}'
    .. '\\arrayrulecolor{cybgrid}\\setlength{\\arrayrulewidth}{0.5pt}'
  -- A table inside a slide column (marked by cybertechna-slides.lua) cannot be a longtable: it would leave the column.
  local inline = tbl.attr and tbl.attr.attributes['cyb-inline'] == '1'
  local env = inline and 'tabular' or 'longtable'
  out[#out + 1] = '\\begin{' .. env .. '}' .. (inline and '' or '[l]') .. '{|' .. table.concat(spec, '|') .. '|}'
  local function row_tex(row, header)
    local cells = {}
    for _, cell in ipairs(row.cells) do cells[#cells + 1] = cell_tex(cell, header) end
    return table.concat(cells, ' &\n  ') .. ' \\\\ \\hline'
  end
  out[#out + 1] = '\\hline'
  if #tbl.head.rows > 0 then
    for _, row in ipairs(tbl.head.rows) do
      out[#out + 1] = header_fill[header_mode] .. row_tex(row, true)
    end
    if not inline then out[#out + 1] = '\\endhead' end
  end
  local body = tbl.bodies[1].body
  for k, row in ipairs(body) do
    local color = (k % 2 == 0) and '\\rowcolor{lightgray}' or '\\rowcolor{white}'
    out[#out + 1] = color .. row_tex(row, false)
  end
  out[#out + 1] = '\\end{' .. env .. '}}'
  local caption = pandoc.utils.stringify(tbl.caption.long)
  local tex = table.concat(out, '\n')
  if caption ~= '' then
    tex = '\\Needspace{6\\baselineskip}\\noindent{\\cybheadfont\\color{darkblue}\\small ' .. latex_escape(caption) .. '}\\par\\vspace{3pt}\n' .. tex
  end
  return pandoc.RawBlock('latex', tex)
end

local function is_para(b) return b.t == 'Para' or b.t == 'Plain' end

local function marker_of(b)
  if b.t ~= 'RawBlock' or not b.format:match('^html') then return nil end
  local word = b.text:match('^%s*<!%-%-%s*(%a+)%s*%-%->%s*$')
  if word == 'landscape' or word == 'portrait' then return word end
  return nil
end

local LAND_ON = '\\clearpage\\newgeometry{left=0.7in,top=0.8in,textwidth=9.6in,textheight=7.05in,headheight=14pt,footskip=26pt}'
  .. '\\pagewidth=11in\\pageheight=8.5in\\setlength{\\headwidth}{\\textwidth}\\relax'
local LAND_OFF = '\\clearpage\\restoregeometry\\pagewidth=8.5in\\pageheight=11in\\setlength{\\headwidth}{\\textwidth}\\relax'

local convert

-- Walks a list of blocks. `inland` means the blocks are already on a landscape page (a ::: landscape div).
convert = function(blocks, inland)
  local out, i = pandoc.List(), 1
  local pending = nil
  while i <= #blocks do
    local b = blocks[i]
    if marker_of(b) then
      pending = marker_of(b); i = i + 1
    elseif b.t == 'Div' and b.classes:includes('landscape') then
      out:insert(pandoc.RawBlock('latex', LAND_ON))
      out:extend(convert(b.content, true))
      out:insert(pandoc.RawBlock('latex', LAND_OFF))
      i = i + 1
    elseif b.t == 'Table' then
      local wide = #b.colspecs >= threshold
      if mode == 'all' then wide = true
      elseif mode == 'none' then wide = false
      elseif pending == 'landscape' then wide = true
      elseif pending == 'portrait' then wide = false end
      pending = nil
      if inland then wide = false end
      local drawn = b
      if style == 'grid' and supported(b) then
        drawn = grid_table(b, wide or inland)
      else
        -- plain style: header in tracked small caps, widen squeezed columns (equal dashes in the source)
        local shares = column_shares(b)
        for c = 1, #b.colspecs do b.colspecs[c][2] = shares[c] end
        for _, row in ipairs(b.head.rows) do
          for _, cell in ipairs(row.cells) do
            for _, blk in ipairs(cell.contents) do
              if blk.t == 'Plain' or blk.t == 'Para' then
                local inl = pandoc.List({ pandoc.RawInline('latex', '\\cybth{') })
                inl:extend(blk.content); inl:insert(pandoc.RawInline('latex', '}'))
                blk.content = inl
              end
            end
          end
        end
      end
      if wide then
        -- take back the heading and the text since it (at most 3 blocks), unless a landscape section just ended
        local take = pandoc.List()
        while #out > 0 and #take < 3 do
          local prev = out[#out]
          if prev.t == 'RawBlock' then break end
          take:insert(1, prev); out:remove(#out)
          if prev.t == 'Header' then break end
        end
        take:insert(drawn)
        local k = i + 1
        if k <= #blocks and is_para(blocks[k]) then take:insert(blocks[k]); k = k + 1 end
        out:insert(pandoc.RawBlock('latex', LAND_ON))
        out:extend(take)
        out:insert(pandoc.RawBlock('latex', LAND_OFF))
        i = k
      else
        -- keep a heading (and the paragraph under it) with its table: start a new page before the heading if the table would not fit
        local back = #out
        if back > 0 and is_para(out[back]) then back = back - 1 end
        if back > 0 and out[back].t == 'Header' and drawn.t == 'RawBlock' then
          out:insert(back, pandoc.RawBlock('latex', '\\Needspace{9\\baselineskip}'))
        end
        out:insert(drawn); i = i + 1
      end
    else
      out:insert(b); i = i + 1
    end
  end
  return out
end

function Pandoc(doc)
  doc.blocks = convert(doc.blocks, false)
  return doc
end

return { { Meta = Meta }, { Pandoc = Pandoc } }
