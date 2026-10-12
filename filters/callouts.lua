local function has_class(el, name)
  for _, value in ipairs(el.classes) do
    if value == name then return true end
  end
  return false
end

function CodeBlock(el)
  if not FORMAT:match('latex') then return nil end
  local lines = 1
  local longest = 0
  for line in (el.text .. '\n'):gmatch('(.-)\n') do
    -- Estimate wrapped visual lines, not only source-line count.
    lines = lines + math.max(1, math.ceil(#line / 68))
    longest = math.max(longest, #line)
  end
  local panel = lines <= 24 and 'ShortCodePanel' or 'LongCodePanel'
  return {
    pandoc.RawBlock('latex', '\\begin{' .. panel .. '}'),
    el,
    pandoc.RawBlock('latex', '\\end{' .. panel .. '}')
  }
end

function Div(el)
  local env, title
  if has_class(el, 'failure') then
    env, title = 'FailureBox', 'Warning'
  elseif has_class(el, 'protip') then
    env, title = 'ProTipBox', 'Pro tip'
  elseif has_class(el, 'takeaways') then
    env, title = 'TakeawaysBox', 'Key takeaways'
  else
    return nil
  end
  if FORMAT:match('latex') then
    local blocks = {pandoc.RawBlock('latex', '\\begin{' .. env .. '}')}
    for _, block in ipairs(el.content) do blocks[#blocks + 1] = block end
    blocks[#blocks + 1] = pandoc.RawBlock('latex', '\\end{' .. env .. '}')
    return blocks
  end
  -- EPUB gets semantic text labels, so icons are not the only cue.
  table.insert(el.content, 1,
    pandoc.Para({pandoc.Strong({pandoc.Str(title)})}))
  return el
end

function Image(el)
  if FORMAT:match('latex') then el.src = el.src:gsub('%.svg$', '.pdf') end
  return el
end

function Header(el)
  if FORMAT:match('latex') and el.level == 1 then
    return {pandoc.RawBlock('latex', '\\clearpage'), el}
  end
  return nil
end
