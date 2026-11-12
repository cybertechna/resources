-- Cybertechna slides: block-level rules for the `slides` type. Runs after cybertechna.lua (which has already lifted the
-- title and shifted headings so the top level in use is level 1) and before cybertechna-tables.lua.
--
--   * A document that uses both # and ## : # is a section divider slide, ## is a content slide.
--     A document that uses only one level : that level is a content slide, the next one down is a sub-heading.
--     (The template reads the `slide-sections` variable set here.)
--   * A line of three dashes (---) starts a continuation slide with no title.
--   * ::: notes ... ::: is speaker notes and is left out of the PDF.
--   * ::::: columns / :::: {.column width="40%"} ... lays blocks out side by side.
local function has_level(blocks, n)
  local found = false
  blocks:walk({ Header = function(h) if h.level == n then found = true end end })
  return found
end

local function columns(el)
  local cols = {}
  for _, b in ipairs(el.content) do
    if b.t == 'Div' and b.classes:includes('column') then cols[#cols + 1] = b end
  end
  if #cols == 0 then return nil end
  local gap = 0.03
  local total_gap = gap * (#cols - 1)
  local widths, fixed, auto = {}, 0, 0
  for i, c in ipairs(cols) do
    local w = c.attributes.width and tonumber(c.attributes.width:match('([%d%.]+)%%'))
    if w then widths[i] = w / 100; fixed = fixed + w / 100 else auto = auto + 1 end
  end
  local share = auto > 0 and math.max((1 - fixed) / auto, 0.1) or 0
  local scale = (1 - total_gap) / math.max(fixed + share * auto, 0.01)
  local out = pandoc.List()
  -- paracol sets the columns side by side and lets blocks (lists, callouts, images) flow inside them.
  out:insert(pandoc.RawBlock('latex', '\\begin{paracol}{' .. #cols .. '}'))
  if #cols == 2 then
    out:insert(pandoc.RawBlock('latex', string.format('\\columnratio{%.4f}', (widths[1] or share) * scale / (1 - gap))))
  end
  for i, c in ipairs(cols) do
    c.content = c.content:walk({ Table = function(t)
      local a = t.attr
      t.attr = pandoc.Attr(a.identifier, a.classes, { ['cyb-inline'] = '1' })
      return t
    end })
    out:extend(c.content)
    if i < #cols then out:insert(pandoc.RawBlock('latex', '\\switchcolumn')) end
  end
  out:insert(pandoc.RawBlock('latex', '\\end{paracol}'))
  return out
end

local function div(el)
  if el.classes:includes('notes') or el.classes:includes('speaker-notes') then return {} end
  if el.classes:includes('columns') then return columns(el) end
end

local function rule() return pandoc.RawBlock('latex', '\\clearpage') end

function Pandoc(doc)
  local meta = doc.meta
  local two = has_level(doc.blocks, 1) and has_level(doc.blocks, 2)
  if two then meta['slide-sections'] = true end
  local blocks = doc.blocks:walk({ Div = div, HorizontalRule = rule })
  -- A new page before every slide heading (a divider or a content slide).
  local top = two and 2 or 1
  local out = pandoc.List()
  for _, b in ipairs(blocks) do
    if b.t == 'Header' and b.level <= top then out:insert(rule()) end
    out:insert(b)
  end
  blocks = out
  return pandoc.Pandoc(blocks, meta)
end
