debugger_state = "RUN"
debugger_breakpoints = setmetatable({}, {
    __index = function(t,k)
        t[k] = {enabled=true, temp=false, num_hits=0, cmds={}} -- TODO: implement num_hits, cmds
        return t[k]
    end
})

function ldb()
    local i = debug.getinfo(2) -- I guess 2 is the code we're debugging???

    local brk_key = tostring(i.short_src) .. ":" .. tostring(i.currentline)

    -- Once we're in the debug prompt, that adds 2 to the stack (apparently)
    -- and then this function adds another 1
    function p(lname) 
        -- Search for a local with the given name
        local idx = 1
        while true do
            local name, val = debug.getlocal(5, idx)
            if not name then break end
            if name == lname then
                print(val)
                return val
            end
            idx = idx + 1
        end

        print("No local with name [" .. lname .. "]")
    end

    -- Set breakpoint on current line (if name empty) or set breakpoint
    -- on named function
    function b(name)
        if not name or #name == 0 then
            debugger_breakpoints[brk_key].enabled = true
        else
            print("Not implemented :(")
        end
    end

    function u(lineno)
        local tbrk_key = tostring(i.short_src) .. ":" .. tostring(lineno)
        debugger_breakpoints[tbrk_key].enabled = true
        debugger_breakpoints[tbrk_key].temp = true
        debugger_state = "RUN"
    end

    function c() debugger_state = "RUN" end

    function d() 
        local brk_info = rawget(debugger_breakpoints, brk_key)
        if brk_info then brk_info.enabled=false end
    end

    if debugger_state == "RUN" then
        -- Check if the current line is in the breakpoints table. We do
        -- this as a separate case so that we don't add breakpoints on
        -- every line
        local brk_info = rawget(debugger_breakpoints, brk_key)
        if brk_info then debugger_state = "BREAK" end
    end

    if debugger_state == "BREAK" then
        -- Check if this breakpoint is enabled
        local brk_info = debugger_breakpoints[brk_key]
        if brk_info.enabled then
            debugger_state = "STEP"
            -- Disable temporary breakpoints
            if brk_info.temp then brk_info.enabled = false end
        end
    end

    if debugger_state == "STEP" then
        io.write(
            "SS ", 
            tostring(i.name), 
            "@", brk_key, 
            "\n"
        )
        debug.debug()
    end
end 

function breakpoint()
    debugger_state = "BREAK"
    -- Just a way to skip dropping to the debugger inside the
    -- breakpoint() call
    debug.sethook(
        function () debug.sethook(ldb, "l") end, 
        "l"
    )
end