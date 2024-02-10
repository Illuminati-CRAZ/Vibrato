---@diagnostic disable: lowercase-global
debug = "hi"

function draw()
    imgui.Begin("Vibrato")
    resetQueue()
    resetCache()

    state.IsWindowHovered = imgui.IsWindowHovered()

    local start = state.GetValue("start") or 0
    local stop = state.GetValue("stop") or 0
    local amplitude = state.GetValue("amplitude") or 100
    local stopamplitude = state.GetValue("stopamplitude") or 100
    local increment = state.GetValue("increment") or 16
    local tp_increment = state.GetValue("tp_increment") or .125

    local useSnap = state.GetValue("useSnap")
    if useSnap == nil then useSnap = true end
    local preserveNotePositions = state.GetValue("preserveNotePositions")
    if preserveNotePositions == nil then preserveNotePositions = true end
    local oneSided = state.GetValue("oneSided")
    if oneSided == nil then oneSided = false end

    if (imgui.Button("Current") or utils.IsKeyPressed(keys.Q)) then start = state.SelectedHitObjects[1] and state.SelectedHitObjects[1].StartTime or state.SongTime end imgui.SameLine()
    _, start = imgui.InputFloat("Start", start, 1)
    lastNoteIndex = #state.SelectedHitObjects
    if (imgui.Button("Current##1") or utils.IsKeyPressed(keys.W)) then stop = state.SelectedHitObjects[lastNoteIndex] and state.SelectedHitObjects[lastNoteIndex].StartTime or state.SongTime end imgui.SameLine()
    _, stop = imgui.InputFloat("Stop", stop, 1)
    _, amplitude = imgui.InputFloat("Start Amplitude", amplitude, 1)
    _, stopamplitude = imgui.InputFloat("Stop Amplitude", stopamplitude, 1)
    _, increment = imgui.InputFloat("Increment", increment, 1)
    _, tp_increment = imgui.InputFloat("Teleport Increment", tp_increment, .125)

    _, useSnap = imgui.Checkbox("Treat increment as 1/n beat snap", useSnap)
    _, preserveNotePositions = imgui.Checkbox("Preserve note positions", preserveNotePositions)
    _, oneSided = imgui.Checkbox("One-Sided Vibing", oneSided)

    state.SetValue("start", start)
    state.SetValue("stop", stop)
    state.SetValue("amplitude", amplitude)
    state.SetValue("stopamplitude", stopamplitude)
    state.SetValue("increment", increment)
    state.SetValue("tp_increment", tp_increment)

    state.SetValue("useSnap", useSnap)
    state.SetValue("preserveNotePositions", preserveNotePositions)
    state.SetValue("oneSided", oneSided)

    if imgui.Button("vibe") or utils.IsKeyPressed(keys.E) then
        vibratoSetup(start, stop, amplitude, increment, stopamplitude, tp_increment, oneSided, preserveNotePositions, useSnap)
    end
    imgui.SameLine();
    if imgui.Button("vibe per section (selected notes only)") or utils.IsKeyPressed(keys.R) then
      if (#state.SelectedHitObjects >= 2) then
        groups = convertObjectsToRanges(state.SelectedHitObjects)
        for _, group in pairs(groups) do
          vibratoSetup(group.startTime, group.endTime, amplitude, increment, stopamplitude, tp_increment, oneSided, preserveNotePositions, useSnap)
        end
      end
    end

    imgui.Text(debug)
    performQueue()

    imgui.End()
end

function convertObjectsToRanges(hitObjects)
  noteTimes = {}
  for _, v in pairs(hitObjects) do
    table.insert(noteTimes, v.startTime)
  end

  groups = {}
  for i=1, #noteTimes - 1 do
    table.insert(groups, {startTime = noteTimes[i], endTime = noteTimes[i + 1]})
  end

  return groups
end

function vibratoSetup(start, stop, amplitude, increment, stopamplitude, tp_increment, oneSided, preserveNotePositions, useSnap)
  --store old positions
  local noteTimes = getNoteTimesDuringPeriod(start, stop)
  local notePositions = {}
  
  if preserveNotePositions then
      for _, time in pairs(noteTimes) do
          table.insert(notePositions, getPositionFromTime(time))
      end
      
      debug = notePositions[1] or "error"
  end
  
  --vibe
  increment = useSnap and 60000 / map.GetTimingPointAt(state.SongTime).Bpm / increment or increment
  vibe(start, stop, amplitude, increment, stopamplitude, tp_increment, oneSided)
  
  --restore positions
  if preserveNotePositions then
      local old_sv_count = #map.ScrollVelocities
      
      performQueue()
      resetQueue()
      resetCache()
  
      --with enough SVs, the game is unable to sort added SVs in time
      --local sorted_svs = correctSVIndexsAtEnd(map.ScrollVelocities, old_sv_count + 1)
      local sorted_svs = table.sort(map.ScrollVelocities, function(a, b) return a.StartTime < b.StartTime end)
      
      local newPositions = {}
      for _, time in pairs(noteTimes) do
          table.insert(newPositions, getPositionFromTime(time, sorted_svs))
      end
      
      debug = debug .. (", " .. (newPositions[1] or "error"))
      
      for i = 1, #noteTimes do
          displace(noteTimes[i], (notePositions[i] - newPositions[i]) / 100, tp_increment, sorted_svs)
      end
  end
end

function sv(time, multiplier) return utils.CreateScrollVelocity(time, multiplier) end

function vibe(start, stop, amplitude, increment, stopamplitude, tp_increment, oneSided)
    local svs = {}
    
    local slope = (stopamplitude - amplitude) / ((stop - start) / increment)
    local target = amplitude
    local displacement = 0
    
    for i = 0, (stop - start - 1) / increment do
        local time = start + i * increment
        
        if oneSided and i % 2 == 1 then
            table.insert(svs, sv(time, (0 - displacement) / tp_increment))
            displacement = 0
        else
            table.insert(svs, sv(time, (target - displacement) / tp_increment))
            displacement = target
        end
        table.insert(svs, sv(time + tp_increment, 0))
        
        target = (target + slope) * -1
        slope = slope * -1
    end
    
    --restore displacement to 0 at end
    target = 0
    table.insert(svs, sv(stop - tp_increment, (target - displacement) / tp_increment))
    table.insert(svs, sv(stop, 0))
    
    mergeSVs(svs)
end

--assumes SVs are added to map in order
--[[function correctSVIndexsAtEnd(svs, origin)
    --identify correct starting index for svs at end of list
    local dest = getScrollVelocityIndexAt(svs[i].StartTime, svs) + 1
    
    local n = #svs - origin + 1
    local original_size = #svs
    local temp = {}
    
    local j = n
    for i = origin, #svs do
        temp[j] = table.remove(svs)
        j = j - 1
    end
    
    for i = #svs, dest, -1 do
        svs[i + n] = svs[i]
    end
    
    for i, v in pairs(temp) do
        svs[dest - 1 + i] = v
    end
end

function reverse(A, start, stop)
    local temp
    local n = math.floor((stop - start + 1) / 2) - 1
    for i = 0, n do
        temp = A[start + i]
        A[start + i] = A[stop - i]
        A[stop - i] = temp
    end
end]]--

function displace(time, displacement, increment, mapsvs)
    local svs = {}
    table.insert(svs, sv(time - increment, displacement / increment))
    table.insert(svs, sv(time, -1 * displacement / increment))
    table.insert(svs, sv(time + increment, 0))
    
    mergeSVs(svs, mapsvs)
end

function resetCache()
    position_cache = {}
end

function getPositionFromTime(time, svs)
    --for some reason, after adding svs to the map,
    --if there are enough svs, the svs will take too long to be sorted by the game
    --and as a result, position would be calculated incorrectly
    --this can be prevented by supplying a custom sorted list of svs
    local svs = svs or map.ScrollVelocities
    
    if #svs == 0 or time < svs[1].StartTime then
        return math.floor(time * 100)
    end
    
    local i = getScrollVelocityIndexAt(time, svs)
    local position = getPositionFromScrollVelocityIndex(i, svs)
    position = position + math.floor((time - svs[i].StartTime) * svs[i].Multiplier * 100)
    return position
end

function getPositionFromScrollVelocityIndex(i, svs)
    if i < 1 then return end
    
    local position = position_cache[i]
    if i == 1 then position = math.floor(svs[1].StartTime * 100) end
    
    if not position then
        svs = svs or map.ScrollVelocities
        position = getPositionFromScrollVelocityIndex(i - 1, svs) + 
                 math.floor((svs[i].StartTime - svs[i - 1].StartTime) * svs[i - 1].Multiplier * 100)
        position_cache[i] = position
    end

    return position
end

function getScrollVelocityIndexAt(time, svs)
    svs = svs or map.ScrollVelocities
    table.insert(svs, sv(1e304, 1))
    
    i = 1
    while svs[i].StartTime <= time do
        i = i + 1
    end
    
    return i - 1
end

function getNoteTimesDuringPeriod(start, stop)
    local times = {}
    local lasttime = -1e304
    
    --should be sorted already
    for _, note in pairs(getNotesDuringPeriod(start, stop)) do
        if note.StartTime > lasttime then
            table.insert(times, note.StartTime)
            lasttime = note.StartTime
        end
    end
    
    return times
end

function getNotesDuringPeriod(start, stop)
    local notes = {}
    
    for _, note in pairs(map.HitObjects) do
        if note.StartTime >= start and note.StartTime <= stop then
            table.insert(notes, note)
        end
    end
    
    return notes
end

function queue(type, arg1, arg2, arg3, arg4)
    arg1 = arg1 or nil
    arg2 = arg2 or nil
    arg3 = arg3 or nil
    arg4 = arg4 or nil

    local action = utils.CreateEditorAction(type, arg1, arg2, arg3, arg4)
    table.insert(action_queue, action)
end

function resetQueue()
    action_queue = {} --list of actions
    add_sv_queue = {} --list of svs
    remove_sv_queue = {} --list of svs
end

function performQueue()
    --create batch actions and add them to queue
    if #remove_sv_queue > 0 then queue(action_type.RemoveScrollVelocityBatch, remove_sv_queue) end
    if #add_sv_queue > 0 then queue(action_type.AddScrollVelocityBatch, add_sv_queue) end
    
    --perform actions in queue
    if #action_queue > 0 then actions.PerformBatch(action_queue) end
end

function mergeSVs(svs, mapsvs)
    local mapsvs = mapsvs or map.ScrollVelocities
    
    --for each sv given, increase map sv if no sv at that time
    for _, sv in pairs(svs) do
        --assumes initial scroll velocity is 1
        local mapsv = getScrollVelocityAt(sv.StartTime) or utils.CreateScrollVelocity(-1e304, 1)
        if mapsv.StartTime ~= sv.StartTime then
            table.insert(add_sv_queue, utils.CreateScrollVelocity(sv.StartTime, mapsv.Multiplier + sv.Multiplier))
        end
    end
    
    --merging starts at first given sv, with map sv's before not changing
    local start = svs[1].StartTime
    
    --merging stops at last sv if last sv has velocity 0, otherwise stops at an sv with time infinity and velocity 0
    local stop
    if svs[#svs].Multiplier == 0 then
        stop = svs[#svs].StartTime
    else
        table.insert(svs, utils.CreateScrollVelocity(1e304, 0))
        stop = 1e304
    end

    local i = 1 --for keeping track of the relevant given sv
    
    --for each map sv within [start, stop), change according to relevant given sv
    for _, mapsv in pairs(mapsvs) do
        if start <= mapsv.StartTime and mapsv.StartTime < stop then
            --make sure current map sv is between relevant given sv and next given sv
            while mapsv.StartTime >= svs[i+1].StartTime do
                i = i + 1
            end
            
            --in extreme cases with a bunch of different svs
            --removing then adding should be more efficient than directly changing
            --https://discord.com/channels/354206121386573824/810908988160999465/815724948256456704
            table.insert(remove_sv_queue, mapsv)
            table.insert(add_sv_queue, utils.CreateScrollVelocity(mapsv.StartTime, mapsv.Multiplier + svs[i].Multiplier))
        end
    end
end

function getScrollVelocityAt(time, svs)
    --by default will use the map's svs
    if not svs or svs == map.ScrollVelocities then return map.GetScrollVelocityAt(time) end
    
    --when custom svs are given
    if #svs == 0 then return nil end
    if time < svs[1].StartTime then return nil end
    
    local i = 1
    while time >= svs[i+1].StartTime do
        i = i + 1
    end
    
    return svs[i]
end