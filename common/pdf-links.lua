-- Pandoc Lua filter that repairs internal links in the PDF manuals.
--
-- The API reference markdown comes from doxybook2 and is rewritten by the
-- pdf-prep perl rules, so its link targets do not always match the
-- identifiers pandoc generates for headings. For example a link to
-- "#enum--mqttqos" has to point at the heading id "enum-_mqttqos".
--
-- Every internal link whose target is not an existing identifier is matched
-- against the identifiers first with case ignored and '_' treated as '-',
-- then with '-', '_' and '.' dropped and the leading non-letters pandoc
-- strips removed. A doxybook2 "#file-" link is also tried without the
-- prefix, since the file heading is just the file name. A link that still
-- has no target, or matches more than one, is replaced by its text so the
-- PDF has no dead links. Set PDF_LINKS_REPORT=1 to list the rewritten and
-- removed links on stderr.

local report = os.getenv('PDF_LINKS_REPORT') == '1'

local function close(id)
  return (id:lower():gsub('_', '-'))
end

local function loose(id)
  return (id:lower():gsub('^[^%a]+', ''):gsub('[-_.]', ''))
end

function Pandoc(doc)
  local exact = {}
  local byClose = {}
  local byLoose = {}

  local function index(map, k, id)
    if map[k] == nil then
      map[k] = id
    elseif map[k] ~= id then
      -- Two identifiers share a key, so the match would be a guess
      map[k] = false
    end
  end

  local function add(el)
    local id = el.identifier
    if id and id ~= '' and not exact[id] then
      exact[id] = true
      index(byClose, close(id), id)
      index(byLoose, loose(id), id)
    end
  end

  local function find(id)
    if exact[id] then
      return id
    end
    return byClose[close(id)] or byLoose[loose(id)]
  end

  doc:walk({ Header = add, Div = add, Span = add, Table = add,
             Figure = add, CodeBlock = add, Code = add, Image = add })

  return doc:walk({
    Link = function(link)
      -- Links to another markdown file are internal once the files are
      -- concatenated into one PDF
      local id = link.target:match('^#(.+)$') or
                 link.target:match('^[%w_./-]+%.md#(.+)$')
      if not id then
        return nil
      end
      local match = find(id)
      if not match and id:match('^file%-') then
        match = find(id:sub(6))
      end
      if match then
        if report and match ~= id then
          io.stderr:write('pdf-links: ' .. link.target .. ' -> #' ..
                          match .. '\n')
        end
        link.target = '#' .. match
        return link
      end
      if report then
        io.stderr:write('pdf-links: no target for ' .. link.target .. '\n')
      end
      return link.content
    end
  })
end
