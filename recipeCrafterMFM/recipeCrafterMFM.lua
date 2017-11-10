require "/scripts/debugUtilsCN.lua"

RecipeCrafterMFMApi = {};
local rcUtils = {};
local ingredientsChanged = false;
local isExpectingOutputChange = false;

function init(virtual)
  DebugUtilsCN.init("[RCMFM]")
  local outputConfigPath = config.getParameter("outputConfig")
  if outputConfigPath == nil then
    storage.possibleOutputs = {}
  else
    storage.possibleOutputs = root.assetJson(outputConfigPath).possibleOutput
  end
  storage.slotCount = config.getParameter("slotCount", 16)
  storage.outputSlot = config.getParameter("outputSlot", 15)
  DebugUtilsCN.logDebug("Setting output slot to: " .. storage.outputSlot)
  if storage.outputSlot < 0 then
    storage.outputSlot = 0
  end
  storage.timePassed = 0
  storage.outputRecipe = nil
  storage.outputPlacedSuccessfully = false
  storage.craftSoundDelaySeconds = config.getParameter("craftSoundDelaySeconds", 10) -- In seconds
  storage.craftSoundIsPlaying = false
  storage.recipeGroup = config.getParameter("recipeGroup")
  storage.noRecipeBookGroup = storage.recipeGroup .. "NoRecipeBook"
  ingredientsChanged = true
end

function update(dt)
  if(not ingredientsChanged) then
    return
  end
  DebugUtilsCN.logDebug("Change")
  ingredientsChanged = false
  isExpectingOutputChange = true
  rcUtils.checkCraftSoundDelay(dt)
  rcUtils.consumeIngredientsIfOutputTaken()
  local ingredients = rcUtils.getIngredients()
  if ingredients == nil then
    DebugUtilsCN.logDebug("No Ingredients")
    isExpectingOutputChange = false
    return
  end
  if not rcUtils.validateCurrentRecipe(storage.outputRecipe, ingredients) then
    DebugUtilsCN.logDebug("Removing Output")
    isExpectingOutputChange = true
    rcUtils.removeOutput()
  end
  if not rcUtils.shouldLookForRecipe() then
    DebugUtilsCN.logDebug("No Look")
    isExpectingOutputChange = false
    return
  end
  local numberOfIngredients = 0
  for slot,item in pairs(ingredients) do
    if slot ~= storage.outputSlot + 1 then
      numberOfIngredients = numberOfIngredients + 1
    end
  end
  if numberOfIngredients > 0 then
    DebugUtilsCN.logDebug("Finding Output")
    local outputRecipe = rcUtils.findOutput(ingredients)
    if outputRecipe then
    DebugUtilsCN.logDebug("Updating Output")
      rcUtils.updateOutputSlotWith(outputRecipe)
    else
      rcUtils.removeOutput()
    end
  else
    rcUtils.removeOutput()
  end
  isExpectingOutputChange = false
end

function die()
  rcUtils.removeOutput()
end

-------------------------------------------------------------------

function containerCallback()
  if(not isExpectingOutputChange) then
    ingredientsChanged = true
    DebugUtilsCN.logDebug("Ingredients changed")
  end
end

-------------------------------------------------------------------

function rcUtils.updateOutputSlotWith(recipe)
  storage.outputRecipe = recipe
  local existingOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if not existingOutput then
    DebugUtilsCN.logDebug("Setting output item to: " .. storage.outputRecipe.output.name .. " in slot " .. storage.outputSlot)
    world.containerPutItemsAt(entity.id(), storage.outputRecipe.output, storage.outputSlot)
    local newOutput = world.containerItemAt(entity.id(), storage.outputSlot)
    if newOutput == nil then
      storage.outputPlacedSuccessfully = false
    elseif newOutput.name == storage.outputRecipe.output.name then
      storage.outputPlacedSuccessfully = true
    else
      storage.outputPlacedSuccessfully = false
    end
    if not storage.outputPlacedSuccessfully then
      if newOutput ~= nil then
        DebugUtilsCN.logDebug("Output not successfully placed, item found instead: " .. newOutput.name)
      else
        DebugUtilsCN.logDebug("Output not successfully placed, and no item found at slot " .. storage.outputSlot)
      end
    end
  else
    DebugUtilsCN.logDebug("Could not place output because of existing item with name: " .. existingOutput.name .. " in slot " .. storage.outputSlot)
  end
end

function rcUtils.recipeCanBeCrafted(recipe)
  if storage.recipeGroup == nil then
    DebugUtilsCN.logDebug("No Recipe Group specified")
    return false
  end
  DebugUtilsCN.logDebug("Recipe group specified: " .. storage.recipeGroup)
  local canBeCrafted = false
  for _,group in ipairs(recipe.groups) do
    if group == storage.recipeGroup or group == storage.noRecipeBookGroup then
      canBeCrafted = true
      break
    end
  end
  return canBeCrafted
end

function rcUtils.findRecipe(recipesForItem, ingredients)
  local recipeFound = nil
  for _,recipe in ipairs(recipesForItem) do
    if rcUtils.recipeCanBeCrafted(recipe) and rcUtils.checkIngredientsMatchRecipe(recipe, ingredients) then
      recipeFound = recipe
      break;
    end
  end
  return recipeFound
end

function rcUtils.findOutput(ingredients)
  local outputRecipe = nil
  for _,itemName in ipairs(storage.possibleOutputs) do
    local recipesForItem = root.recipesForItem(itemName)
    if recipesForItem ~= nil and #recipesForItem > 0 then
      outputRecipe = rcUtils.findRecipe(recipesForItem, ingredients)
      if outputRecipe then
        DebugUtilsCN.logDebug("Found recipe with output name: " .. outputRecipe.output.name)
        break;
      end
    end
  end
  return outputRecipe
