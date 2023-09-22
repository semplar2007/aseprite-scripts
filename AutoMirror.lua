----------------------------------------------------------------------
-- Automatically synchronizes changes between several configured regions.
-- Useful for non-standard symmetries, like drawing seamless isometric tiles of any shape.
-- Latest version: https://github.com/semplar2007/aseprite-scripts
----------------------------------------------------------------------
local VERSION = "0.1"

local dialog

local trackedImage = app.image -- TODO: maybe refer to a sprite? test if origin calculation is correct
local rollbackImage -- a copy of app.image when you do Ctrl+C or Ctrl+V
-- first mirror contains the edited image, rest of mirrors contains rollback images, used when pressing "Finish"
local mirrors = {} -- elements are {selection, origin, image}
local numModificatioins = 0 -- just a visual helper

function onSpriteChange(ev)
  if ev.fromUndo then
    if #mirrors > 0 then
      mirrors[1].image = Image(trackedImage, mirrors[1].selection.bounds)
    end
    return
  end
  if #mirrors > 1 then
    editingImage = mirrors[1].image
    transparentPixel = app.pixelColor.rgba(0,0,0,0)
    modifyImage = Image(editingImage.width, editingImage.height)
    -- gather all changes across images
    for _, mirror in pairs(mirrors) do
      destinationX = mirror.origin.x
      destinationY = mirror.origin.y
      for px in modifyImage:pixels() do
        if mirror.selection:contains(destinationX + px.x, destinationY + px.y) then
          pixel = trackedImage:getPixel(destinationX + px.x, destinationY + px.y)
          if pixel ~= editingImage:getPixel(px.x, px.y) then
            px(pixel)
          end
        end
      end
    end
    -- deposit all changes across all images
    for _, mirror in pairs(mirrors) do
      trackedImage:drawImage(modifyImage, mirror.origin)
    end
    app.refresh()
    numModificatioins = numModificatioins + 1
    displayMirror()
  end
end

function strSelection(s)
  if not s then return "nil" end
  return "Selection(origin=(" .. s.origin.x .. ";" .. s.origin.y .. ")" ..
         ",bounds=(" .. s.bounds.x .. ";" .. s.bounds.y .. ";" .. s.bounds.width .. ";" .. s.bounds.height .. ")" ..
         ",empty=" .. tostring(s.isEmpty) .. ")"
end

function copySelection(s)
  result = Selection()
  result:add(s)
  return result
end

function isSameSelection(s1, s2)
  tmp1 = copySelection(s1)
  tmp2 = copySelection(s2)
  tmp1:subtract(s2)
  tmp2:subtract(s1)
  return tmp1.isEmpty and tmp2.isEmpty
end

function onBeforeCommand(ev)
  currentSelection = trackedImage.cel.sprite.selection
  if ev.name == "Copy" then
    if currentSelection.bounds then
      rollbackImage = Image(trackedImage)
      doReset()
      cutSelection = copySelection(currentSelection)
      cutSelection:intersect(trackedImage.cel.sprite.bounds)
      if not isSameSelection(cutSelection, currentSelection) then
        dialog:modify{id="status", text = "Can't initialize mirror: selection is out of sprite bounds"}
      else
        mirrors[#mirrors + 1] = {
          selection = cutSelection,
          origin = currentSelection.origin,
          image = Image(trackedImage, cutSelection.bounds)
        }
        displayMirror()
      end
    end
  elseif ev.name == "Paste" or ev.name == "DeselectMask" then
    if #mirrors > 0 and currentSelection and not currentSelection.isEmpty and
       not isSameSelection(currentSelection, mirrors[1].selection) then
      intersectsWithMirror = nil
      for _, mirror in pairs(mirrors) do
        check = Selection()
        check:add(currentSelection)
        check:intersect(mirror.selection)
        if not check.isEmpty then
          intersectsWithMirror = mirror.selection
          break
        end
      end
      if intersectsWithMirror then
        dialog:modify{id="status", text = "Can't place mirror: collides with already existing mirror"}
      else
        cutSelection = copySelection(currentSelection)
        cutSelection:intersect(trackedImage.cel.sprite.bounds)
        mirrors[#mirrors + 1] = {
          selection = cutSelection,
          origin = currentSelection.origin,
          image = Image(rollbackImage, cutSelection.bounds)
        }
        rollbackImage = Image(trackedImage)
        displayMirror()
      end
    end
  else
