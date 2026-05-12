local query = require "vim.treesitter.query"

local html_script_type_languages = {
  ["importmap"] = "json",
  ["module"] = "javascript",
  ["application/ecmascript"] = "javascript",
  ["text/ecmascript"] = "javascript",
}

local non_filetype_match_injection_language_aliases = {
  ex = "elixir",
  pl = "perl",
  sh = "bash",
  uxn = "uxntal",
  ts = "typescript",
}

-- compatibility shim for breaking change on nightly/0.11
local opts = vim.fn.has "nvim-0.10" == 1 and { force = true, all = false } or true

local function get_parser_from_markdown_info_string(injection_alias)
  local match = vim.filetype.match { filename = "a." .. injection_alias }
  return match or non_filetype_match_injection_language_aliases[injection_alias] or injection_alias
end

local function error(str)
  vim.api.nvim_err_writeln(str)
end

local function valid_args(name, pred, count, strict_count)
  local arg_count = #pred - 1

  if strict_count then
    if arg_count ~= count then
      error(string.format("%s must have exactly %d arguments", name, count))
      return false
    end
  elseif arg_count < count then
    error(string.format("%s must have at least %d arguments", name, count))
    return false
  end

  return true
end

local function get_capture_nodes(match, capture_id)
  local capture = match[capture_id]
  if not capture then
    return
  end

  if type(capture) ~= "table" then
    return { capture }
  end

  if #capture == 0 then
    return
  end

  return capture
end

local function get_capture_text(match, capture_id, bufnr, metadata)
  local nodes = get_capture_nodes(match, capture_id)
  if not nodes then
    return
  end

  local text = {}
  for _, node in ipairs(nodes) do
    table.insert(text, vim.treesitter.get_node_text(node, bufnr, metadata) or "")
  end

  return table.concat(text, "")
end

---@param match (TSNode|nil)[]
---@param _pattern string
---@param _bufnr integer
---@param pred string[]
---@return boolean|nil
query.add_predicate("nth?", function(match, _pattern, _bufnr, pred)
  if not valid_args("nth?", pred, 2, true) then
    return
  end

  local node = match[pred[2]] ---@type TSNode
  local n = tonumber(pred[3])
  if node and node:parent() and node:parent():named_child_count() > n then
    return node:parent():named_child(n) == node
  end

  return false
end, opts)

---@param match (TSNode|nil)[]
---@param _pattern string
---@param bufnr integer
---@param pred string[]
---@return boolean|nil
query.add_predicate("is?", function(match, _pattern, bufnr, pred)
  if not valid_args("is?", pred, 2) then
    return
  end

  -- Avoid circular dependencies
  local locals = require "nvim-treesitter.locals"
  local node = match[pred[2]]
  local types = { unpack(pred, 3) }

  if not node then
    return true
  end

  local _, _, kind = locals.find_definition(node, bufnr)

  return vim.tbl_contains(types, kind)
end, opts)

---@param match (TSNode|nil)[]
---@param _pattern string
---@param _bufnr integer
---@param pred string[]
---@return boolean|nil
query.add_predicate("kind-eq?", function(match, _pattern, _bufnr, pred)
  if not valid_args(pred[1], pred, 2) then
    return
  end

  local node = match[pred[2]]
  local types = { unpack(pred, 3) }

  if not node then
    return true
  end

  return vim.tbl_contains(types, node:type())
end, opts)

---@param match (TSNode|nil)[]
---@param _ string
---@param bufnr integer
---@param pred string[]
---@return boolean|nil
query.add_directive("set-lang-from-mimetype!", function(match, _, bufnr, pred, metadata)
  local capture_id = pred[2]
  local type_attr_value = get_capture_text(match, capture_id, bufnr)
  if not type_attr_value then
    return
  end
  local configured = html_script_type_languages[type_attr_value]
  if configured then
    metadata["injection.language"] = configured
  else
    local parts = vim.split(type_attr_value, "/", {})
    metadata["injection.language"] = parts[#parts]
  end
end, opts)

---@param match (TSNode|nil)[]
---@param _ string
---@param bufnr integer
---@param pred string[]
---@return boolean|nil
query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
  local capture_id = pred[2]
  local injection_alias = get_capture_text(match, capture_id, bufnr)
  if not injection_alias then
    return
  end
  metadata["injection.language"] = get_parser_from_markdown_info_string(injection_alias:lower())
end, opts)

-- Just avoid some annoying warnings for this directive
query.add_directive("make-range!", function() end, opts)

--- transform node text to lower case (e.g., to make @injection.language case insensitive)
---
---@param match (TSNode|nil)[]
---@param _ string
---@param bufnr integer
---@param pred string[]
---@return boolean|nil
query.add_directive("downcase!", function(match, _, bufnr, pred, metadata)
  local id = pred[2]
  local text = get_capture_text(match, id, bufnr, { metadata = metadata[id] })
  if not text then
    return
  end

  if not metadata[id] then
    metadata[id] = {}
  end
  metadata[id].text = string.lower(text)
end, opts)
