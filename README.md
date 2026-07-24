# What is pdh?
Performance Data Helper is a Windows API for collecting performance counter data.

## Example
```Lua
local pdh = require "pdh"

local query   = pdh:open_query()
local counter = query:add_counter("\\Processor(_Total)\\% Processor Time")

local timer = 0

local function on_render()
    if (common.get_unixtime() - timer) < 1 then
        return
    end

    query:collect()

    local cpu_load = counter:as_double()
    if cpu_load then
        print(
            "CPU Load: ", math.floor(cpu_load + 0.5), "%"
        )
    end

    timer = common.get_unixtime()
end

local function on_shutdown()
    query:close()
end

events.shutdown(on_shutdown)
events.render(on_render)
```
