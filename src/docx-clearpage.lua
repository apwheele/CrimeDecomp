local function is_clearpage(block)
  return block.t == "RawBlock" and
    block.format == "tex" and
    block.text:match("^\\clearpage%s*$")
end

function Pandoc(doc)
  if not FORMAT:match("docx") then
    return doc
  end

  local blocks = {}
  for index, block in ipairs(doc.blocks) do
    if is_clearpage(block) then
      local next_block = doc.blocks[index + 1]
      -- Word's heading styles already start sections on a new page. Adding a
      -- second explicit break before a heading can create a blank page.
      if not next_block or next_block.t ~= "Header" then
        table.insert(
          blocks,
          pandoc.RawBlock(
            "openxml",
            '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
          )
        )
      end
    else
      table.insert(blocks, block)
    end
  end

  doc.blocks = blocks
  return doc
end
