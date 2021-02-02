debug = "hi"

function draw()
    imgui.Begin("Vibrato")
    resetQueue()

    state.IsWindowHovered = imgui.IsWindowHovered()

    local start = state.GetValue("start") or 0
    local stop = state.GetValue("stop") or 0
    local amplitude = state.GetValue("amplitude") or 1
    local stopamplitude = state.GetValue("stopamplitude") or 0
    local increment = state.GetValue("increment") or 10

    local useSnap = state.GetValue("useSnap") or false

    if imgui.Button("Current") then start = state.SongTime end imgui.SameLine()
    _, start = imgui.InputFloat("Start", start, 1)
    if imgui.Button("Current##1") then stop = state.SongTime end imgui.SameLine()
    _, stop = imgui.InputFloat("Stop", stop, 1)
    _, amplitude = imgui.InputFloat("Amplitude", amplitude, 1)
    _, stopamplitude = imgui.InputFloat("stopamplitude", stopamplitude, 1)
    _, increment = imgui.InputFloat("Increment", increment, 1)

    _, useSnap = imgui.Checkbox("Treat increment as 1/n beat snap", useSnap)

    state.SetValue("start", start)
    state.SetValue("stop", stop)
    state.SetValue("amplitude", amplitude)
    state.SetValue("stopamplitude", stopamplitude)
    state.SetValue("increment", increment)

    state.SetValue("useSnap", useSnap)

    if imgui.Button("vibe") then
        if useSnap then
            vibe(start, stop, amplitude, 60000 / map.GetTimingPointAt(state.SongTime).Bpm / increment, stopamplitude)
        else
            vibe(start, stop, amplitude, increment, stopamplitude)
        end
    end

    imgui.Text(debug)

    performQueue()
    imgui.End()
end

function vibe(start, stop, amplitude, increment, stopamplitude)
    local time = start
    local direction = 1
    local slope = (stopamplitude - amplitude) / ((stop - start) / increment / 2)

    while time < stop do
        increaseSV(time, amplitude * direction)
        time = time + increment
        direction = direction * -1
        amplitude = direction == 1 and amplitude or amplitude + slope
    end
    increaseSV(stop, 0)
    debug = amplitude
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