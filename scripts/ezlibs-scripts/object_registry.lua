local ezcache = require('scripts/ezlibs-scripts/ezcache')

local object_registry = {
    handlers = {},          -- type -> list of callbacks
    types_to_cache = {},    -- set of types that have handlers
}

function object_registry.register_handler(object_type, callback)
    if not object_registry.handlers[object_type] then
        object_registry.handlers[object_type] = {}
        object_registry.types_to_cache[object_type] = true
        -- Inform ezcache that this type should be cacheable
        ezcache.add_cacheable_type(object_type)
    end
    table.insert(object_registry.handlers[object_type], callback)
end

function object_registry.load_all()
    print("[object_registry] Starting preload...")
    local start_time = os.clock()

    local areas = Net.list_areas()
    for _, area_id in ipairs(areas) do
        local objects = Net.list_objects(area_id)
        for _, object_id in ipairs(objects) do
            local object = Net.get_object_by_id(area_id, object_id)
            if object and object.type and object_registry.types_to_cache[object.type] then
                -- Cache the object (removes from Net)
                local cached = ezcache.cache_object(area_id, object)
                if cached then
                    -- Invoke all handlers for this type
                    local handlers = object_registry.handlers[object.type]
                    if handlers then
                        for _, callback in ipairs(handlers) do
                            callback(area_id, cached)
                        end
                    end
                end
            end
        end
    end

    local elapsed = os.clock() - start_time
    print("[object_registry] Preload completed in " .. elapsed .. "s")
end

return object_registry