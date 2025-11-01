local helpers = require('scripts/ezlibs-scripts/helpers')
local json    = require("scripts/libs/json")
-- Debug toggle
local DEBUG   = true

Level         = {
    warning = { level_name = "Warning" },
    lowError = { level_name = "Low" },
    mediumError = { level_name = "Medium" },
    criticalError = { level_name = "Critical" },
    information = { level_name = "Information" }
}

function DBGLogger(lib_name, level, message)
    return async(function()
        if DEBUG then
            print(lib_name)
            await(Async.write_file("scripts/debug-logger/logs/" .. lib_name .. ".txt",
                json.encode({ level.level_name, message })))
        end
    end)
end
