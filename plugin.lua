debug = "hi"

function draw()
    imgui.Begin("Vibrato")
    resetQueue()

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

    if imgui.Button("Current") then start = state.SongTime end imgui.SameLine()
    _, start = imgui.InputFloat("Start", start, 1)
    if imgui.Button("Current##1") then stop = state.SongTime end imgui.SameLine()
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

    if imgui.Button("vibe") then
        --store old positions
        local noteTimes = getNoteTimesDuringPeriod(start, stop)
        local notePositions = {}
        if preserveNotePositions then
            for _, time in pairs(noteTimes) do
                table.insert(notePositions, getPositionFromTime(time))
            end
        end
        
        --vibe
        if useSnap then
            vibe(start, stop, amplitude, 60000 / map.GetTimingPointAt(state.SongTime).Bpm / increment, stopamplitude, tp_increment, oneSided)
        else
            vibe(start, stop, amplitude, increment, stopamplitude, tp_increment, oneSided)
        end
        
        performQueue()
        resetQueue()
        
        --restore positions
        if preserveNotePositions then
            local newPositions = {}
            for _, time in pairs(noteTimes) do
                table.insert(newPositions, getPositionFromTime(time))
            end
            
            for i = 1, #noteTimes do
                displace(noteTimes[i], (notePositions[i] - newPositions[i]) / 100, tp_increment)
            end
        end
    end

    imgui.Text(debug)
    performQueue()

    imgui.End()
end

function vibe(start, stop, amplitude, increment, stopamplitude, tp_increment, oneSided)
    local slope = (stopamplitude - amplitude) / ((stop - start) / increment)
    local target = amplitude
    local displacement = 0

    for i = 0, (stop - start) / increment - 1 do
        local time = start + i * increment
        
        if oneSided and i % 2 == 1 then
            increaseSV(time, (0 - displacement) / tp_increment)
            displacement = 0
        else
            increaseSV(time, (target - displacement) / tp_increment)
            displacement = target
        end
        increaseSV(time + tp_increment, 0)

        target = (target + slope) * -1
        slope = slope * -1
    end
    
    --restore displacement to 0 at end
    time = stop - increment
    target = 0
    increaseSV(time - tp_increment, (target - displacement) / tp_increment)
    increaseSV(time, 0)
    
    debug = target
end

function displace(time, displacement, increment)
    increaseSV(time - increment, displacement / increment)
    increaseSV(time, -1 * displacement / increment)
    increaseSV(time + increment, 0)
end

--can be optimized by caching positions for multiple uses in one frame
function getPositionFromTime(time)
    local svs = map.ScrollVelocities

    if #svs == 0 or time < svs[1].StartTime then
        return math.floor(time * 100)
    end

    local position = math.floor(svs[1].StartTime * 100)

    local i = 2

    while i <= #svs do
        if time < svs[i].StartTime then
            break
        else
            position = position + math.floor((svs[i].StartTime - svs[i - 1].StartTime) * svs[i - 1].Multiplier * 100)
        end

        i = i + 1
    end

    i = i - 1

    position = position + math.floor((time - svs[i].StartTime) * svs[i].Multiplier * 100)
    return position
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
    action_queue = {}
    add_sv_queue = {}
end

function performQueue()
    if #add_sv_queue > 0 then queue(action_type.AddScrollVelocityBatch, add_sv_queue) end
    if #action_queue > 0 then actions.PerformBatch(action_queue) end
end

function increaseSV(time, multiplier)
    --assuming initial sv multiplier is 1
    local sv = map.GetScrollVelocityAt(time) or utils.CreateScrollVelocity(-1e309, 1)

    if sv.StartTime == time then
        queue(action_type.ChangeScrollVelocityMultiplierBatch, {sv}, sv.Multiplier + multiplier)
    else
        local newsv = utils.CreateScrollVelocity(time, sv.Multiplier + multiplier)
        table.insert(add_sv_queue, newsv)
    end
end