--    dialog:modify{id="status", text = "event " .. json.encode(ev)}
  end
end

function displayMirror()
  if #mirrors == 0 then
    dialog:modify{id="status", text = "Select pixels and Copy+Paste the region"}
  elseif #mirrors == 1 then
    dialog:modify{id="status", text = "Paste, Move and Deselect to create a Mirror"}
  else
    dialog:modify{id="status", text = "(" .. numModificatioins .. ") Mirroring " .. #mirrors .. " regions"}
  end
  enableOrDisableButtons()
end

function onSelectMirrorsClick()
  if #mirrors == 0 then
    dialog:modify{id="status", text = "Nothing to select: set up mirrors first"}
  end
  app.sprite.selection:deselect()
  for _, selectedDestination in pairs(mirrors) do
    app.sprite.selection:add(selectedDestination.selection)
  end
  app:refresh()
  dialog:modify{id="status", text = "Selected " .. #mirrors .. " active regions"}
end

function onSelectOriginClick()
  if #mirrors == 0 then
    dialog:modify{id="status", text = "Nothing to select: "}
  end
  app.sprite.selection:deselect()
  app.sprite.selection:add(mirrors[1].selection)
  app:refresh()
  dialog:modify{id="status", text = "Selected original region"}
end

function doReset()
  if #mirrors > 0 then
    rollbackImage = nil
    mirrors = {}
    numModifications = 0
    enableOrDisableButtons()
  end
end

function onFinishClick()
  if #mirrors > 1 then
    for i = 2,#mirrors do
      image = mirrors[i].image
      selection = mirrors[i].selection
      originX = mirrors[i].selection.origin.x
      originY = mirrors[i].selection.origin.y
      for px in image:pixels() do
        x = originX + px.x
        y = originY + px.y
        if selection:contains(x, y) then
          trackedImage:drawPixel(x, y, px())
        end
      end
    end
  end
  doReset()
  app:refresh()
  dialog:modify{id="status", text = "Not mirroring"}
end

function enableOrDisableButtons()
  dialog:modify{id="finish", enabled=(#mirrors > 0)}
  dialog:modify{id="selectorigin", enabled=(#mirrors > 0)}
  dialog:modify{id="selectmirrors", enabled=(#mirrors > 1)}
end

function onSiteChange()
  if trackedImage then
    trackedImage.cel.sprite.events:off(onSpriteChange)
  end
  trackedImage = app.image
  if trackedImage then
	trackedImage.cel.sprite.events:on('change', onSpriteChange)
  end
end

-- initialize
trackedImage.cel.sprite.events:on('change', onSpriteChange)
app.events:on('sitechange', onSiteChange)
app.events:on('beforecommand', onBeforeCommand)

-- shutdown
function shutdown()
  trackedImage.cel.sprite.events:off(onSpriteChange)
  app.events:off(onSiteChange)
  app.events:off(onBeforeCommand)
end

-- dialog
dialog = Dialog{title="Auto Mirror v" .. VERSION, onclose=shutdown}
dialog
  :label{id="status", text="Select pixels and Copy+Paste the region    "}
  :button{id="finish", text="Finish", onclick=onFinishClick}
  :button{id="selectorigin", text="Origin", onclick=onSelectOriginClick}
  :button{id="selectmirrors", text="Mirrors", onclick=onSelectMirrorsClick}
enableOrDisableButtons()
dialog:show{wait=false}
