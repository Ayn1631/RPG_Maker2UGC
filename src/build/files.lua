-- Desktop filesystem boundary. No shell or source-file writes.
return function(deps)
    local diagnostic = deps["contracts.diagnostic"]
    local M, serial = {}, 0

    function M.read(path)
        local handle, reason, code = io.open(path, "rb")
        if not handle then return nil, reason, code end
        local bytes, read_reason, read_code = handle:read("*a")
        handle:close()
        return bytes, read_reason, read_code
    end

    function M.relative(path)
        if type(path) ~= "string" or path == "" or path:find("[%z\r\n:]") then return nil end
        path = path:gsub("\\", "/")
        if path:sub(1, 1) == "/" or path:sub(-1) == "/" then return nil end
        for part in path:gmatch("[^/]+") do
            if part == ".." or part == "." then return nil end
        end
        if path:find("//", 1, true) then return nil end
        return path
    end

    function M.join(root, relative)
        relative = M.relative(relative)
        if not relative then diagnostic.raise("E_PATH", "Expected a contained relative path") end
        return root:gsub("\\", "/"):gsub("/+$", "") .. "/" .. relative
    end

    -- Only descend from an existing output root; never construct a shell command.
    function M.mkdirs(root, relative)
        relative=M.relative(relative)
        if not relative then diagnostic.raise('E_PATH','Expected a contained output directory')end
        local ok,lfs=pcall(require,'lfs')
        if not ok then diagnostic.raise('E_OUTPUT_DIR','Directory creation requires LuaFileSystem')end
        local path=root
        if lfs.attributes(path,'mode')~='directory' then diagnostic.raise('E_OUTPUT_DIR','Output root must exist',{file=path})end
        for part in relative:gmatch('[^/]+')do
            path=path..'/'..part
            local mode=lfs.symlinkattributes(path,'mode')
            if mode and mode~='directory' then diagnostic.raise('E_OUTPUT_DIR','Output component must be a directory, not a file or link',{file=path})end
            if not mode then local made,reason=lfs.mkdir(path);if not made then diagnostic.raise('E_OUTPUT_DIR',tostring(reason),{file=path})end end
        end
        return path
    end

    local function unused_name(path, suffix)
        for _ = 1, 100 do
            serial = serial + 1
            local name = path .. ".r2u-" .. suffix .. "-" .. tostring(os.time()) .. "-" .. serial
            local bytes, _, code = M.read(name)
            if bytes == nil and code == 2 then return name end
        end
        diagnostic.raise("E_OUTPUT_WRITE", "Cannot reserve an output candidate", { file = path })
    end

    -- Stage every file first; on a reported commit failure restore replaced files.
    -- This is not a crash-atomic transaction across several files.
    function M.commit(items, options)
        options = options or {}
        local rename = options.rename or os.rename
        local records, cleanup_notes, destinations = {}, {}, {}
        local function cleanup()
            for _, record in ipairs(records) do
                if record.candidate then os.remove(record.candidate) end
            end
        end
        local function stage()
            for _, item in ipairs(items) do
                if type(item.path) ~= "string" or type(item.bytes) ~= "string" or destinations[item.path] then
                    diagnostic.raise("E_OUTPUT_WRITE", "Invalid or duplicate output item")
                end
                destinations[item.path] = true
                local previous, reason, code = M.read(item.path)
                if previous == nil and code ~= 2 then
                    diagnostic.raise("E_OUTPUT_READ", reason or "Cannot read output", { file = item.path })
                end
                if item.expectMissing and previous~=nil or item.expected~=nil and previous~=item.expected then
                    diagnostic.raise('E_OUTPUT_CHANGED','Output changed since deployment preflight',{file=item.path})
                end
                local record = { path = item.path, previous = previous }
                records[#records + 1] = record
                record.candidate = unused_name(item.path, "candidate")
                local handle, write_reason = io.open(record.candidate, "wb")
                if not handle then
                    diagnostic.raise("E_OUTPUT_DIR_MISSING", "Output directory missing or not writable: " .. tostring(write_reason), { file = item.path })
                end
                local written, write_error = handle:write(item.bytes)
                local closed, close_error = handle:close()
                if not written or not closed then
                    diagnostic.raise("E_OUTPUT_WRITE", tostring(write_error or close_error), { file = item.path })
                end
                local roundtrip = M.read(record.candidate)
                if roundtrip ~= item.bytes then
                    diagnostic.raise("E_OUTPUT_WRITE", "Candidate verification failed", { file = item.path })
                end
            end
            -- Refuse observed concurrent edits before beginning replacement.
            for _, record in ipairs(records) do
                local current, reason, code = M.read(record.path)
                if (current == nil and code ~= 2) or current ~= record.previous then
                    diagnostic.raise("E_OUTPUT_CHANGED", reason or "Output changed during build", { file = record.path })
                end
            end
        end
        local ok, err = pcall(stage)
        if not ok then cleanup(); error(err, 0) end

        local function rollback()
            local errors = {}
            for index = #records, 1, -1 do
                local record = records[index]
                if record.installed then
                    local removed, reason = os.remove(record.path)
                    if not removed then errors[#errors + 1] = record.path .. ": " .. tostring(reason) end
                end
                if record.backup then
                    local restored, reason = rename(record.backup, record.path)
                    if not restored then errors[#errors + 1] = record.backup .. ": " .. tostring(reason) end
                end
            end
            cleanup()
            return errors
        end
        ok, err = pcall(function()
            for _, record in ipairs(records) do
                if record.previous ~= nil then
                    local backup = unused_name(record.path, "backup")
                    local moved, reason = rename(record.path, backup)
                    if not moved then diagnostic.raise("E_OUTPUT_COMMIT", tostring(reason), { file = record.path }) end
                    record.backup = backup
                end
                local moved, reason = rename(record.candidate, record.path)
                if not moved then diagnostic.raise("E_OUTPUT_COMMIT", tostring(reason), { file = record.path }) end
                record.candidate, record.installed = nil, true
            end
        end)
        if not ok then
            local rollback_errors = rollback()
            if #rollback_errors > 0 then
                diagnostic.raise("E_OUTPUT_ROLLBACK", "Replacement failed; recovery files retained: " .. table.concat(rollback_errors, "; "))
            end
            error(err, 0)
        end
        for _, record in ipairs(records) do
            if record.backup then
                local removed, reason = os.remove(record.backup)
                if not removed then cleanup_notes[#cleanup_notes + 1] = record.backup .. ": " .. tostring(reason) end
            end
        end
        return cleanup_notes
    end

    return M
end
