-- set correct dimensions to frames around images
return  function(dom)
  local frames  = dom:query_selector("draw|frame")
  for _, frame in ipairs(frames) do
    local images = frame:query_selector("draw|image")
    if #images > 0 then
      local image = images[1]
      local width = image:get_attribute("svg:width")
      local height = image:get_attribute("svg:height")
      frame:set_attribute("svg:width", width)
      frame:set_attribute("svg:height", height)
      print("image dimensions", width, height)
    end
  end
  return dom
end