end

function rcUtils.checkIngredientsMatchRecipe(recipe, ingredients)
  DebugUtilsCN.logDebug("Checking Recipe Ingredients For Recipe: " .. recipe.output.name)
  -- Check the recipe inputs to verify ingredients match with all inputs
  local ingredientsUsed = {}
  local matchesAllInput = true
  for i,input in ipairs(recipe.input) do
      DebugUtilsCN.logDebug("Checking Input: " .. input.name)
    local matchFound = false
    for slot,ingred in pairs(ingredients) do
      DebugUtilsCN.logDebug("Checking Ingred: " .. ingred.name)
      if ingred.name ~= recipe.output.name then
        if input.name == ingred.name and input.count <= ingred.count then
          matchFound = true
          DebugUtilsCN.logDebug("Match Found: " .. ingred.name)
          table.insert(ingredientsUsed, ingred.name)
          break
        end
      end
    end
    if not matchFound then
      DebugUtilsCN.logDebug("All Inputs Do Not Match")
      matchesAllInput = false
      break;
    end
  end
  -- All ingredients that exist should be used
  for slot,ingred in pairs(ingredients) do
    if ingred.name ~= recipe.output.name then
      local matches = false
      for _,ingreds in ipairs(ingredientsUsed) do
        DebugUtilsCN.logDebug("Checking Ingredient Matches With: " .. ingreds)
        if ingred.name == ingreds then
          matches = true
          DebugUtilsCN.logDebug("Ingredient Matches: " .. ingred.name)
          break
        end
      end
      if not matches then
        DebugUtilsCN.logDebug("Ingredient Doesn't Match: " .. ingred.name)
        matchesAllInput = false
        break;
      end
    end
  end
  return matchesAllInput
end

function rcUtils.checkCraftSoundDelay(dt)
  if not storage.craftSoundIsPlaying then
    return
  end
  storage.timePassed = storage.timePassed + dt
  DebugUtilsCN.logDebug("Craft sound playing, time passed: " .. storage.timePassed)
  if storage.timePassed <= 0 then
    return
  end
  if storage.timePassed >= storage.craftSoundDelaySeconds then
    DebugUtilsCN.logDebug("Stopping all onCraft sounds")
    storage.timePassed = 0
    storage.craftSoundIsPlaying = false
    animator.stopAllSounds("onCraft")
  end
end

function rcUtils.consumeIngredientsIfOutputTaken()
  if storage.outputRecipe == nil or not storage.outputPlacedSuccessfully then
    return
  end
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if outputSlotItem == nil then
    DebugUtilsCN.logDebug("Consuming ingredients for recipe with output: " .. storage.outputRecipe.output.name)
    for _,input in ipairs(storage.outputRecipe.input) do
      DebugUtilsCN.logDebug("Consuming ingredient with name: " .. input.name)
      world.containerConsume(entity.id(), input)
    end
    rcUtils.onCraft()
    storage.outputRecipe = nil
    storage.outputPlacedSuccessfully = false
    return
  end
  local recipeOutput = storage.outputRecipe.output
  if outputSlotItem.name == recipeOutput.name and outputSlotItem.count == recipeOutput.count then
    return
  end
end

function rcUtils.getIngredients()
  local ingredientNames = {}
  local uniqueIngredients = {}
  local ingredients = world.containerItems(entity.id())
  for slot,item in pairs(ingredients) do
    if ingredientNames[item.name] == nil then
      item.count = world.containerAvailable(entity.id(), item.name)
      ingredientNames[item.name] = true
      uniqueIngredients[slot] = item
    end
  end
  return uniqueIngredients
end

function rcUtils.removeOutput()
  -- Find existing output
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if not outputSlotItem then
    storage.outputRecipe = nil
    storage.outputPlacedSuccessfully = false
    return
  end
  
  if storage.outputRecipe then
    local outputItem = storage.outputRecipe.output
    -- If the item in the output is the same as the one we placed
    -- then we remove the amount we placed and spit the rest out of the machine
    if outputSlotItem.name == outputItem.name then
      world.containerConsumeAt(entity.id(), storage.outputSlot, outputItem.count)
    end
  end
  -- If output still exists, we ignore it and prevent adding new output
  storage.outputRecipe = nil
  storage.outputPlacedSuccessfully = false
end

function rcUtils.validateCurrentRecipe(recipe, ingredients)
  if recipe == nil or ingredients == nil then
    return false
  end
  return rcUtils.checkIngredientsMatchRecipe(recipe, ingredients)
end

function rcUtils.shouldLookForRecipe()
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if outputSlotItem == nil then
    DebugUtilsCN.logDebug("No output item, so look for recipe")
    return true
  end
  if storage.outputRecipe == nil then
    DebugUtilsCN.logDebug("No output recipe, so look for recipe")
    return true
  end
  local outputRecipeOutput = storage.outputRecipe.output
  DebugUtilsCN.logDebug("Verifying found output (" .. outputSlotItem.name .. ", " .. outputSlotItem.count .. ") with recipe (" .. outputRecipeOutput.name .. ", " .. outputRecipeOutput.count .. ")")
  if outputRecipeOutput.name ~= outputSlotItem.name or outputRecipeOutput.count ~= outputSlotItem.count then
    DebugUtilsCN.logDebug("Output item isn't the same, so look for recipe")
    return true
  end
  return false
end

function rcUtils.onCraft()
  if animator.hasSound("onCraft") and not storage.craftSoundIsPlaying then
    DebugUtilsCN.logDebug("Playing onCraft sounds")
    storage.timePassed = 0
    animator.playSound("onCraft")
    storage.craftSoundIsPlaying = true
  end
end