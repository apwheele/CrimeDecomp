-- GitHub's Markdown renderer handles multiline display equations reliably when
-- they use fenced `math` blocks. Quarto's GFM writer otherwise emits multiline
-- $$ blocks, whose lines beginning with "+" are parsed as Markdown list items.
function Para(element)
  if #element.content ~= 1 then
    return nil
  end

  local math = element.content[1]
  if math.t ~= "Math" or math.mathtype ~= "DisplayMath" then
    return nil
  end

  local expression = math.text:gsub("^%s+", ""):gsub("%s+$", "")
  return pandoc.RawBlock(
    "markdown",
    "```math\n" .. expression .. "\n```"
  )
end
