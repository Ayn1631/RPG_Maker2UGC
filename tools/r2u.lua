local script_path = (arg and arg[0] or "tools/r2u.lua"):gsub("\\", "/")
local root = (script_path:match("^(.*[/])") or "") .. "../"
local load_module = assert(loadfile(root .. "tools/bootstrap.lua"))()(root)
local cli = load_module("cli")
local arguments, as_json = {}, false
for index = 1, #arg do
    arguments[index] = arg[index]
    if arg[index] == "--json" then as_json = true end
end
local report, exit_code = cli.run(arguments, root)
if as_json then
    print(load_module("contracts.json").encode(report))
elseif report.command == "help" then
    print("R2U " .. cli.version .. " - Lua 5.3 tools")
    print("Init: lua tools/r2u.lua init --source <RPG Maker directory> --game-id <name> [--bindings <existing-project.lua>] [--profile <profile>]")
    print("Usage: lua tools/r2u.lua inspect|build|deploy|verify|release-check|export-tiles|export-characters|export-primitives --project projects/<game>/project.lua [--json]")
    print("Build/inspect/deploy: --tile-bindings <completed-manifest.json> embeds template bindings offline")
    print("Build/inspect/deploy: --character-bindings <completed-manifest.json> embeds twelve-direction-frame bindings offline")
    print("Art: export-primitives --project <project.lua> creates an editable primitiveArt.path Lua library; build embeds referenced assets only")
    print("Verify: --suite <name> [--case <substring>] and/or --trace <trace-pair.json>; no implicit full suite")
    print("Release-check: --target simulator|ugc --evidence <release-evidence.json>; never publishes")
    print("Deploy: --target <existing-directory>/levelScript.lua builds once, backs up, then updates a managed entry")
    print("UGC loading and publishing are separate from building or copying the single Lua file.")
else
    print((report.ok and "OK " or "FAILED ") .. (report.command or "command")
        .. " [" .. report.stage .. "; playable="..tostring(report.playable==true).."; publishable="..tostring(report.publishable==true).."]")
    if report.output then print("Output: " .. report.output) end
    if report.setup then print("Setup: "..report.setup);print("Detected: "..report.engineProfile.." / "..report.sourceVersion)end
    if report.buildId then print("Build: " .. report.buildId) end
    if report.gates then for _,gate in ipairs(report.gates)do print("Gate "..gate.id..": "..gate.status..(gate.reason and " - "..gate.reason or ""))end end
    if report.tests then print("Selected checks: "..report.tests.passed.." passed, "..report.tests.failed.." failed")end
    if report.traceComparison then print("Provided trace comparison: "..report.traceComparison.status)end
    if report.deployment then
        print("Deployed: "..report.deployment.target)
        print("UGC load: "..report.deployment.loaded.."; published=false")
        if report.deployment.backup then print("Previous Lua: "..report.deployment.backup)end
    end
    if report.tileCount then print('Tiles: '..report.tileCount..'; PNGs: '..report.imageCount)end
    if report.characterCount then print('Characters: '..report.characterCount..'; PNGs: '..report.imageCount)end
    for _,path in ipairs(report.unavailableSources or {})do print('Artwork source absent; existing rendering retained: '..path)end
    for _, item in ipairs(report.diagnostics or {}) do
        print(item.code .. " " .. (item.file or "") .. " " .. (item.jsonPath or "") .. ": " .. item.reason)
    end
    for _, note in ipairs(report.cleanupNotes or {}) do print("Backup retained: " .. note) end
end
if exit_code ~= 0 then os.exit(exit_code) end
