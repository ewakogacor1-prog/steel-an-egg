--[[    Steal An Egg — Auto Steal v4.39 (straight flight)
    =========================================
    • Mode GAME SPEED atau CFrame step 100–1000 stud/s (eksperimental)
    • Preset CFrame: pulang/berangkat lurus ala Dice — diagonal tunggal ke
      kolom pintu, tidak sidestep dulu lalu belok di tengah koridor
    • CFrame step mengikuti waypoint; konfirmasi delivery tetap berdasarkan event game
    • Worker bisa dimulai ulang setelah error; respawn menunggu rig + snapshot baru
    • Koreksi posisi besar mematikan boost sampai pengguna memilih ulang
    • Cek tabrakan proposional: kotak tipis + horizon pendek, tidak nge-freeze
      di dinding guard (navmesh game mengabaikannya tapi solid untuk pemain)
    • Pulang tidak lagi stop-and-replan tiap senggolan; leg rute pulang panjang
    • Titik rute belok kecil digabung → jalan lurus di tengah jalan, bukan zig-zag
    • Tembok satu sisi → bidik dikunci paralel tetap 8 stud dari tembok, tak serong
    • Titik rute di belakang posisi langsung dilewati → tidak balik badan saat nabrak
    • Telur lepas jauh dari base → batal pulang & dijeda (bukan langsung balik arah)
    • UI: WindUI (Footagesus); kalau gagal di-fetch, panel bawaan tetap dipakai
    • Steal HANYA saat dekat (<= 7 stud), UID tersedia, gerbang terbuka
    • 1 request carry per attempt, hasil server + UID diperiksa (anti-spam)
    • Filter kelangkaan (multi-select) + deteksi otomatis
    • Tetap ON saat gagal; cooldown dan retry otomatis sampai OFF manual

    [ CARA DETEKSI RARITY ]
    1. UID snapshot -> AssetCategory -> katalog 227 config game (termasuk turunan).
    2. Highlight/signature hanya fallback tampilan tanpa kategori snapshot.
    3. Pickup wajib lolos pemeriksaan ulang kategori + filter dari snapshot terbaru.

    [ CATATAN PENTING ]
    • Kalau karakter ke-anchor (AFK Treadmill), gerak manual dulu (WASD) —
      script ini sengaja TIDAK menyentuh Anchored.
    • Base otomatis dari data kepemilikan Homestead (UserId), bukan posisi saat start.
    • Klaim otomatis hanya dikonfirmasi melalui feedback game, bukan telur yang hilang.
    • Tidak ada jaminan bebas deteksi/ban.
]]

-- Fixed, low-volume startup breadcrumbs survive in Roblox's player log.
-- A native crash cannot be caught by pcall; no retries/re-execution here.
warn("[ASE-BOOT 4.35] 01 entry")

--==============================================================
-- CONFIG
--==============================================================
local CONFIG = {
    activationDistance  = 7,        -- jarak ambil, tetap dibatasi MaxActivationDistance game
    moveInterval        = 0.025,    -- belok/cek waypoint lebih sering
    arriveTimeout       = 18,       -- detik sebelum telur di-skip (nyangkut)
    stuckSeconds        = 3.5,      -- dianggap nyangkut kalau posisi tak berubah
    retryCooldown       = 0.5,      -- jeda hanya setelah percobaan gagal
    carryConfirmTimeout = 2.5,      -- tunggu event carry game (biasanya <0.5s)
    claimConfirmTimeout = 7,        -- tunggu verdict klaim setelah sampai base
    returnTimeout       = 45,       -- lari pulang; lewat ini dianggap gagal
    pathHorizon         = 180,      -- pathfinding lokal, bukan lintas map sekaligus
    returnPathHorizon   = 420,      -- pulang: leg lebih panjang → rekomputasi rute jauh lebih jarang
    dropAbortDistance   = 140,      -- telur lepas >ini dari base → batal pulang, lanjut hunting (jangan bolak-balik kosong)
    backskipRadius      = 25,       -- jarak maks titik rute mundur yang boleh dilewati, bukan dikejar
    simplifyTolerance   = 5,        -- titik rute belok <ini digabung → jalan lurus di tengah jalan
    centerProbe         = 22,       -- jarak ray kanan/kiri untuk mendeteksi koridor (jalan lebar ikut terdeteksi)
    centerGain          = 0.5,      -- setengah selisih dikoreksi per tick: tarik cepat ke tengah
    centerDeadZone      = 0.6,      -- di bawah ini tidak digeser sama sekali
    centerKeep          = 10,       -- jarak lintang minimal dari dinding (badan ~4 lebar)
    centerMaxShift      = 16,       -- geseran bidikan maksimum per tick
    routeCheckInterval  = 0.15,
    obstacleAhead       = 40,       -- horizon cek tabrakan (dulu 84.8 → false-block terus)
    obstacleBox         = 2.4,      -- lebar kotak cek (dulu 3.5 → kena dinding lorong sempit)
    blockTimeout        = 2,        -- terhalang terus selebihnya dari ini → skip, bukan loop selamanya
    anchorGrace         = 15,       -- waktu tunggu kalau game mengunci gerakan (run-back wake), bukan langsung OFF
    carryEscapeDistance = 60,       -- gerak arah pulang dulu; bukan klaim radius aman guard
    avoidTreadmills     = true,
    autoTreadmillExit   = true,     -- input Space normal, hanya pada treadmill yang terkonfirmasi
    treadmillPadding   = 3,
    treadmillCornerGap = 16,       -- toleransi belok/arrival di boost, di luar footprint
    navigationTurnSpeed = 0,        -- 0 = jangan rem ke 48; pakai kecepatan yang aktif
    directFlight        = true,     -- lurus ala Dice: diagonal tunggal, tanpa pathfinding (aktif saat preset CFrame)
    maxTriesPerEgg      = 2,        -- percobaan per telur sebelum di-blacklist
    eggBlacklistSeconds = 120,      -- durasi blacklist telur gagal
    stopAfterFails      = 6,        -- jumlah gagal sebelum cooldown; tidak mematikan Auto Steal
    preferHighestRarity = false,    -- default: telur cocok terdekat, bukan lintas map
    pickupMode          = "server", -- API EggState yang terverifikasi; "prompt" untuk jalur lama
    useRealInput        = false,    -- opsional input E; bukan jaminan tidak terdeteksi
    toggleKey           = Enum.KeyCode.RightShift,
    refreshBaseKey      = Enum.KeyCode.B,
    autoStart           = false,
    debugEnabled        = true,
    debugEcho           = false,    -- ring buffer tetap aktif, jangan banjiri console tiap gerak
    debugLogLimit       = 200,
}

--==============================================================
-- DATA RARITY (dari game)
--==============================================================
local TIERS = {
    ["Common"]       = { 1,  Color3.fromRGB(151, 151, 151) },
    ["Uncommon"]     = { 2,  Color3.fromRGB(0, 255, 0) },
    ["SuperRare"]    = { 2,  Color3.fromRGB(25, 216, 250) },
    ["Rare"]         = { 3,  Color3.fromRGB(25, 144, 255) },
    ["Epic"]         = { 4,  Color3.fromRGB(196, 2, 255) },
    ["Legendary"]    = { 5,  Color3.fromRGB(254, 132, 36) },
    ["Mythic"]       = { 6,  Color3.fromRGB(254, 44, 102) },
    ["Rainbow"]      = { 6,  Color3.fromRGB(240, 35, 172) },
    ["BrainrotGod"]  = { 6,  Color3.fromRGB(172, 0, 198) },
    ["Cosmic"]       = { 7,  Color3.fromRGB(65, 0, 170) },
    ["Secret"]       = { 8,  Color3.fromRGB(46, 46, 46) },
    ["Eternal"]      = { 9,  Color3.fromRGB(255, 30, 240) },
    ["Limited"]      = { 9,  Color3.fromRGB(174, 80, 254) },
    ["Divine"]       = { 10, Color3.fromRGB(251, 255, 0) },
    ["Transcendent"] = { 10, Color3.fromRGB(196, 254, 254) },
    ["Titan"]        = { 11, Color3.fromRGB(255, 64, 64) },
    ["LightDark"]    = { 12, Color3.fromRGB(196, 148, 255) },
    ["Unknown"]      = { 99, Color3.fromRGB(130, 132, 140) },
}
local TIER_ORDER = { "Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret",
                     "Eternal","Divine","Limited","Transcendent","Titan","Rainbow","BrainrotGod",
                     "SuperRare","LightDark","Unknown" }

-- Verified 2026-10-17 via MCP: 227 Data.Assets.Configs, place version 687.
-- Includes template overrides and inheritance: Aetheron -> ArchAngel, Equinox -> Pegasus.
local CATEGORY_RARITY = {
    ["67"] = "Secret",
    ["67 OP"] = "Secret",
    ["Abyssal Overlord"] = "Secret",
    ["Abyssal Overlord OP"] = "Secret",
    ["Aetheron"] = "Divine",
    ["Alabaster Whale"] = "Cosmic",
    ["Alien Skeleton Boss"] = "Secret",
    ["Amethyst Runebear"] = "Secret",
    ["Amethyst Runebear OP"] = "Secret",
    ["Ankylosaurus"] = "Mythic",
    ["ArchAngel"] = "Divine",
    ["Archdemon Dragon"] = "Divine",
    ["Ascended Vermilion Phoenix"] = "Eternal",
    ["Ash Gecko"] = "Rare",
    ["Baby Aurora Dragon"] = "Legendary",
    ["Balrog"] = "Eternal",
    ["Bananita Dolphinita"] = "Epic",
    ["Banjo Firefly"] = "Secret",
    ["Basilisk"] = "Cosmic",
    ["Bear"] = "Epic",
    ["Belula Beluga"] = "Mythic",
    ["Blade Head"] = "Mythic",
    ["Bomboclat Crocolat"] = "Secret",
    ["Bronto"] = "Cosmic",
    ["Brr Brr Patapim"] = "Legendary",
    ["Burrowing Owl"] = "Rare",
    ["Camel"] = "Rare",
    ["Catfish"] = "Uncommon",
    ["Cave Dragon"] = "Secret",
    ["Centapede"] = "Epic",
    ["Centaur"] = "Secret",
    ["Cerberus"] = "Secret",
    ["Chicken"] = "Common",
    ["Chillin Chilli"] = "Mythic",
    ["Chimpanzee"] = "Rare",
    ["Citadel Snail"] = "Mythic",
    ["Colossal Mammoth"] = "Cosmic",
    ["Cosmic Beetle Blue"] = "Mythic",
    ["Cosmic Fox"] = "Secret",
    ["Cosmic Lion"] = "Eternal",
    ["Crab"] = "Legendary",
    ["Crane"] = "Epic",
    ["Crawler"] = "Cosmic",
    ["Crocodile"] = "Epic",
    ["Crocodon"] = "Secret",
    ["Cthulhu"] = "Divine",
    ["Cyclops Gorilla"] = "Mythic",
    ["Dark Gargoyle"] = "Secret",
    ["DeathstalkerScorpion"] = "Mythic",
    ["Demon Hound"] = "Cosmic",
    ["Demon Imp"] = "Cosmic",
    ["Depths Cthulhu"] = "Divine",
    ["Depths Electric Eel"] = "Eternal",
    ["Depths Manta Ray"] = "Secret",
    ["Depths Megalodon"] = "Secret",
    ["Depths Riptide Octopus"] = "Cosmic",
    ["Depths Spike"] = "Secret",
    ["Depths Terra Snapper"] = "Eternal",
    ["DesertLark"] = "Uncommon",
    ["Dodo"] = "Rare",
    ["Dog"] = "Common",
    ["Dove"] = "Legendary",
    ["Dragon"] = "Eternal",
    ["Dreadclaw"] = "Cosmic",
    ["Dreadscale"] = "Divine",
    ["Dreadstinger"] = "Eternal",
    ["Dream Axolotl"] = "Legendary",
    ["Drill Monster"] = "Cosmic",
    ["Duckling"] = "Common",
    ["Dunkleosteus"] = "Secret",
    ["El Maja"] = "Eternal",
    ["Electric Eel"] = "Secret",
    ["Ember Dragon"] = "Secret",
    ["Enchanted Bluejay"] = "Mythic",
    ["Engine Snail"] = "Eternal",
    ["Equinox"] = "Eternal",
    ["Eternal Lunar Dragon"] = "Eternal",
    ["Eye Bat"] = "Legendary",
    ["Eyeball Crab"] = "Secret",
    ["FennecFox"] = "Uncommon",
    ["Finned Thresher"] = "Legendary",
    ["Flame Sprite"] = "Legendary",
    ["Flaming Bull"] = "Legendary",
    ["Frog"] = "Common",
    ["Frogfly"] = "Mythic",
    ["Froggo"] = "Mythic",
    ["Galaxy Gecko"] = "Legendary",
    ["Gigantopithecus"] = "Eternal",
    ["Glyptodon"] = "Legendary",
    ["Godzilla"] = "Divine",
    ["Gorilla"] = "Legendary",
    ["Hazardhog"] = "Eternal",
    ["Hellhound"] = "Cosmic",
    ["Ice Dragon"] = "Eternal",
    ["Imp"] = "Cosmic",
    ["Irihorus"] = "Cosmic",
    ["Jellyfish"] = "Secret",
    ["Jerboa"] = "Common",
    ["Kaiju Spider"] = "Legendary",
    ["King Kong"] = "Eternal",
    ["Kitsune"] = "Divine",
    ["Koi"] = "Cosmic",
    ["Kraken"] = "Secret",
    ["Krakenoid"] = "Eternal",
    ["La Vacca Saturno Saturnita"] = "Cosmic",
    ["Lamb"] = "Mythic",
    ["Lava frog"] = "Epic",
    ["Lava Iguana"] = "Legendary",
    ["LimitedTimeExperimentPet"] = "Secret",
    ["Mammoth"] = "Mythic",
    ["Mangolini Parrochini"] = "Cosmic",
    ["Manta Ray"] = "Mythic",
    ["Mantis"] = "Cosmic",
    ["Mawbreaker"] = "Secret",
    ["Mecha Chompa"] = "Secret",
    ["Mecha Crawler"] = "Secret",
    ["Mecha Crocodon"] = "Eternal",
    ["Mecha Dreadscale"] = "Divine",
    ["Mecha Froggo"] = "Secret",
    ["Mecha Krakenoid"] = "Eternal",
    ["Mecha Scorpio"] = "Secret",
    ["Mecha Scrambler"] = "Divine",
    ["Megalodon"] = "Cosmic",
    ["Megatherium"] = "Cosmic",
    ["Mire Fox"] = "Epic",
    ["Mosasaurus"] = "Eternal",
    ["Moth"] = "Cosmic",
    ["Nibbles #013"] = "Cosmic",
    ["Nuceodille"] = "Secret",
    ["Nuclear Mantis"] = "Eternal",
    ["Octophant"] = "Divine",
    ["Oni Tiger"] = "Eternal",
    ["Orangutini Ananassini"] = "Legendary",
    ["Orca"] = "Mythic",
    ["Ostrich"] = "Secret",
    ["Ostrich OP"] = "Secret",
    ["Parrotfish"] = "Rare",
    ["Peacock"] = "Cosmic",
    ["Pegasus"] = "Eternal",
    ["Penguin"] = "Rare",
    ["Pink Dragon Experiment"] = "Eternal",
    ["Polar Bear"] = "Legendary",
    ["Prism Gecko"] = "Legendary",
    ["Pterodactyl"] = "Legendary",
    ["Raccoon"] = "Rare",
    ["Race Bird"] = "Cosmic",
    ["Race Cheetah"] = "Secret",
    ["Race Lizard"] = "Mythic",
    ["Race Seahorse"] = "Legendary",
    ["Radcoon"] = "Cosmic",
    ["Rattlesnake"] = "Legendary",
    ["RazorFang"] = "Secret",
    ["Red Panda"] = "Mythic",
    ["Rhino"] = "Cosmic",
    ["Rhinobear"] = "Eternal",
    ["Rift Eye"] = "Legendary",
    ["Riftwing"] = "Mythic",
    ["Ring Guard"] = "Cosmic",
    ["Ringlord"] = "Secret",
    ["Riptide Octopus"] = "Cosmic",
    ["Royal Skywhale"] = "Divine",
    ["Sabertooth"] = "Divine",
    ["Sabertooth Tiger"] = "Mythic",
    ["Salamander"] = "Legendary",
    ["Sand Spider"] = "Mythic",
    ["ScorchedDragon"] = "Secret",
    ["Scorpio"] = "Legendary",
    ["Shadow Dragon"] = "Mythic",
    ["Shardling"] = "Mythic",
    ["Shardwing"] = "Secret",
    ["Shark"] = "Secret",
    ["Sharkodile"] = "Secret",
    ["Shattered Colossus"] = "Divine",
    ["Shattered Drake"] = "Eternal",
    ["Shattered Ram"] = "Cosmic",
    ["Skeletal Dunkleosteus"] = "Eternal",
    ["Skeletal Gigantopithecus"] = "Eternal",
    ["Skeletal Glyptodon"] = "Secret",
    ["Skeletal Megatherium"] = "Secret",
    ["Skeletal Sabertooth"] = "Divine",
    ["Skeletal Terrorbird"] = "Secret",
    ["Skeleton Horse"] = "Eternal",
    ["Snowy Owl"] = "Cosmic",
    ["Spider"] = "Mythic",
    ["Spiderpig"] = "Cosmic",
    ["Spike"] = "Legendary",
    ["Spirit Hare"] = "Cosmic",
    ["Spirit Panda"] = "Cosmic",
    ["Stacked Turtle"] = "Cosmic",
    ["Stag"] = "Secret",
    ["Strawberry Elephant"] = "Eternal",
    ["Swan"] = "Epic",
    ["Swordfish"] = "Epic",
    ["Terra Snapper"] = "Eternal",
    ["Terrorbird"] = "Mythic",
    ["Three Headed Chicken"] = "Cosmic",
    ["Tiger"] = "Mythic",
    ["Tob Tobi Tob Tob"] = "Epic",
    ["Toro"] = "Mythic",
    ["Toucan"] = "Rare",
    ["Toucax"] = "Cosmic",
    ["Toxic Crocodile"] = "Secret",
    ["Toxic Hedgehog"] = "Secret",
    ["Toxic Hedgehog OP"] = "Secret",
    ["Toxic Rat"] = "Mythic",
    ["Tralaledon"] = "Secret",
    ["Triceratops"] = "Cosmic",
    ["Trulimero Trulicina"] = "Epic",
    ["Tung Tung Sahur"] = "Rare",
    ["Turtle"] = "Rare",
    ["TyrannosaurusRex"] = "Secret",
    ["Uncoiled Armadillo"] = "Cosmic",
    ["Unicorn"] = "Divine",
    ["Ventinal"] = "Cosmic",
    ["Void Angler"] = "Legendary",
    ["Void Dragon"] = "Eternal",
    ["Void Serpent"] = "Eternal",
    ["Voidmaw"] = "Mythic",
    ["Walrus"] = "Epic",
    ["Warden"] = "Secret",
    ["Wendigo"] = "Secret",
    ["Whale Shark"] = "Cosmic",
    ["Wheel Hamster"] = "Mythic",
    ["World Burner"] = "Divine",
    ["World Eater"] = "Eternal",
    ["World Spirit"] = "Divine",
    ["Yeti"] = "Secret",
}

--==============================================================
-- SERVICES
--==============================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")

-- Bounded structured log, retained locally and readable through DebugLogs:Invoke.
-- Never logs arbitrary remote traffic, hooks functions, or sends telemetry.
local debugSession = HttpService:GenerateGUID(false):sub(1, 8)
local debugStarted = os.clock()
local debugRecords, debugThrottle = {}, {}
local debugSequence = 0
local function clean(value, depth)
    depth = depth or 0
    local kind = typeof(value)
    if kind == "nil" then return "nil" end
    if kind == "string" then return value:sub(1, 6000) end
    if kind == "boolean" then return value end
    if kind == "number" then
        if value ~= value or math.abs(value) == math.huge then return tostring(value) end
        return value
    end
    if kind == "Vector3" then
        return {x = math.round(value.X * 100) / 100, y = math.round(value.Y * 100) / 100, z = math.round(value.Z * 100) / 100}
    end
    if kind == "Instance" then return value:GetFullName() end
    if kind == "table" then
        if depth >= 4 then return "[depth limit]" end
        local result, count = {}, 0
        for key, entry in pairs(value) do
            count += 1
            if count > 40 then result._truncated = true; break end
            result[tostring(key)] = clean(entry, depth + 1)
        end
        return result
    end
    return tostring(value)
end
local function debugLog(event, fields, level, interval, silent)
    if not CONFIG.debugEnabled then return end
    local now = os.clock()
    local throttle = debugThrottle[event]
    if interval and throttle and now - throttle.last < interval then
        throttle.suppressed += 1
        return
    end
    debugSequence += 1
    local record = {
        seq = debugSequence, session = debugSession, time = os.time(),
        serverTime = Workspace:GetServerTimeNow(),
        elapsed = math.round((now - debugStarted) * 1000) / 1000,
        event = event, level = level or "INFO", fields = clean(fields or {}),
        suppressed = throttle and throttle.suppressed or 0,
    }
    debugThrottle[event] = {last = now, suppressed = 0}
    table.insert(debugRecords, record)
    if #debugRecords > CONFIG.debugLogLimit then table.remove(debugRecords, 1) end
    if not silent and CONFIG.debugEcho then
        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, record)
        local message = "[AutoStealDebug] " .. (ok and encoded or (event .. " (encode failed)"))
        if level == "ERROR" then warn(message) else print(message) end
    end
end

-- LOG KE FILE (folder workspace executor): ringkas 1 baris/record, max 150
-- record + potong 60KB → file tidak bengkak. Dipakai lewat tombol
-- "Simpan Log" dan otomatis saat UI dihancurkan (reload/execute ulang).
local function compactValue(v)
    local kind = typeof(v)
    if kind == "number" then return tostring(math.round(v * 100) / 100) end
    if kind == "string" then
        local s = v:gsub("%s+", "_"):sub(1, 40)
        return s == "" and nil or s
    end
    if kind == "boolean" then return v and "1" or "0" end
    if kind == "table" then
        if type(v.x) == "number" and type(v.z) == "number" then
            return tostring(math.round(v.x)) .. "," .. tostring(math.round(v.z))
        end
        return nil
    end
    return nil
end
local function buildLogText()
    if not CONFIG.debugEnabled then return nil, "debug mati" end
    local lines = {"# AutoSteal " .. debugSession .. " " .. os.date("%H:%M:%S")}
    local from = math.max(1, #debugRecords - 149)
    for i = from, #debugRecords do
        local rec = debugRecords[i]
        local parts = {"t=" .. tostring(rec.elapsed or 0), "q=" .. tostring(rec.seq or 0), tostring(rec.event)}
        if type(rec.fields) == "table" then
            for k, v in pairs(rec.fields) do
                if tostring(k) == "snapshot" and type(v) == "table" then
                    if type(v.pos) == "table" and type(v.pos.x) == "number" then
                        parts[#parts + 1] = "pos=" .. tostring(math.round(v.pos.x)) .. "," .. tostring(math.round(v.pos.z))
                    end
                    if type(v.phase) == "string" then parts[#parts + 1] = "ph=" .. v.phase end
                    if v.carrying ~= nil then parts[#parts + 1] = "car=" .. (v.carrying and "1" or "0") end
                elseif tostring(k) ~= "snapshot" then
                    local s = compactValue(v)
                    if s then parts[#parts + 1] = tostring(k) .. "=" .. s end
                end
            end
        end
        local line = table.concat(parts, " ")
        lines[#lines + 1] = #line > 220 and line:sub(1, 220) or line
    end
    local text = table.concat(lines, "\n")
    if #text > 60000 then text = text:sub(-60000) end
    return text
end
local function saveLogToFile(auto)
    local text, err = buildLogText()
    if not text then return false, err end
    local name = (auto and "steal-log-last.txt" or ("steal-log-" .. debugSession .. ".txt"))
    local wf = rawget(_G, "writefile")
    if type(wf) == "function" then
        local ok, werr = pcall(wf, name, text)
        if ok then return true, name end
        return false, tostring(werr):sub(1, 80)
    end
    local sc = rawget(_G, "setclipboard")
    if type(sc) == "function" then pcall(sc, text) return false, "writefile tidak ada — log di-copy ke clipboard" end
    return false, "writefile/setclipboard tidak ada di executor"
end
local function guarded(label, callback)
    return function(...)
        local args = table.pack(...)
        local ok, err = xpcall(function() callback(table.unpack(args, 1, args.n)) end, debug.traceback)
        if not ok then debugLog("callback.error", {callback = label, traceback = err}, "ERROR", 1) end
    end
end

-- Destroying the UI is also the cancellation signal for every worker/listener.
warn("[ASE-BOOT 4.35] 02 before-old-session-cleanup")
local previousSelected, previousReturnHomePending
-- Filter (rarity + tempat) dipertahankan lintas eksekusi/rejoin: global VM
-- (eksekusi ulang di client yang sama) → berkas executor (rejoin/proses baru)
-- → snapshot UI lama sebagai fallback terakhir.
local PREF_FILE = "AutoStealEggs_UIPrefs.json"
local previousSelectedAreas, previousAutoNewAreas, previousPrefsSource
local function findExecutorGlobal(name)
    local value = rawget(_G, name)
    if type(value) == "function" then return value end
    local ok, loaded = pcall(function()
        if type(loadstring) ~= "function" then return nil end
        local chunk = loadstring("return " .. name)
        return chunk and chunk() or nil
    end)
    if ok and type(loaded) == "function" then return loaded end
    return nil
end
local function readFilterPrefsFile()
    local reader = findExecutorGlobal("readfile")
    if not reader then return nil end
    local okRead, content = pcall(reader, PREF_FILE)
    if not okRead or type(content) ~= "string" or #content == 0 then return nil end
    local okDecode, decoded = pcall(function() return HttpService:JSONDecode(content) end)
    if not okDecode or typeof(decoded) ~= "table" then return nil end
    return decoded
end
local function loadSavedFilterPrefs()
    local quick = rawget(_G, "AutoStealEggsPrefs")
    if typeof(quick) == "table" then return quick, "global" end
    local fileData = readFilterPrefsFile()
    if fileData then return fileData, "disk" end
    return nil, nil
end
local function rememberPreferences(ui)
    local reader = ui and ui:FindFirstChild("DebugLogs")
    if not reader or not reader:IsA("BindableFunction") then return end
    local ok, saved = pcall(function() return reader:Invoke("snapshot") end)
    if ok and type(saved) == "table" then
        if type(saved.selected) == "string" then previousSelected = saved.selected end
        previousReturnHomePending = saved.returnHomePending == true
    end
end
local old = LP:WaitForChild("PlayerGui"):FindFirstChild("AutoStealEggsUI")
if old then rememberPreferences(old); old:Destroy() end
-- Instance lama bisa jadi dipasang di CoreGui (versi stealth); bersihkan juga.
do
    local ok, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if ok and coreGui then
        local old2 = coreGui:FindFirstChild("AutoStealEggsUI")
        if old2 then rememberPreferences(old2); old2:Destroy() end
    end
end
warn("[ASE-BOOT 4.35] 03 old-host-cleaned")
do
    local saved, source = loadSavedFilterPrefs()
    if saved then
        local tiers = {}
        for _, name in ipairs(saved.tiers or {}) do
            if type(name) == "string" then table.insert(tiers, name) end
        end
        if type(saved.autoNewAreas) == "boolean" then previousAutoNewAreas = saved.autoNewAreas end
        previousSelectedAreas = {}
        for _, name in ipairs(saved.areas or {}) do
            if type(name) == "string" then table.insert(previousSelectedAreas, name) end
        end
        previousSelected = table.concat(tiers, ",")
        previousPrefsSource = source
        debugLog("filter.restored-session", {source = source, tiers = previousSelected, areas = table.concat(previousSelectedAreas, ",")})
    end
end
local alive, generation = true, 0
local Worker = {alive = false, starts = 0, lastActivity = nil, error = nil, waitingRig = false}
local ensureWorker
local miniGui -- forward: tombol restore terpisah, dihancurkan bareng UI utama
local windWindow -- own the library window, not a guessed ScreenGui
-- Eksekusi baru = pemilik baru. Epoch global mematikan loop lama; window
-- WindUI lama (ScreenGui sendiri di luar AutoStealEggsUI) diburu lewat judul
-- lalu dihancurkan; tombol mini lama ikut dibersihkan.
local myEpoch = (rawget(_G, "AutoStealEggsEpoch") or 0) + 1
rawset(_G, "AutoStealEggsEpoch", myEpoch)
local WINDOW_TITLE = "Steal An Egg — Auto Steal"
local function stealWindowContainers(skip)
    local found = {}
    local function scan(parent)
        if not parent then return end
        for _, child in ipairs(parent:GetDescendants()) do
            if child ~= skip and child:IsA("ScreenGui") and child.Name ~= "AutoStealEggsMini" then
                for _, d in ipairs(child:GetDescendants()) do
                    if (d:IsA("TextLabel") or d:IsA("TextButton")) and type(d.Text) == "string"
                        and d.Text:find(WINDOW_TITLE, 1, true) then
                        found[#found + 1] = child
                        break
                    end
                end
            end
        end
    end
    local huiFn = rawget(_G, "gethui")
    if type(huiFn) == "function" then
        local okHui, hui = pcall(huiFn)
        if okHui and typeof(hui) == "Instance" then scan(hui) end
    end
    local ok, coreGui = pcall(function() return game:GetService("CoreGui") end)
    scan(ok and coreGui or nil)
    local pg = LP:FindFirstChild("PlayerGui")
    scan(pg)
    return found
end
local function stealWindowContainer(skip)
    return stealWindowContainers(skip)[1]
end
do
    local known = rawget(_G, "AutoStealEggsWindUI")
    if typeof(known) == "Instance" then pcall(function() known:Destroy() end) end
    rawset(_G, "AutoStealEggsWindUI", nil)
    for _, orphan in ipairs(stealWindowContainers()) do pcall(function() orphan:Destroy() end) end
    local pg = LP:FindFirstChild("PlayerGui")
    local oldMini = pg and pg:FindFirstChild("AutoStealEggsMini")
    if oldMini then pcall(function() oldMini:Destroy() end) end
end
warn("[ASE-BOOT 4.35] 04 orphan-cleanup-done")
local cancelNavigation
local connections = {}
local function connect(signal, fn)
    local connection = signal:Connect(guarded("managed event", fn))
    table.insert(connections, connection)
    return connection
end
connect(LogService.MessageOut, function(message, messageType)
    if message:find("[AutoStealDebug]", 1, true) then return end
    -- Separate unrelated game-error spam from carry/claim failures. No console echo
    -- inside MessageOut: avoids recursion. The original game console is untouched.
    local lowered = message:lower()
    local event, interval
    if lowered:find("carry denied", 1, true) then
        event, interval = "game.carry-denied", 0.2
    elseif lowered:find("claim denied", 1, true) then
        event, interval = "game.claim-denied", 0.2
    elseif message:find("Server Kick Message", 1, true) then
        event, interval = "game.kick", 0
    elseif messageType == Enum.MessageType.MessageError then
        event, interval = "game.error", 10
    end
    if event then debugLog(event, {message = message, messageType = tostring(messageType)}, "ERROR", interval, true) end
end)
debugLog("session.start", {version = "4.39-straight-flight", placeId = game.PlaceId, jobId = game.JobId})
local function active(token)
    return alive and token == generation and rawget(_G, "AutoStealEggsEpoch") == myEpoch
end
local function waitActive(seconds, token)
    local deadline = os.clock() + seconds
    repeat
        if not active(token) then return false end
        Worker.lastActivity = os.clock()
        task.wait(math.min(0.05, math.max(0, deadline - os.clock())))
    until os.clock() >= deadline
    return active(token)
end
local Delivery
local carryKnown, carryState = false, false
local carryUid, carryUpdatedAt, carryRevision = nil, nil, 0
local claimRevision = 0
local carrySignal, verdictSignal = 0, 0
local lastVerdict = nil
local function colorKey(c)
    return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local COLOR_TO_TIER = {}
for name, d in pairs(TIERS) do COLOR_TO_TIER[colorKey(d[2])] = name end

local function rootPos()
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or Vector3.zero
end
local function getRig()
    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or root.Parent ~= char or hum.Parent ~= char or hum.Health <= 0 then return nil, nil end
    return root, hum
end
local function isCarrying()
    if carryKnown then return carryState end
    local gui = LP:FindFirstChild("PlayerGui")
    local drop = gui and gui:FindFirstChild("DropHeldEgg")
    return drop ~= nil and drop:IsA("ScreenGui") and drop.Enabled == true
end

-- Passive subscriptions only; no remote calls or hooks.
local networking = ReplicatedStorage:FindFirstChild("Packages")
networking = networking and networking:FindFirstChild("Networking")
local carryFeed = networking and networking:FindFirstChild("RE/EggWorld/FieldEggCarry")
local claimFeed = networking and networking:FindFirstChild("RE/EggWorld/FieldEggRedeemVerdict")
local claimMovementSettleUntil = 0
if carryFeed and carryFeed:IsA("RemoteEvent") then
    connect(carryFeed.OnClientEvent, function(payload)
        debugLog("carry.event", {payload = payload})
        if Delivery then Delivery:onCarry(payload) end
        if type(payload) == "table" and type(payload.IsCarrying) == "boolean" then
            carryKnown, carryState = true, payload.IsCarrying
            carryRevision += 1
            carryUid = payload.IsCarrying and payload.Uid or nil
            carryUpdatedAt = os.clock()
            if payload.IsCarrying then carrySignal += 1 end
        end
    end)
end
if claimFeed and claimFeed:IsA("RemoteEvent") then
    connect(claimFeed.OnClientEvent, function(payload)
        debugLog("claim.event", {payload = payload})
        if Delivery then Delivery:onClaim(payload) end
        if type(payload) == "table" and payload.AssetCategory ~= nil then
            -- Observed claim→position reset delay ~0.52 s. Pause positional writes
            -- for one second, so the server's claim relocation can finish.
            claimMovementSettleUntil = os.clock() + 1
            debugLog("speed.claim-settle", {untilAt=claimMovementSettleUntil, category=payload.AssetCategory})
            claimRevision += 1
            verdictSignal += 1
            lastVerdict = {cat = payload.AssetCategory, name = payload.DisplayName, rar = payload.Rarity}
        end
    end)
end
debugLog("feeds.ready", {carry = carryFeed ~= nil, claim = claimFeed ~= nil})

-- Same record feed/schema as Client.EggState, without requiring its protected
-- dependencies. Snapshot requests are single-flight; events win over older reads.
local Field = {records = {}, revisions = {}, sequence = 0, ready = false,
    pending = false, lastRequest = -math.huge, lastSnapshotAt = nil, error = nil, epoch = 0}
local function updateField(record)
    if type(record) ~= "table" or type(record.Uid) ~= "string" then return end
    Field.sequence += 1
    Field.revisions[record.Uid] = Field.sequence
    Field.records[record.Uid] = record
    if Delivery then Delivery:onField(record.Uid, record) end
end
local function removeField(uid)
    if type(uid) ~= "string" then return end
    Field.sequence += 1
    Field.revisions[uid], Field.records[uid] = Field.sequence, nil
    if Delivery then Delivery:onField(uid, nil) end
end
local function fieldFeed(name, callback)
    local ev = networking and networking:FindFirstChild("RE/EggWorld/" .. name)
    if ev and ev:IsA("RemoteEvent") then connect(ev.OnClientEvent, callback) end
end
fieldFeed("FieldEggShifted", updateField)
fieldFeed("FieldEggGone", removeField)
fieldFeed("FieldEggBatchShifted", function(payload)
    if type(payload) ~= "table" then return end
    for _, uid in ipairs(payload.RemovedUids or {}) do removeField(uid) end
    for _, record in ipairs(payload.UpdatedRecords or {}) do updateField(record) end
end)
local function requestFieldSnapshot()
    if Field.pending or os.clock() - Field.lastRequest < 10 then return end
    local ask = networking and networking:FindFirstChild("RF/EggWorld/AskFieldEggSnapshot")
    if not ask or not ask:IsA("RemoteFunction") then Field.error = "snapshot remote missing"; return end
    Field.pending, Field.lastRequest = true, os.clock()
    local revision, epoch = Field.sequence, Field.epoch
    local settled = false
    task.spawn(function()
        local ok, payload = pcall(function() return ask:InvokeServer() end)
        -- Zombie invoke (jawaban tidak pernah balik) tidak boleh mengunci Field
        -- selamanya: watchdog di bawah melepas pending supaya retry jalan lagi.
        if settled then return end
        settled, Field.pending = true, false
        if not alive or epoch ~= Field.epoch then return end
        if not ok or type(payload) ~= "table" or type(payload.Records) ~= "table" then
            Field.error = tostring(payload)
            debugLog("field.snapshot-error", {error = Field.error}, "WARN")
            return
        end
        local seen = {}
        for _, record in ipairs(payload.Records) do
            if type(record) == "table" and type(record.Uid) == "string" then
                seen[record.Uid] = true
                if (Field.revisions[record.Uid] or 0) <= revision then Field.records[record.Uid] = record end
            end
        end
        for uid in pairs(Field.records) do
            if not seen[uid] and (Field.revisions[uid] or 0) <= revision then Field.records[uid] = nil end
        end
        Field.ready, Field.error, Field.lastSnapshotAt = true, nil, os.clock()
        debugLog("field.snapshot-ready", {count = #payload.Records, elapsed = os.clock() - Field.lastRequest})
    end)
    task.delay(8, function()
        if settled or not alive or epoch ~= Field.epoch then return end
        settled, Field.pending = true, false
        Field.error = "snapshot timeout (8s, diulang otomatis)"
        debugLog("field.snapshot-timeout", {elapsed = 8}, "WARN")
    end)
end
local function targetAvailable(target)
    if not target or not target.prompt.Parent or not target.slot.Parent then return false end
    if not Field.ready then return true end
    local record = Field.records[target.uid]
    return record ~= nil and (record.State == "Slot" or record.State == "Dropped")
end
local function fieldGateOpen()
    local world = Workspace:FindFirstChild("World")
    local areas = world and world:FindFirstChild("Areas")
    if not areas then return true end
    local collision = areas:FindFirstChild("WallStartCollision")
    if collision and collision:IsA("BasePart") and collision.CanCollide then return false end
    local visual = areas:FindFirstChild("WallStartVisual")
    return not (visual and visual:IsA("BasePart") and visual.Size.Y > 0.25)
end

--==============================================================
-- TEMPLATE INDEX (mesh+warna -> kategori)
--==============================================================
local Templates = { exact = {}, byMesh = {} }

local function buildTemplateIndex()
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local models = assets and assets:FindFirstChild("Models")
    local eggs = models and models:FindFirstChild("Eggs")
    if not eggs then return false end
    Templates.exact, Templates.byMesh = {}, {}
    for _, tpl in ipairs(eggs:GetChildren()) do
        local colors = {}
        for _, d in ipairs(tpl:GetDescendants()) do
            if d:IsA("MeshPart") then colors[d.MeshId] = d.Color end
        end
        local ids = {}
        for id in pairs(colors) do table.insert(ids, id) end
        if #ids > 0 then
            table.sort(ids)
            local key = table.concat(ids, "|")
            local entry = { category = tpl.Name, colors = colors }
            Templates.exact[key] = Templates.exact[key] or {}
            table.insert(Templates.exact[key], entry)
            for id in pairs(colors) do
                Templates.byMesh[id] = Templates.byMesh[id] or {}
                table.insert(Templates.byMesh[id], entry)
            end
        end
    end
    return true
end

local function colorDistance(a, b)
    if not a or not b then return math.huge end
    local d = (a.R - b.R) ^ 2 + (a.G - b.G) ^ 2 + (a.B - b.B) ^ 2
    return math.sqrt(d)
end

local function scoreCandidate(entry, colors)
    local total, n = 0, 0
    for id, col in pairs(colors) do
        local tcol = entry.colors[id]
        if tcol then
            total += colorDistance(col, tcol)
            n += 1
        end
    end
    if n == 0 then return math.huge end
    return total / n
end

-- cocokkan model slot -> kategori (nilai balik: category atau nil)
local function matchCategory(slotModel)
    if not next(Templates.exact) then
        if not buildTemplateIndex() then return nil end
    end
    local colors = {}
    for _, d in ipairs(slotModel:GetDescendants()) do
        if d:IsA("MeshPart") then colors[d.MeshId] = d.Color end
    end
    local ids = {}
    for id in pairs(colors) do table.insert(ids, id) end
    if #ids == 0 then return nil end
    table.sort(ids)
    local key = table.concat(ids, "|")

    local best, bestD, secondD = nil, math.huge, math.huge
    local function consider(entry)
        local d = scoreCandidate(entry, colors)
        if d < bestD then
            secondD = bestD
            bestD = d
            best = entry
        elseif d < secondD then
            secondD = d
        end
    end

    local exact = Templates.exact[key]
    if exact then
        for _, e in ipairs(exact) do consider(e) end
    else
        -- fallback: template yang mengandung semua mesh kita (mis. sebagian part tak ke-render)
        local candidates = {}
        for id in pairs(colors) do
            for _, e in ipairs(Templates.byMesh[id] or {}) do
                candidates[e] = (candidates[e] or 0) + 1
            end
        end
        for e, cnt in pairs(candidates) do
            if cnt == #ids then consider(e) end
        end
    end

    if best and bestD <= 0.12 and (secondD - bestD) >= 0.015 then
        return best.category
    end
    return nil
end

--==============================================================
-- RARITY RESOLVER
--==============================================================
local function rarityOf(slotModel, category)
    -- Snapshot identity wins over cosmetic highlights and shared mesh/color signatures.
    if category then return CATEGORY_RARITY[category] or "Unknown", category, "server-category" end
    if not slotModel then return "Unknown", nil, "no-slot" end
    for _, d in ipairs(slotModel:GetDescendants()) do
        if d:IsA("Highlight") and d.Name == "RareAreaEggHighlight" then
            local tier = COLOR_TO_TIER[colorKey(d.OutlineColor)]
            if tier then return tier, category, "highlight" end
        end
    end
    local cat = matchCategory(slotModel)
    if cat then
        return CATEGORY_RARITY[cat] or "Unknown", cat, "signature"
    end
    return "Unknown", nil, "unmatched"
end

--==============================================================
-- STATE
--==============================================================
    -- Flag "tengah pulang" yang tersisa dari sesi lamanya hanya dihormati kalau
    -- telur benar-benar sedang dibawa sekarang; semennya membuat ON pertama
    -- tanpa telur malah jalan pulang dulu (kelihatan seperti "balik ke base").
local reloadResumePending = previousReturnHomePending == true and isCarrying() == true
local State = {
    running = false,
    stolen = 0,
    claimed = 0,
    home = nil,
    homePlot = nil,
    homeSource = nil,
    returnHomePending = reloadResumePending,
    returnClaimRevision = reloadResumePending and 0 or nil,
    returnUid = nil,
    failed = 0,
    consecutiveFails = 0,
    selected = {
        Common = true, Uncommon = true, Rare = true, Epic = true, Legendary = true,
        Mythic = true, Cosmic = true, Secret = true, Eternal = true, Divine = true,
        Limited = true, Transcendent = true, Titan = true, Rainbow = true, BrainrotGod = true,
        SuperRare = true, LightDark = true, Unknown = false,
    },
    selectedAreas = {},
    autoNewAreas = true,
    blacklist = setmetatable({}, { __mode = "k" }),
    tries = setmetatable({}, { __mode = "k" }),
    log = {},
}
-- Verified against live GuardAreas and 65 server snapshot records (13 AreaIds).
local AREA_LIST = {"Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano",
    "Abyss Ocean", "Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple",
    "Light Dark", "Enchanted Forest"}
for _, area in ipairs(AREA_LIST) do State.selectedAreas[area] = true end
if previousSelected ~= nil then
    for tier in pairs(State.selected) do State.selected[tier] = false end
    for tier in previousSelected:gmatch("[^,]+") do
        if TIERS[tier] then State.selected[tier] = true end
    end
end
if previousSelectedAreas ~= nil then
    for area in pairs(State.selectedAreas) do State.selectedAreas[area] = false end
    for _, area in ipairs(previousSelectedAreas) do
        if State.selectedAreas[area] ~= nil then State.selectedAreas[area] = true end
    end
end
if previousAutoNewAreas ~= nil then State.autoNewAreas = previousAutoNewAreas end
debugLog("filter.restored", {source = previousPrefsSource, tiers = previousSelected, areas = previousSelectedAreas and table.concat(previousSelectedAreas, ",")})
-- Simpanan filter: global VM + berkas (kalau executor punya writefile).
-- Dipanggil dari semua jalur perubahan filter di bawah.
local saveFilterPrefs
local function filterPrefsPayload()
    local tiers, areas = {}, {}
    for _, name in ipairs(TIER_ORDER) do
        if State.selected[name] then table.insert(tiers, name) end
    end
    for _, area in ipairs(AREA_LIST) do
        if State.selectedAreas[area] then table.insert(areas, area) end
    end
    return {version = 1, tiers = tiers, areas = areas, autoNewAreas = State.autoNewAreas == true}
end
saveFilterPrefs = function()
    local data = filterPrefsPayload()
    rawset(_G, "AutoStealEggsPrefs", data)
    local writer = findExecutorGlobal("writefile")
    if writer then
        local okEncode, encoded = pcall(function() return HttpService:JSONEncode(data) end)
        if okEncode and type(encoded) == "string" then
            local okWrite, err = pcall(writer, PREF_FILE, encoded)
            if not okWrite then
                debugLog("filter.save-failed", {error = tostring(err):sub(1, 80)}, "WARN", 5)
            end
        end
    end
    debugLog("filter.saved", {tiers = table.concat(data.tiers, ","), areas = table.concat(data.areas, ",")}, "INFO", 0.25)
end
-- Ownership is resolved by UserId, never a potentially duplicated display name.
local ownersBySlot, ownerRevisions, ownersReady = {}, {}, false
local plotsFolder = Workspace:FindFirstChild("Plots")
local function resolveAutoBase()
    plotsFolder = Workspace:FindFirstChild("Plots")
    local slot, source, count = nil, nil, 0
    if ownersReady then
        for id, owner in pairs(ownersBySlot) do
            if owner == LP.UserId then slot, count = tostring(id), count + 1 end
        end
        source = "Homestead.UserId"
    elseif plotsFolder then
        for _, plot in ipairs(plotsFolder:GetChildren()) do
            local sign = plot:FindFirstChild("PlotSign")
            local attachment = sign and sign:FindFirstChild("Attachment")
            local marker = attachment and attachment:FindFirstChild("YourBase")
            if marker and marker:IsA("BillboardGui") and marker.Enabled then
                slot, count = plot.Name, count + 1
            end
        end
        source = "YourBase.marker"
    end
    local plot = count == 1 and plotsFolder and plotsFolder:FindFirstChild(slot)
    local spawn = plot and plot:FindFirstChild("SpawnPoint")
    local previousPlot, previousSource, previousHome = State.homePlot, State.homeSource, State.home
    State.homePlot, State.homeSource, State.home = nil, nil, nil
    if spawn and spawn:IsA("BasePart") then
        State.homePlot, State.homeSource, State.home = slot, source, spawn.Position
    end
    if previousPlot ~= State.homePlot or previousSource ~= State.homeSource or previousHome ~= State.home then
        debugLog("base.auto-resolved", {
            plot = State.homePlot, source = State.homeSource, point = State.home,
            ownerUserId = LP.UserId, ownersReady = ownersReady, candidates = count,
        }, State.home and "INFO" or "WARN")
    end
    return State.home
end
local ownerFeed = networking and networking:FindFirstChild("RE/Homestead/StateShifted")
if ownerFeed and ownerFeed:IsA("RemoteEvent") then
    connect(ownerFeed.OnClientEvent, function(payload)
        if type(payload) ~= "table" or type(payload.Revision) ~= "number" or not tonumber(payload.Slot) then return end
        local slot = tostring(payload.Slot)
        if payload.Revision > (ownerRevisions[slot] or -1) then
            ownerRevisions[slot], ownersBySlot[slot] = payload.Revision, payload.UserId
            resolveAutoBase()
        end
    end)
end
local baseRequestPending = false
local lastBaseRequest = -math.huge
local function requestBaseSnapshot()
    resolveAutoBase()
    if baseRequestPending or os.clock() - lastBaseRequest < 5 then return end
    local ask = networking and networking:FindFirstChild("RF/Homestead/AskState")
    if not ask or not ask:IsA("RemoteFunction") then
        debugLog("base.snapshot-unavailable", {fallback = State.homeSource}, "WARN", 5)
        return
    end
    baseRequestPending, lastBaseRequest = true, os.clock()
    task.spawn(function()
        -- Same read-only ownership query used by the game's PlotState. No claim,
        -- placement, movement, or teleport remote is called here.
        local ok, payload = pcall(function() return ask:InvokeServer() end)
        baseRequestPending = false
        if not alive then return end
        if not ok or type(payload) ~= "table" or type(payload.OwnersBySlot) ~= "table" or type(payload.Revision) ~= "number" then
            debugLog("base.snapshot-error", {error = tostring(payload)}, "WARN")
            return
        end
        local seen = {}
        for id, owner in pairs(payload.OwnersBySlot) do
            if tonumber(id) then
                local slot = tostring(id)
                seen[slot] = true
                if payload.Revision >= (ownerRevisions[slot] or -1) then
                    ownerRevisions[slot], ownersBySlot[slot] = payload.Revision, owner
                end
            end
        end
        for slot in pairs(ownersBySlot) do
            if not seen[slot] and payload.Revision >= (ownerRevisions[slot] or -1) then
                ownersBySlot[slot], ownerRevisions[slot] = nil, payload.Revision
            end
        end
        ownersReady = true
        resolveAutoBase()
    end)
end
requestBaseSnapshot()

local lastTarget, debugPhase, debugAttempt = nil, "idle", 0
local function snapshot(target)
    local hrp, hum = getRig()
    local selected = {}
    for name, on in pairs(State.selected) do if on then table.insert(selected, name) end end
    table.sort(selected)
    local data = {
        phase = debugPhase, running = State.running, generation = generation,
        workerAlive = Worker.alive, workerStarts = Worker.starts, workerLastActivity = Worker.lastActivity,
        workerError = Worker.error, waitingCharacter = Worker.waitingRig,
        attempt = debugAttempt,
        pos = hrp and hrp.Position, anchored = hrp and hrp.Anchored,
        health = hum and hum.Health, walkSpeed = hum and hum.WalkSpeed,
        humanoidState = hum and tostring(hum:GetState()),
        carrying = isCarrying(), carryKnown = carryKnown, carryState = carryState,
        carryUid = carryUid, carryRevision = carryRevision,
        fieldReady = Field.ready, fieldPending = Field.pending, fieldError = Field.error,
        claimRevision = claimRevision, base = State.home, basePlot = State.homePlot, baseSource = State.homeSource,
        returnHomePending = State.returnHomePending,
        stolen = State.stolen, claimed = State.claimed, failed = State.failed,
        selected = table.concat(selected, ","), tools = {},
    }
    if LP.Character then
        for _, child in ipairs(LP.Character:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(data.tools, {name = child.Name, itemType = child:GetAttribute("ItemType")})
            end
        end
    end
    local drop = LP.PlayerGui:FindFirstChild("DropHeldEgg")
    data.carryGui = drop and drop:IsA("ScreenGui") and drop.Enabled or false
    target = target or lastTarget
    if target then
        local prompt, part = target.prompt, target.part
        data.target = {
            uid = target.uid, slot = target.slot and target.slot.Name, rarity = target.rarity,
            category = target.category, via = target.via,
            promptAlive = prompt.Parent ~= nil, slotAlive = target.slot and target.slot.Parent ~= nil,
            enabled = prompt.Enabled, holdDuration = prompt.HoldDuration,
            maxDistance = prompt.MaxActivationDistance,
            prompt = prompt:GetFullName(), promptPosition = part and part.Position,
            distance = hrp and part and (hrp.Position - part.Position).Magnitude,
            tries = State.tries[prompt] or 0,
            blacklistRemaining = math.max(0, (State.blacklist[prompt] or 0) - os.clock()),
        }
    end
    return data
end

--==============================================================
-- SCANNER
--==============================================================
warn("[ASE-BOOT 4.35] 05 before-slot-watchers")
local promptParts, slotParts, slotConnections = {}, {}, {}
local rarityCache = setmetatable({}, { __mode = "k" })
local grid, gridDirty = {}, true
local scanCount, resolveCount, lastScanMs = 0, 0, 0
local lastFilterScan = {serverMatches = 0, renderedMatches = 0, promptMatches = 0, eligible = 0}
local function cell(x, z) return x .. ":" .. z end
local function unwatchSlot(slot)
    for _, c in ipairs(slotConnections[slot] or {}) do c:Disconnect() end
    slotConnections[slot], slotParts[slot], rarityCache[slot] = nil, nil, nil
    gridDirty = true
end
local function watchSlot(slot)
    if not slot:IsA("Model") or slotConnections[slot] then return end
    local owned = {}
    slotConnections[slot] = owned
    local function changed()
        rarityCache[slot] = nil
        slotParts[slot] = slot:FindFirstChild("Hitbox", true) or slot:FindFirstChildWhichIsA("BasePart", true)
        gridDirty = true
    end
    local function watchPart(d)
        if d:IsA("MeshPart") then
            for _, property in ipairs({"Color", "MeshId"}) do
                table.insert(owned, d:GetPropertyChangedSignal(property):Connect(guarded("slot." .. property, changed)))
            end
        elseif d:IsA("Highlight") then
            table.insert(owned, d:GetPropertyChangedSignal("OutlineColor"):Connect(guarded("slot.highlight", changed)))
        end
    end
    for _, d in ipairs(slot:GetDescendants()) do watchPart(d) end
    table.insert(owned, slot.DescendantAdded:Connect(guarded("slot.add", function(d) watchPart(d); changed() end)))
    table.insert(owned, slot.DescendantRemoving:Connect(guarded("slot.remove", changed)))
    table.insert(owned, slot.AncestryChanged:Connect(guarded("slot.ancestry", function()
        if not slot:IsDescendantOf(Workspace) then unwatchSlot(slot) end
    end)))
    changed()
end
local slotsFolder
local function watchWorkspaceChild(child)
    if child.Name == "SmartPromptPart" and child:IsA("BasePart") then
        promptParts[child] = true
    elseif child.Name == "AreaEggSlotsClient" and child ~= slotsFolder then
        slotsFolder = child
        for _, s in ipairs(child:GetChildren()) do watchSlot(s) end
        connect(child.ChildAdded, watchSlot)
        connect(child.ChildRemoved, unwatchSlot)
    end
end
connect(Workspace.ChildAdded, watchWorkspaceChild)
connect(Workspace.ChildRemoved, function(child)
    promptParts[child] = nil
    if child == slotsFolder then
        slotsFolder = nil
        local removed = {}
        for slot in pairs(slotConnections) do table.insert(removed, slot) end
        for _, slot in ipairs(removed) do unwatchSlot(slot) end
    end
end)
for _, child in ipairs(Workspace:GetChildren()) do watchWorkspaceChild(child) end

-- AreaId di luar AREA_LIST = area baru buatan game update/event: auto-index
-- (klik Filter tempat untuk area yang sudah dikenal; toggle "Auto ambil area baru" di WindUI mematikannya).
local function areaAllowed(areaId)
    local flag = areaId and State.selectedAreas[areaId]
    if flag == true then return true end
    if flag == false then return false end
    return State.autoNewAreas == true
end

-- Re-read identity and selection at the action boundary; never trust a cached label.
local function validateEggRarity(egg)
    local record = egg and Field.records[egg.uid]
    if not Field.ready or not record or record.Uid ~= egg.uid
        or not egg.slot or egg.slot.Name ~= egg.uid
        or (record.State ~= "Slot" and record.State ~= "Dropped") then
        return false, "identitas telur belum terverifikasi"
    end
    local rarity = CATEGORY_RARITY[record.AssetCategory]
    if not areaAllowed(record.AreaId) then
        return false, "tempat di luar filter: " .. tostring(record.AreaId)
    end
    if not rarity then return false, "rarity kategori belum terverifikasi" end
    egg.rarity, egg.category, egg.via = rarity, record.AssetCategory, "server-category"
    if State.selected[rarity] ~= true then return false, "rarity di luar filter: " .. rarity end
    return true
end

-- WindUI Select dispatches callbacks asynchronously. Only real changes may
-- trigger a redraw: a synchronous "syncing" flag alone causes feedback loops.
local function applyFilterSelection(selection, options)
    if type(options) ~= "table" then return false end
    local nextSelection, changed = {}, false
    for key in pairs(selection) do nextSelection[key] = false end
    for _, value in ipairs(options) do
        local name = type(value) == "table" and value.Title or value
        if type(name) == "string" and nextSelection[name] ~= nil then nextSelection[name] = true end
    end
    for key, value in pairs(nextSelection) do
        if selection[key] ~= value then changed = true end
    end
    if changed then
        for key, value in pairs(nextSelection) do selection[key] = value end
        if saveFilterPrefs then saveFilterPrefs() end
    end
    return changed
end

local function collectEggs()
    local started, now, origin = os.clock(), os.clock(), rootPos()
    local list, totalDetected, matchedSlots, unknown = {}, 0, 0, 0
    lastFilterScan = {serverMatches = 0, renderedMatches = 0, promptMatches = 0, eligible = 0, byArea = {}}
    if not Field.ready then return list, 0 end
    for _, record in pairs(Field.records) do
        local rarity = CATEGORY_RARITY[record.AssetCategory]
        if (record.State == "Slot" or record.State == "Dropped")
            and rarity and State.selected[rarity] and areaAllowed(record.AreaId) then
            lastFilterScan.serverMatches += 1
            lastFilterScan.byArea[record.AreaId] = (lastFilterScan.byArea[record.AreaId] or 0) + 1
        end
    end
    for slot, part in pairs(slotParts) do
        local record = Field.records[slot.Name]
        if part and part.Parent and slot.Parent and record
            and (record.State == "Slot" or record.State == "Dropped")
            and State.selected[CATEGORY_RARITY[record.AssetCategory]]
            and areaAllowed(record.AreaId) then
            lastFilterScan.renderedMatches += 1
        end
    end
    if gridDirty then
        grid = {}
        for slot, part in pairs(slotParts) do
            if part and part.Parent and slot.Parent then
                local p = part.Position
                local key = cell(math.floor(p.X / 8), math.floor(p.Z / 8))
                grid[key] = grid[key] or {}
                table.insert(grid[key], slot)
            end
        end
        gridDirty = false
    end
    for part in pairs(promptParts) do
        local prompt = part:FindFirstChild("CarryAreaEgg")
        if prompt and prompt:IsA("ProximityPrompt") and prompt.ActionText == "Steal" then
            totalDetected += 1
            if (State.blacklist[prompt] or 0) <= now and
                (prompt.Enabled or (CONFIG.pickupMode == "server" and not CONFIG.useRealInput)) then
                local p, slot, distance = part.Position, nil, 6
                local cx, cz = math.floor(p.X / 8), math.floor(p.Z / 8)
                for dx = -1, 1 do
                    for dz = -1, 1 do
                        for _, candidate in ipairs(grid[cell(cx + dx, cz + dz)] or {}) do
                            local pv = slotParts[candidate]
                            local d = (pv.Position - p).Magnitude
                            if d < distance then distance, slot = d, candidate end
                        end
                    end
                end
                if slot then
                    local record = Field.records[slot.Name]
                    if not record or record.Uid ~= slot.Name
                        or (record.State ~= "Slot" and record.State ~= "Dropped") then continue end
                    matchedSlots += 1
                    local cached = rarityCache[slot]
                    local category = record and record.AssetCategory
                    if not cached or cached.snapshotCategory ~= category then
                        local rarity, cat, via = rarityOf(slot, category)
                        cached = {rarity, cat, via, snapshotCategory = category}
                        rarityCache[slot] = cached
                        resolveCount += 1
                    end
                    local rarity, cat, via = table.unpack(cached)
                    if rarity == "Unknown" then unknown += 1 end
                    if rarity ~= "Unknown" and State.selected[rarity] == true
                        and areaAllowed(record.AreaId) then
                        lastFilterScan.promptMatches += 1
                        table.insert(list, {
                            prompt = prompt, part = part, slot = slot, pos = p,
                            uid = record and record.Uid or slot.Name,
                            rarity = rarity, category = cat, via = via, area = record.AreaId, dist = (p - origin).Magnitude,
                        })
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        if CONFIG.preferHighestRarity then
            local ra = a.rarity == "Unknown" and 0 or TIERS[a.rarity][1]
            local rb = b.rarity == "Unknown" and 0 or TIERS[b.rarity][1]
            if ra ~= rb then return ra > rb end
        end
        return a.dist < b.dist
    end)
    scanCount += 1
    lastScanMs = (os.clock() - started) * 1000
    lastFilterScan.eligible = #list
    debugLog("scan.summary", {
        detected = totalDetected, matchedSlots = matchedSlots, unknown = unknown,
        eligible = #list, scanMs = lastScanMs, resolves = resolveCount,
        serverMatches = lastFilterScan.serverMatches, renderedMatches = lastFilterScan.renderedMatches,
    }, "INFO", 5)
    return list, totalDetected
end

local function filterScanText()
    if not Field.ready then return "Menunggu snapshot server; filter tidak memunculkan telur." end
    local rows = {}
    for _, area in ipairs(AREA_LIST) do
        if State.selectedAreas[area] then
            table.insert(rows, area .. ": " .. tostring(lastFilterScan.byArea and lastFilterScan.byArea[area] or 0))
        end
    end
    -- Area baru buatan game (di luar daftar) ikut dilaporkan: auto-index.
    local newRows, seenNew = {}, {}
    for _, record in pairs(Field.records) do
        local name = tostring(record.AreaId)
        if name ~= "nil" and State.selectedAreas[name] == nil and not seenNew[name] then
            seenNew[name] = true
            table.insert(newRows, name .. ": auto")
        end
    end
    return string.format("Cocok di server: %d | Ter-render: %d | Siap diambil: %d\n%s\nArea baru (auto-index): %s\nFilter hanya memilih target, tidak memunculkan telur.",
        lastFilterScan.serverMatches, lastFilterScan.renderedMatches, lastFilterScan.eligible,
        #rows > 0 and table.concat(rows, ", ") or "Tidak ada tempat dipilih",
        #newRows > 0 and table.concat(newRows, ", ") or "tidak ada")
end

--==============================================================
-- UI
--==============================================================
local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

-- WindUI mirror hooks (no-op unless the community UI library loads successfully).
local uiHooks = {}

-- Preserve the user's CoreGui preference; this is not a guarantee of invisibility
-- or protection from anti-cheat detection.
local uiParent = LP:WaitForChild("PlayerGui")
do
    local ok, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if ok and coreGui then
        local ok2 = pcall(function()
            local probe = Instance.new("Folder")
            probe.Name = "ASE_parentProbe"
            probe.Parent = coreGui
            probe:Destroy()
        end)
        if ok2 then uiParent = coreGui end
    end
end

warn("[ASE-BOOT 4.35] 06 before-host-ui")
local gui = new("ScreenGui", {
    Name = "AutoStealEggsUI",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 50,
}, uiParent)
connect(gui.Destroying, function()
    debugLog("session.stop", {reason = "UI destroyed / reload", snapshot = snapshot()})
    pcall(function() saveLogToFile(true) end)
    alive, State.running = false, false
    generation += 1
    if windWindow then
        local oldWindow = windWindow
        windWindow = nil
        pcall(function() oldWindow:Destroy() end)
    end
    if miniGui and miniGui.Parent then pcall(function() miniGui:Destroy() end) end
    if cancelNavigation then cancelNavigation(); cancelNavigation = nil end
    local hrp, hum = getRig()
    if hrp and hum then hum:MoveTo(hrp.Position) end
    for _, c in ipairs(connections) do c:Disconnect() end
    local removed = {}
    for slot in pairs(slotConnections) do table.insert(removed, slot) end
    for _, slot in ipairs(removed) do unwatchSlot(slot) end
end)

local main = new("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(310, 540),
    Position = UDim2.new(0.5, -155, 0.5, -270),
    BackgroundColor3 = Color3.fromRGB(22, 23, 28),
    BorderSizePixel = 0,
    Active = true,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 14) }, main)
new("UIStroke", { Color = Color3.fromRGB(64, 66, 82), Thickness = 1.2, Transparency = 0.2 }, main)

-- header
local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundColor3 = Color3.fromRGB(30, 31, 38),
    BorderSizePixel = 0,
}, main)
new("UICorner", { CornerRadius = UDim.new(0, 14) }, header)
new("TextLabel", {
    Text = "🥚  Steal An Egg — Auto Steal",
    Font = Enum.Font.GothamBold, TextSize = 14,
    TextColor3 = Color3.fromRGB(237, 238, 246), BackgroundTransparency = 1,
    Position = UDim2.fromOffset(14, 5), Size = UDim2.new(1, -90, 0, 20),
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)
new("TextLabel", {
    Text = "v4.39 • straight flight",
    Font = Enum.Font.Gotham, TextSize = 10,
    TextColor3 = Color3.fromRGB(122, 126, 142), BackgroundTransparency = 1,
    Position = UDim2.fromOffset(14, 24), Size = UDim2.new(1, -90, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)
local minBtn = new("TextButton", {
    Text = "—", Font = Enum.Font.GothamBold, TextSize = 15,
    TextColor3 = Color3.fromRGB(205, 207, 220), BackgroundColor3 = Color3.fromRGB(44, 46, 58),
    Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -38, 0, 8),
    BorderSizePixel = 0,
}, header)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, minBtn)

-- body
local body = new("Frame", {
    Name = "Body",
    Size = UDim2.new(1, -20, 1, -54),
    Position = UDim2.fromOffset(10, 48),
    BackgroundTransparency = 1,
}, main)

local toggleBtn = new("TextButton", {
    Name = "Toggle",
    Text = "AUTO STEAL: OFF",
    Font = Enum.Font.GothamBold, TextSize = 14,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundColor3 = Color3.fromRGB(66, 70, 88),
    Size = UDim2.new(1, 0, 0, 38), BorderSizePixel = 0,
}, body)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, toggleBtn)

local statusFrame = new("Frame", {
    Size = UDim2.new(1, 0, 0, 58),
    Position = UDim2.fromOffset(0, 46),
    BackgroundColor3 = Color3.fromRGB(28, 29, 35),
    BorderSizePixel = 0,
}, body)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, statusFrame)
local statusText = new("TextLabel", {
    Text = "Status: siap",
    Font = Enum.Font.Gotham, TextSize = 11,
    TextColor3 = Color3.fromRGB(192, 194, 208), BackgroundTransparency = 1,
    Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -20, 1, -10),
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
}, statusFrame)

-- quick buttons
local quickRow = new("Frame", {
    Size = UDim2.new(1, 0, 0, 24),
    Position = UDim2.fromOffset(0, 110),
    BackgroundTransparency = 1,
}, body)
local quickLayout = new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, quickRow)

local function setFromTier(minRank, exactNone)
    for name in pairs(State.selected) do
        State.selected[name] = not exactNone and (name ~= "Unknown" or minRank == -1) and TIERS[name][1] >= minRank
    end
    debugLog("filter.preset", {minRank = minRank, none = exactNone == true, snapshot = snapshot()})
    if saveFilterPrefs then saveFilterPrefs() end
    return 0
end

local function makeQuick(text, fn)
    local b = new("TextButton", {
        Text = text, Font = Enum.Font.GothamMedium, TextSize = 10,
        TextColor3 = Color3.fromRGB(200, 202, 214),
        BackgroundColor3 = Color3.fromRGB(40, 42, 52),
        Size = UDim2.fromOffset(50, 22), BorderSizePixel = 0,
    }, quickRow)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    connect(b.MouseButton1Click, fn)
    return b
end

new("TextLabel", {
    Text = "Filter Kelangkaan:", Font = Enum.Font.Gotham, TextSize = 11,
    TextColor3 = Color3.fromRGB(148, 152, 168), BackgroundTransparency = 1,
    Position = UDim2.fromOffset(2, 138), Size = UDim2.new(1, 0, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, body)

local chipHolder = new("Frame", {
    Size = UDim2.new(1, 0, 0, 168),
    Position = UDim2.fromOffset(0, 154),
    BackgroundTransparency = 1,
}, body)
new("UIGridLayout", {
    CellSize = UDim2.fromOffset(94, 24),
    CellPadding = UDim2.fromOffset(4, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, chipHolder)

local chips = {}
local refreshChips
local function makeChip(name)
    local chip = new("TextButton", {
        Text = name, Font = Enum.Font.GothamMedium, TextSize = 10,
        TextColor3 = Color3.fromRGB(190, 192, 206),
        BackgroundColor3 = Color3.fromRGB(42, 44, 54),
        BorderSizePixel = 0, TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = table.find(TIER_ORDER, name) or 0,
    }, chipHolder)
    new("UICorner", { CornerRadius = UDim.new(0, 7) }, chip)
    chips[name] = chip
    connect(chip.MouseButton1Click, function()
        State.selected[name] = not State.selected[name]
        debugLog("filter.change", {tier = name, selected = State.selected[name]})
        if saveFilterPrefs then saveFilterPrefs() end
        refreshChips()
    end)
end
for _, name in ipairs(TIER_ORDER) do makeChip(name) end

function refreshChips()
    for name, chip in pairs(chips) do
        local on = State.selected[name]
        chip.BackgroundColor3 = on and TIERS[name][2] or Color3.fromRGB(42, 44, 54)
        chip.TextColor3 = on and Color3.fromRGB(12, 12, 14) or Color3.fromRGB(190, 192, 206)
        chip.Text = (on and "● " or "○ ") .. name
    end
    if uiHooks.filter then uiHooks.filter() end
end

-- Apply the same preset as the UI without enabling automation.
local filterControl = new("BindableFunction", {Name = "FilterControl"}, gui)
filterControl.OnInvoke = function(minRank)
    if type(minRank) ~= "number" or minRank ~= math.floor(minRank) or minRank < 1 or minRank > 17 then
        return {ok = false, reason = "minimum rank must be an integer from 1 to 17"}
    end
    setFromTier(minRank)
    refreshChips()
    return {ok = true, selected = snapshot().selected}
end
do
    makeQuick("All", function() setFromTier(-1); refreshChips() end)
    makeQuick("None", function() setFromTier(999, true); refreshChips() end)
    makeQuick("≥Epic", function() setFromTier(4); refreshChips() end)
    makeQuick("≥Leg", function() setFromTier(5); refreshChips() end)
    makeQuick("≥Secret", function() setFromTier(8); refreshChips() end)
end
refreshChips()

-- stats + log
local statsLabel = new("TextLabel", {
    Text = "Bawa: 0 • Klaim: 0 • Gagal: 0",
    Font = Enum.Font.Gotham, TextSize = 11,
    TextColor3 = Color3.fromRGB(148, 152, 168), BackgroundTransparency = 1,
    Position = UDim2.new(0, 2, 1, -46), Size = UDim2.new(1, 0, 0, 16),
    TextXAlignment = Enum.TextXAlignment.Left,
}, body)
local logLabel = new("TextLabel", {
    Text = "",
    Font = Enum.Font.Gotham, TextSize = 10,
    TextColor3 = Color3.fromRGB(126, 130, 146), BackgroundTransparency = 1,
    Position = UDim2.new(0, 2, 1, -28), Size = UDim2.new(1, 0, 0, 28),
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
}, body)

local function setStatus(t)
    if alive and statusText.Text ~= "Status: " .. t then
        statusText.Text = "Status: " .. t
        debugLog("status.change", {text = t}, "INFO", 0.2)
        if uiHooks.status then uiHooks.status(t) end
    end
end
local function refreshStats()
    statsLabel.Text = string.format("Bawa: %d • Klaim: %d • Gagal: %d", State.stolen, State.claimed, State.failed)
    if uiHooks.stats then uiHooks.stats(statsLabel.Text) end
end
local function addLog(t)
    table.insert(State.log, 1, t)
    while #State.log > 3 do table.remove(State.log) end
    logLabel.Text = table.concat(State.log, "\n")
    if uiHooks.log then uiHooks.log(logLabel.Text) end
end

-- Tombol darurat TERPISAH (ScreenGui sendiri): tetap ada walau window utama
-- di-minimize/di-hidden — satu klik menampilkan lagi UI + window WindUI.
-- Ini pengganti RightControl yang tidak selalu sampai ke Roblox.
miniGui = new("ScreenGui", {
    Name = "AutoStealEggsMini",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 200,
}, uiParent)
do
    local btn = new("TextButton", {
        Name = "Open", Text = "STEAL", Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = Color3.fromRGB(255, 255, 255), BackgroundColor3 = Color3.fromRGB(46, 125, 60),
        BorderSizePixel = 0, Size = UDim2.fromOffset(64, 32), Position = UDim2.new(1, -72, 1, -120),
    }, miniGui)
    new("UICorner", {CornerRadius = UDim.new(0, 8)}, btn)
    connect(btn.MouseButton1Click, function()
        main.Visible = true
        gui.Enabled = true
        if windWindow then
            pcall(function() windWindow:Open() end)
        end
        addLog("UI dibuka lagi (tombol STEAL).")
    end)
end

-- STICKY TAKEOVER: file lama yang dieksekusi SETELAH versi ini tidak boleh
-- hidup berdampingan. Tiap 5 detik: hancurkan AutoStealEggsUI lain, mini
-- lain, dan container window lain. Rival mati lewat handler Destroying-nya
-- sendiri (semua versi punya); rival se-versi kalah lewat epoch.
-- Handle window milik sendiri (disimpan segera setelah CreateWindow) dilewati.
local function killRivals()
    local ours = rawget(_G, "AutoStealEggsWindUI")
    local killed = 0
    local function scan(parent)
        if not parent then return end
        for _, child in ipairs(parent:GetChildren()) do
            if child ~= gui and child ~= miniGui and child ~= ours and child:IsA("ScreenGui") then
                local rival = child.Name == "AutoStealEggsUI" or child.Name == "AutoStealEggsMini"
                if not rival then
                    for _, d in ipairs(child:GetDescendants()) do
                        if (d:IsA("TextLabel") or d:IsA("TextButton")) and type(d.Text) == "string"
                            and d.Text:find(WINDOW_TITLE, 1, true) then
                            rival = true
                            break
                        end
                    end
                end
                if rival then
                    if pcall(function() child:Destroy() end) then killed += 1 end
                end
            end
        end
    end
    local ok, coreGui = pcall(function() return game:GetService("CoreGui") end)
    scan(ok and coreGui or nil)
    scan(LP:FindFirstChild("PlayerGui"))
    if killed > 0 then debugLog("instance.takeover", {killed = killed}, "WARN") end
end
-- Cleanup happens at takeover, never periodically: an older session must
-- not destroy the newly executing session's window.

-- minimize + drag
local minimized = false
connect(minBtn.MouseButton1Click, function()
    minimized = not minimized
    body.Visible = not minimized
    TweenService:Create(main, TweenInfo.new(0.2), {
        Size = minimized and UDim2.fromOffset(310, 44) or UDim2.fromOffset(310, 540),
    }):Play()
end)
do
    local dragging, dragStart, startPos
    connect(header.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, main.Position
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

--==============================================================
-- SPEED CONTROLS: horizontal physics boost; game WalkSpeed stays untouched.
--==============================================================
local Speed = {multiplier = 1, selected = 1, reason = "belum dipilih", humanoid = nil, root = nil, applied = nil, goal = nil, rejected = false}
local function releaseSpeed(reason)
    if Speed.force then Speed.force:Destroy() end
    if Speed.attachment then Speed.attachment:Destroy() end
    -- Return control to the Humanoid without an artificial horizontal stop.
    -- This also preserves game knockback when a force is removed mid-transition.
    Speed.humanoid, Speed.root, Speed.applied, Speed.force, Speed.attachment = nil, nil, nil, nil, nil
    Speed.mode, Speed.target = nil, nil
    Speed.multiplier = 1
    Speed.moving = false
    Speed.reason = reason or "dimatikan"
    Speed.sample = nil
end
local function waypointNeedsBraking(points, index, from, destination, arrivalRadius)
    local waypoint = points[index]
    if not waypoint then return true end
    local nextWaypoint = points[index + 1]
    if waypoint.Action == Enum.PathWaypointAction.Jump
        or (nextWaypoint and nextWaypoint.Action == Enum.PathWaypointAction.Jump) then return true end
    local incoming = Vector3.new(waypoint.Position.X - from.X, 0, waypoint.Position.Z - from.Z)
    local onward = nextWaypoint and nextWaypoint.Position or destination
    local outgoing = Vector3.new(onward.X - waypoint.Position.X, 0, onward.Z - waypoint.Position.Z)
    if incoming.Magnitude < 0.05 or outgoing.Magnitude <= (nextWaypoint and 0.05 or arrivalRadius) then return true end
    -- Straight intermediate points (including the end of a local path horizon)
    -- do not require a stop. Tight corners, jumps and the actual destination do.
    return incoming.Unit:Dot(outgoing.Unit) < 0.94
end
local function requestSpeed(multiplier)
    releaseSpeed(multiplier <= 1 and "dimatikan pengguna" or "menunggu karakter siap; pilih ulang boost")
    Speed.selected = multiplier
    Speed.correction = nil
    Speed.rejected = false
    if multiplier <= 1 then
        debugLog("speed.mode", {selected = multiplier, active = Speed.multiplier, reason = Speed.reason})
        if Delivery then Delivery:onSpeed(multiplier, Speed.multiplier, Speed.reason) end
        return
    end
    local root, h = getRig()
    if not root or not h or h.Health <= 0 then return end
    if multiplier >= 100 then
        Speed.mode = "cframe"
        Speed.target = math.clamp(multiplier, 100, 1000)
        Speed.root, Speed.humanoid = root, h
        Speed.multiplier = Speed.target / math.max(h.WalkSpeed, 1)
        Speed.applied = Speed.target
        Speed.reason = nil
        debugLog("speed.cframe-request", {target=Speed.target, gameSpeed=h.WalkSpeed})
        if Delivery then Delivery:onSpeed(multiplier, Speed.multiplier, "CFrame step") end
        return
    end
    local attachment = Instance.new("Attachment")
    attachment.Name = "ASESpeedAttachment"
    attachment.Parent = root
    local force = Instance.new("LinearVelocity")
    force.Name = "ASESpeedVelocity"
    force.Attachment0 = attachment
    force.RelativeTo = Enum.ActuatorRelativeTo.World
    force.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
    force.PrimaryTangentAxis = Vector3.new(1, 0, 0)
    force.SecondaryTangentAxis = Vector3.new(0, 0, 1)
    force.PlaneVelocity = Vector2.zero
    force.ForceLimitsEnabled = false
    force.Enabled = false
    force.Parent = root
    Speed.multiplier, Speed.humanoid, Speed.root = multiplier, h, root
    Speed.attachment, Speed.force = attachment, force
    Speed.applied = math.min(h.WalkSpeed * multiplier, 400)
    Speed.reason = nil
    debugLog("speed.physics-request", {gameSpeed = h.WalkSpeed, target = Speed.applied, multiplier = multiplier})
    if Delivery then Delivery:onSpeed(multiplier, Speed.multiplier, Speed.reason) end
end
local function observeSpeedCorrection(root, direction, speed, now)
    local previous = Speed.sample
    Speed.sample = {root = root, pos = root.Position, direction = direction, speed = speed, at = now}
    if not previous or previous.root ~= root then return false end
    local dt = now - previous.at
    if dt <= 0 or dt > 0.25 then return false end
    local a, b = previous.direction, direction
    if a.Magnitude < 0.05 or b.Magnitude < 0.05 or a.Unit:Dot(b.Unit) < 0.8 then return false end
    local back = (previous.pos - root.Position):Dot(a.Unit)
    local threshold = math.max(20, 3 * previous.speed * dt)
    if back <= threshold then return false end
    releaseSpeed("koreksi posisi terdeteksi; memakai speed game")
    Speed.rejected = true
    Speed.correction = {at = now, root = root, pos = root.Position, stableSince = now}
    debugLog("speed.correction", {back = back, threshold = threshold, dt = dt, selected = Speed.selected}, "WARN")
    return true
end
local function updateSpeedPhysics()
    local force, root, h = Speed.force, Speed.root, Speed.humanoid
    if not force then return end
    local currentRoot, currentHumanoid = getRig()
    if not force.Parent or not root.Parent or h ~= currentHumanoid or root ~= currentRoot or h.Health <= 0 then
        releaseSpeed("karakter berubah; pilih ulang boost")
        return
    end
    local movementState = tostring(h:GetState())
    local uncontrolled = movementState == "Enum.HumanoidStateType.Physics"
        or movementState == "Enum.HumanoidStateType.Ragdoll"
        or movementState == "Enum.HumanoidStateType.FallingDown"
        or movementState == "Enum.HumanoidStateType.GettingUp"
    if root.Anchored or h.Sit or h.PlatformStand or uncontrolled then
        force.Enabled = false
        Speed.moving = false
        Speed.sample = nil
        return
    end
    local direction, distance = h.MoveDirection, nil
    if State.running then
        if Speed.goal then
            local offset = Speed.goal - root.Position
            direction = Vector3.new(offset.X, 0, offset.Z)
            distance = direction.Magnitude
        else
            direction = Vector3.zero
        end
    end
    local flat = Vector3.new(direction.X, 0, direction.Z)
    if flat.Magnitude < 0.05 then
        force.Enabled = false
        Speed.moving = false
        Speed.sample = nil
        return
    end
    local target = math.min(h.WalkSpeed * Speed.multiplier, 400)
    -- Slow only at a corner/jump/final goal, never at a straight transit point.
    if distance and Speed.brakeAtGoal ~= false then
        target = math.min(target, math.max(0, distance - (Speed.goalRadius or 1.5)) * 8)
    end
    if movementState == "Enum.HumanoidStateType.Running" or movementState == "Enum.HumanoidStateType.Landed" then
        if observeSpeedCorrection(root, flat, target, os.clock()) then return end
    else
        Speed.sample = nil
    end
    Speed.applied = target
    force.PlaneVelocity = Vector2.new(flat.Unit.X * target, flat.Unit.Z * target)
    force.Enabled = true
    Speed.moving = true
end
function Speed.step(dt)
    if Speed.mode ~= "cframe" then return end
    local root, hum = getRig()
    if root ~= Speed.root or hum ~= Speed.humanoid or not hum or hum.Health <= 0 then
        releaseSpeed("karakter berubah; pilih ulang speed")
        return
    end
    if os.clock() < claimMovementSettleUntil then
        Speed.sample, Speed.moving = nil, false
        if State.running then hum:Move(Vector3.zero, false) end
        return
    end
    local state = hum:GetState()
    if root.Anchored or hum.Sit or hum.PlatformStand or root.Parent:GetAttribute("IsTrapped")
        or state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.Ragdoll
        or state == Enum.HumanoidStateType.FallingDown or state == Enum.HumanoidStateType.GettingUp then
        Speed.sample, Speed.moving = nil, false
        return
    end
    if dt <= 0 or dt > 0.25 then Speed.sample=nil; return end
    -- MoveTo was used by the previous route/mode. Cancel that actuator before
    -- applying a positional step, otherwise native walking adds to the step.
    if State.running then hum:Move(Vector3.zero, false) end
    local from = root.Position
    local offset = State.running and Speed.goal and (Speed.goal - from) or nil
    local direction = State.running and (offset or Vector3.zero) or hum.MoveDirection
    local flat = Vector3.new(direction.X, 0, direction.Z)
    if flat.Magnitude < 0.05 then Speed.sample=nil; Speed.moving=false; return end
    local target = Speed.target
    Speed.multiplier = target / math.max(hum.WalkSpeed, 1)
    if observeSpeedCorrection(root, flat, target, os.clock()) then return end
    local distance = offset and math.max(0, flat.Magnitude - (Speed.goalRadius or 1.5)) or math.huge
    local step = math.min(target * dt, distance)
    if step <= 0 then Speed.moving=false; return end
    local delta = flat.Unit * step
    local goal = from + delta
    -- Preserve vertical physics/jumps; only port the horizontal motion mechanism.
    root.CFrame = CFrame.lookAt(goal, goal + flat.Unit)
    local velocity = root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
    Speed.applied, Speed.moving = target, true
    debugLog("speed.cframe-step", {target=target, step=step, dt=dt, position=goal}, nil, 1)
end
connect(game:GetService("RunService").Heartbeat, Speed.step)

local speedLabel = new("TextLabel", {
    Name = "SpeedReadout", Text = "Kecepatan: menunggu karakter…",
    Font = Enum.Font.Gotham, TextSize = 11,
    TextColor3 = Color3.fromRGB(178, 219, 204), BackgroundTransparency = 1,
    Position = UDim2.fromOffset(2, 328), Size = UDim2.new(1, -4, 0, 31),
    TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
}, body)
local speedButtons = {}
for i, multiplier in ipairs({1, 200, 300, 400, 600, 800, 1000}) do
    local b = new("TextButton", {
        Name = "Speed" .. tostring(multiplier), Text = multiplier == 1 and "GAME SPEED" or tostring(multiplier) .. " stud/s",
        Font = Enum.Font.GothamBold, TextSize = 10,
        TextColor3 = Color3.fromRGB(231, 237, 244), BackgroundColor3 = Color3.fromRGB(40, 65, 60),
        Position = UDim2.new(((i - 1) % 4) / 4, 0, 0, 361 + math.floor((i - 1) / 4) * 30),
        Size = UDim2.new(1 / 4, -4, 0, 26), BorderSizePixel = 0,
    }, body)
    new("UICorner", {CornerRadius = UDim.new(0, 6)}, b)
    speedButtons[multiplier] = b
    connect(b.MouseButton1Click, function()
        requestSpeed(multiplier)
        addLog(multiplier == 1 and "Boost dimatikan." or "CFrame speed " .. tostring(multiplier) .. " stud/s dipilih.")
    end)
end
connect(gui.Destroying, releaseSpeed)
connect(LP.CharacterRemoving, function() releaseSpeed("respawn; pilih ulang boost") end)
connect(game:GetService("RunService").PreSimulation, updateSpeedPhysics)
local speedControl = new("BindableFunction", {Name = "SpeedControl"}, gui)
speedControl.OnInvoke = function(multiplier)
    if not table.find({1, 1.1, 1.2, 1.3, 1.4, 1.5, 2, 100, 200, 300, 400, 500, 600, 800, 1000}, multiplier) then
        return {ok = false, reason = "pilih 1 (game) atau 100–1000 dari preset"}
    end
    requestSpeed(multiplier)
    return {ok = multiplier == 1 or Speed.force ~= nil or Speed.mode == "cframe", multiplier = Speed.multiplier, requested = Speed.applied}
end
task.spawn(function()
    while alive do
        local root, h = getRig()
        if h then
            local velocity = root and root.AssemblyLinearVelocity
            local actual = 0
            local now = os.clock()
            local previous = Speed.readoutSample
            if root and previous and previous.root == root and now > previous.at then
                local delta=root.Position-previous.position
                actual=Vector2.new(delta.X,delta.Z).Magnitude/(now-previous.at)
            end
            Speed.readoutSample=root and {root=root,position=root.Position,at=now} or nil
            speedLabel.Text = string.format("Gerak nyata %.0f stud/s | speed game %.0f\n%s", actual, h.WalkSpeed,
                Speed.mode == "cframe" and string.format("CFrame ON • target %.0f stud/s", Speed.target) or Speed.force and string.format("Boost fisika %.1fx • target maksimal %.0f", Speed.multiplier, math.min(h.WalkSpeed * Speed.multiplier, 400))
                or ("Boost OFF • " .. tostring(Speed.reason) .. " • pilihan " .. tostring(Speed.selected) .. (Speed.selected >= 100 and " stud/s" or "x")))
            gui:SetAttribute("WalkSpeed", h.WalkSpeed)
            gui:SetAttribute("MovementSpeed", actual)
            gui:SetAttribute("SpeedMultiplier", Speed.multiplier)
            gui:SetAttribute("SpeedMethod", Speed.mode or (Speed.force and "physics" or "game"))
            gui:SetAttribute("SpeedStopReason", Speed.reason)
            gui:SetAttribute("SpeedSelected", Speed.selected)
            gui:SetAttribute("SpeedTarget", Speed.target)
            if uiHooks.speed then uiHooks.speed(speedLabel.Text, Speed.multiplier) end
        end
        for multiplier, button in pairs(speedButtons) do
            button.BackgroundColor3 = ((Speed.mode == "cframe" and Speed.target == multiplier) or (not Speed.mode and Speed.multiplier == multiplier)) and Color3.fromRGB(46, 127, 94) or Color3.fromRGB(40, 44, 54)
        end
        task.wait(0.25)
    end
end)

--==============================================================
-- CORE
--==============================================================
local function setRunning(on)
    debugLog("toggle.request", {requested = on, snapshot = snapshot()})
    if on then
        if not resolveAutoBase() then
            requestBaseSnapshot()
            setStatus("base belum tersedia/ter-load; menunggu data kepemilikan game (B: cek ulang)")
            return
        end
        local hrp, hum = getRig()
        if hrp and hrp.Anchored then
            setStatus("GERAK DIKUNCI GAME. Keluar treadmill / tekan WASD, lalu ON lagi.")
            return
        end
    end
    generation += 1
    if not on then releaseSpeed("otomatisasi OFF") end
    State.running = on
    if cancelNavigation then pcall(cancelNavigation); cancelNavigation = nil end
    debugPhase = on and "scanning" or "idle"
    State.consecutiveFails = 0
    toggleBtn.Text = on and "AUTO STEAL: ON" or "AUTO STEAL: OFF"
    TweenService:Create(toggleBtn, TweenInfo.new(0.25), {
        BackgroundColor3 = on and Color3.fromRGB(58, 196, 118) or Color3.fromRGB(66, 70, 88),
    }):Play()
    if uiHooks.toggle then uiHooks.toggle(on) end
    Worker.retryAt = nil
    if on and ensureWorker then Worker.error = nil; ensureWorker() end
    if on then
        setStatus("mencari telur...")
        addLog("• start (filter " .. (function()
            local n = 0
            for _, v in pairs(State.selected) do if v then n += 1 end end
            return n
        end)() .. " tier)")
    else
        local hrp, hum = getRig()
        if hrp and hum then hum:MoveTo(hrp.Position) end
        setStatus("idle")
    end
end

connect(toggleBtn.MouseButton1Click, function() setRunning(not State.running) end)
local function refreshBase()
    requestBaseSnapshot()
    if resolveAutoBase() then
        addLog("Base otomatis: plot " .. State.homePlot)
        setStatus("base otomatis plot " .. State.homePlot .. "; RightShift untuk mulai")
    else
        setStatus("menunggu base ter-load / data Homestead; tidak memilih plot sembarang")
    end
end
makeQuick("AutoBase", refreshBase).Size = UDim2.fromOffset(50, 22)
-- Six quick buttons fit in the row without spilling outside the panel.
for _, button in ipairs(quickRow:GetChildren()) do
    if button:IsA("TextButton") then button.Size = UDim2.fromOffset(44, 22) end
end
connect(UserInputService.InputBegan, function(input, gpe)
    if gpe then return end
    if input.KeyCode == CONFIG.toggleKey then setRunning(not State.running) end
    if input.KeyCode == CONFIG.refreshBaseKey then refreshBase() end
end)

local returnContext, pendingPickup = nil, nil
local function retryWait(token, reason, seconds)
    debugPhase = "retry-wait"
    setStatus("ON • " .. reason .. string.format(" • coba lagi %.0f dtk", seconds))
    debugLog("retry.wait", {reason = reason, seconds = seconds}, "WARN", 2)
    return waitActive(seconds, token)
end
local function navigationParams(character)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    params.RespectCanCollide = true
    return params
end
local function navigationObstructed(from, destination, character, speed)
    local direction = Vector3.new(destination.X - from.X, 0, destination.Z - from.Z)
    if direction.Magnitude < 1 then return false end
    -- Dinding guard ("GUARD NO COLLIDE") solid buat pemain tapi diabaikan navmesh;
    -- lorong jalan juga cuma ~1 stud dari dinding. Probing 3.5-lebar/84-panjang
    -- menandai lorong bersih terus-menerus dan karakter nge-freeze di depan dinding.
    local length = math.min(direction.Magnitude, math.clamp((speed or 16) * 0.12 + 6, 10, CONFIG.obstacleAhead))
    return Workspace:Blockcast(CFrame.new(from), Vector3.new(CONFIG.obstacleBox, 4, CONFIG.obstacleBox),
        direction.Unit * length, navigationParams(character)) ~= nil
end
-- Merge near-collinear road waypoints into long straight centreline runs so the
-- runner stops zig-zagging around navmesh graph jitter ("belok-belok" lambat
-- dan lekas diketahui guard). Jump waypoints and tight corners stay untouched.
local function distanceFromSegment(a, b, p)
    local abx, abz = b.X - a.X, b.Z - a.Z
    local apx, apz = p.X - a.X, p.Z - a.Z
    local length2 = abx * abx + abz * abz
    if length2 < 0.01 then
        return apx * apx + apz * apz
    end
    local t = math.clamp((apx * abx + apz * abz) / length2, 0, 1)
    local dx, dz = apx - abx * t, apz - abz * t
    return dx * dx + dz * dz
end
local function simplifyRoute(points)
    if #points < 3 then return points end
    local tolerance2 = CONFIG.simplifyTolerance * CONFIG.simplifyTolerance
    local simplified = {points[1]}
    local anchor = 1
    while anchor < #points do
        local furthest = anchor + 1
        local probe = anchor + 2
        while probe <= #points and points[probe].Action ~= Enum.PathWaypointAction.Jump do
            local straight = true
            for k = anchor + 1, probe - 1 do
                if points[k].Action == Enum.PathWaypointAction.Jump
                    or distanceFromSegment(points[anchor].Position, points[probe].Position, points[k].Position) > tolerance2 then
                    straight = false
                    break
                end
            end
            if not straight then break end
            furthest = probe
            probe += 1
        end
        table.insert(simplified, points[furthest])
        anchor = furthest
    end
    if #simplified < #points then
        debugLog("navigation.simplify", {original = #points, simplified = #simplified})
    end
    return simplified
end
local function navigationRoute(from, destination, character, horizon)
    local direction = Vector3.new(destination.X - from.X, 0, destination.Z - from.Z)
    local endpoint = destination
    local maxLeg = horizon or CONFIG.pathHorizon
    if direction.Magnitude > maxLeg then
        endpoint = from + direction.Unit * maxLeg
    end
    -- SpawnPoint is elevated; pathfind to the floor rather than a point in the air.
    local ground = Workspace:Raycast(endpoint + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), navigationParams(character))
    if ground then endpoint = ground.Position end
    local path = game:GetService("PathfindingService"):CreatePath({
        AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6,
    })
    local ok = pcall(function() path:ComputeAsync(from, endpoint) end)
    if ok and path.Status == Enum.PathStatus.Success then
        local points = path:GetWaypoints()
        if #points > 0 then return {points = simplifyRoute(points), path = path} end
    end
    return false
end
-- TREADMILL GEOMETRY: read trigger footprints; never modify game parts.
local function insideTreadmill(point, rect)
    return point.X > rect.x0 and point.X < rect.x1 and point.Z > rect.z0 and point.Z < rect.z1
end
local function segmentHitsTreadmill(a, b, rect)
    local lo, hi = 0, 1
    for _, axis in ipairs({{"X", rect.x0, rect.x1}, {"Z", rect.z0, rect.z1}}) do
        local origin, delta = a[axis[1]], b[axis[1]] - a[axis[1]]
        if math.abs(delta) < 0.0001 then
            if origin < axis[2] or origin > axis[3] then return false end
        else
            local near, far = (axis[2] - origin) / delta, (axis[3] - origin) / delta
            if near > far then near, far = far, near end
            lo, hi = math.max(lo, near), math.min(hi, far)
            if lo > hi then return false end
        end
    end
    return true
end
-- Aim points that land inside a padded footprint are clamped out; otherwise a
-- shifted centre-aim would grind the character against the treadmill side.
local function pushOutsidePadding(point, regions)
    for _, rect in ipairs(regions) do
        if insideTreadmill(point, rect) then
            local dx0, dx1 = point.X - rect.x0, rect.x1 - point.X
            local dz0, dz1 = point.Z - rect.z0, rect.z1 - point.Z
            local edge = math.min(dx0, dx1, dz0, dz1)
            local x, z = point.X, point.Z
            if edge == dx0 then x = rect.x0 - 1
            elseif edge == dx1 then x = rect.x1 + 1
            elseif edge == dz0 then z = rect.z0 - 1
            else z = rect.z1 + 1 end
            point = Vector3.new(x, point.Y, z)
        end
    end
    return point
end
local treadmillCache, treadmillCacheAt = {}, -math.huge
local treadmillLoggedCount = -1
local function treadmillRegions()
    if not CONFIG.avoidTreadmills or type(Workspace.FindFirstChild) ~= "function" then return {} end
    if os.clock() - treadmillCacheAt < 1 then return treadmillCache end
    treadmillCache, treadmillCacheAt = {}, os.clock()
    local plots = Workspace:FindFirstChild("Plots")
    for _, plot in ipairs(plots and plots:GetChildren() or {}) do
        local bottom = plot:FindFirstChild("TreadmillBottom")
        if bottom and bottom:IsA("BasePart") then
            local cf, size, p = bottom.CFrame, bottom.Size, bottom.Position
            local x = (math.abs(cf.RightVector.X) * size.X + math.abs(cf.LookVector.X) * size.Z) * 0.5
            local z = (math.abs(cf.RightVector.Z) * size.X + math.abs(cf.LookVector.Z) * size.Z) * 0.5
            local pad = CONFIG.treadmillPadding
            table.insert(treadmillCache, {x0=p.X-x-pad, x1=p.X+x+pad, z0=p.Z-z-pad, z1=p.Z+z+pad,
                floorY=p.Y, name=plot.Name})
        end
    end
    if #treadmillCache ~= treadmillLoggedCount then
        treadmillLoggedCount = #treadmillCache
        debugLog("treadmill.regions", {count = #treadmillCache})
    end
    return treadmillCache
end
local function planTreadmillDetour(origin, goal, regions, gap)
    if #regions == 0 then return {goal} end
    local function clear(a, b, allowExit)
        for _, rect in ipairs(regions) do
            if not (allowExit and insideTreadmill(a, rect)) and segmentHitsTreadmill(a, b, rect) then return false end
        end
        return true
    end
    for _, rect in ipairs(regions) do
        if insideTreadmill(goal, rect) then return nil end
    end
    if clear(origin, goal, true) then return {goal} end
    -- Small visibility graph: corners of measured, expanded footprints.
    local nodes = {origin, goal}
    for _, rect in ipairs(regions) do
        for _, x in ipairs({rect.x0-gap, rect.x1+gap}) do
            for _, z in ipairs({rect.z0-gap, rect.z1+gap}) do
                local point, blocked = Vector3.new(x, origin.Y, z), false
                for _, other in ipairs(regions) do if insideTreadmill(point, other) then blocked = true; break end end
                if not blocked then table.insert(nodes, point) end
            end
        end
    end
    local distance, previous, visited = {[1]=0}, {}, {}
    for _ = 1, #nodes do
        local index, best = nil, math.huge
        for i = 1, #nodes do
            if not visited[i] and (distance[i] or math.huge) < best then index, best = i, distance[i] end
        end
        if not index then return nil end
        if index == 2 then
            local path, at = {}, 2
            while at ~= 1 do table.insert(path, 1, nodes[at]); at = previous[at] end
            return path
        end
        visited[index] = true
        for j, point in ipairs(nodes) do
            if not visited[j] and clear(nodes[index], point, index == 1) then
                local dx, dz = point.X-nodes[index].X, point.Z-nodes[index].Z
                local nextDistance = best + math.sqrt(dx*dx+dz*dz)
                if nextDistance < (distance[j] or math.huge) then distance[j], previous[j] = nextDistance, index end
            end
        end
    end
    return nil
end
-- TREADMILL RECOVERY: the game's TreadmillUIController exits via JumpRequest →
-- Remotes.Treadmill.AskDoff. Send the same Space input a player would press,
-- only when the belt is confirmed or the locked position is on a footprint.
local Treadmill = {assigned=false, nextExit=0, attempts=0, windowStart=0}
local treadmillFeed = networking and networking:FindFirstChild("RE/Treadmill/AssignedBeltShifted")
if treadmillFeed and treadmillFeed:IsA("RemoteEvent") then
    connect(treadmillFeed.OnClientEvent, function(id)
        Treadmill.assigned = id ~= nil
        if id == nil then Treadmill.nextExit, Treadmill.attempts = 0, 0 end
    end)
end
debugLog("treadmill.feed", {found = treadmillFeed ~= nil})
local function tryExitTreadmill(root, hum, token)
    if not CONFIG.autoTreadmillExit or not active(token) then return false end
    local confirmed = Treadmill.assigned
    if not confirmed and root.Anchored then
        for _, rect in ipairs(treadmillRegions()) do
            if insideTreadmill(root.Position, rect) and root.Position.Y >= rect.floorY
                and root.Position.Y - rect.floorY <= 10 then confirmed = true; break end
        end
    end
    if not confirmed then Treadmill.attempts = 0; return false end
    if os.clock() - Treadmill.windowStart > 5 then
        Treadmill.attempts, Treadmill.windowStart = 0, os.clock()
    end
    if os.clock() < Treadmill.nextExit or Treadmill.attempts >= 3 then return true end
    Treadmill.nextExit, Treadmill.attempts = os.clock() + 1.5, Treadmill.attempts + 1
    local focused = false
    pcall(function() focused = UserInputService:GetFocusedTextBox() ~= nil end)
    if focused then return true end -- never leak a keystroke into chat
    local ok, err = pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.spawn(function()
            task.wait(0.06)
            pcall(function() vim:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
        end)
    end)
    -- Natural jump signal too; harmless when the game only reads JumpRequest.
    pcall(function() hum.Jump = true end)
    debugLog("treadmill.exit-input", {ok = ok, error = not ok and tostring(err) or nil,
        attempt = Treadmill.attempts, pos = root.Position}, ok and "INFO" or "WARN")
    return true
end
local function moveRawLeg(pos, timeout, token, target, arrivalRadius, transit)
    arrivalRadius = arrivalRadius or CONFIG.activationDistance
    local hrp, hum = getRig()
    if not hrp or not hum then return false, "no char" end
    if not target then
        -- Kaki tanpa prompt (pulang/base): radius minimal = jarak tempuh per tick.
        -- Pada 2x satu tick = 9.6 stud > radius 3 → karakter melompati lingkaran
        -- tiba lalu muter balik dan osilasi ("reset/balik" saat boost). Radius
        -- dinamis menangkap kedatangan dalam satu langkah maju.
        arrivalRadius = math.max(arrivalRadius, math.clamp(hum.WalkSpeed * CONFIG.moveInterval * 0.75, 3, 14))
    end
    local function commandMove(destination, brakeAtGoal, goalRadius)
        local regions = treadmillRegions()
        local safe = planTreadmillDetour(hrp.Position, destination, regions, CONFIG.treadmillCornerGap or 16)
        if not safe then
            -- Aim landed inside a footprint (centre-shift drift): clamp to the
            -- nearest edge instead of standing still against the treadmill.
            destination = pushOutsidePadding(destination, regions)
            safe = planTreadmillDetour(hrp.Position, destination, regions, CONFIG.treadmillCornerGap or 16)
        end
        if not safe then
            destination = hrp.Position
        elseif #safe > 1 then
            destination, brakeAtGoal, goalRadius = safe[1], true, 3
        end
        Speed.goal = destination
        Speed.brakeAtGoal = brakeAtGoal ~= false
        Speed.goalRadius = goalRadius or 1.5
        if Speed.mode == "cframe" then
            hum:Move(Vector3.zero, false)
        else
            hum:MoveTo(destination)
        end
    end
    local function centerTarget(destination)
        -- "PAKSA di jalur": bidikan ABSOLUT di sumbu dunia. Leg jalan di map
        -- ini hampir selalu sumbu X atau Z; ray sisi dipancarkan tegak lurus
        -- SUMBU dominan leg (bukan tegak lurus leg diagonal), lalu lintang
        -- bidikan (koordinat di sumbu itu) di-clamp ke garis keep dari dinding.
        -- Temuan live: dinding utara z≈-295 + waypoint rute menempel dinding
        -- (z≈-290) — clamp ini memaksa jalur lari sejajar di jarak aman,
        -- tidak lagi terseret waypoint ke tembok (serong + scrape + nyendat).
        local origin = hrp.Position
        local dx, dz = destination.X - origin.X, destination.Z - origin.Z
        local flat = dx * dx + dz * dz
        if flat < 400 then return destination end -- dekat tujuan: biar presisi
        local len = math.sqrt(flat)
        local nx, nz = dx / len, dz / len
        local vx, vz
        if math.abs(nx) >= math.abs(nz) then
            vx, vz = 0, 1 -- leg dominan X → periksa dinding di sumbu Z
        else
            vx, vz = 1, 0 -- leg dominan Z → periksa dinding di sumbu X
        end
        local params = navigationParams(hrp.Parent)
        local hitPlus = Workspace:Raycast(origin, Vector3.new(vx, 0, vz) * CONFIG.centerProbe, params)
        local hitMinus = Workspace:Raycast(origin, Vector3.new(-vx, 0, -vz) * CONFIG.centerProbe, params)
        if not hitPlus and not hitMinus then return destination end
        local keep = CONFIG.centerKeep
        local destLat = dx * vx + dz * vz
        local targetLat
        if hitPlus and hitMinus then
            local dPlus = (hitPlus.Position - origin).Magnitude
            local dMinus = (hitMinus.Position - origin).Magnitude
            local hi, lo = dPlus - keep, -dMinus + keep
            if hi < lo then
                targetLat = (dPlus - dMinus) * 0.5 -- koridor lebih sempit dari 2x keep
            else
                targetLat = math.clamp(destLat, lo, hi)
            end
        elseif hitPlus then
            targetLat = math.min(destLat, (hitPlus.Position - origin).Magnitude - keep)
        else
            targetLat = math.max(destLat, -((hitMinus.Position - origin).Magnitude - keep))
        end
        local shift = targetLat - destLat
        if math.abs(shift) < CONFIG.centerDeadZone then return destination end
        if shift > CONFIG.centerMaxShift then shift = CONFIG.centerMaxShift end
        if shift < -CONFIG.centerMaxShift then shift = -CONFIG.centerMaxShift end
        debugLog("navigation.center", {shift = shift, targetLat = targetLat, destLat = destLat, snapshot = snapshot()}, nil, 0.5)
        return destination + Vector3.new(vx, 0, vz) * shift
    end
    local t0 = os.clock()
    local nextProgressLog = t0
    local route, routeIndex, routing, routeBlocked = nil, 2, false, false
    local nextRouteCheck, nextPlanAt, routeSerial, finished = 0, 0, 0, false
    local blockedConnection, noPathCount, obstructed = nil, 0, false
    local anchorWait, anchorNotified
    local savedSpeed, appliedSpeed
    local function restoreSpeed()
        if savedSpeed and hum.Parent and hum.WalkSpeed == appliedSpeed then hum.WalkSpeed = savedSpeed end
        savedSpeed, appliedSpeed = nil, nil
    end
    local function steeringSpeed()
        if CONFIG.navigationTurnSpeed <= 0 then return end
        if savedSpeed and hum.WalkSpeed ~= appliedSpeed then savedSpeed, appliedSpeed = nil, nil end
        if not savedSpeed and hum.WalkSpeed > CONFIG.navigationTurnSpeed then
            savedSpeed, appliedSpeed = hum.WalkSpeed, CONFIG.navigationTurnSpeed
            hum.WalkSpeed = appliedSpeed
        end
    end
    local function clearRoute()
        if blockedConnection then blockedConnection:Disconnect(); blockedConnection = nil end
        route, routeBlocked = nil, false
    end
    local function cleanupNavigation()
        Speed.goal = nil
        Speed.brakeAtGoal, Speed.goalRadius = nil, nil
        finished = true
        routeSerial += 1
        clearRoute()
        restoreSpeed()
    end
    cancelNavigation = cleanupNavigation
    debugLog("move.start", {goal = pos, radius = arrivalRadius, timeout = timeout, snapshot = snapshot(target)})
    local function finish(ok, reason)
        cleanupNavigation()
        if cancelNavigation == cleanupNavigation then cancelNavigation = nil end
        if active(token) and hum.Parent and hrp.Parent and not (ok and transit) then hum:MoveTo(hrp.Position) end
        debugLog("move.finish", {ok = ok, reason = reason or "arrived", elapsed = os.clock() - t0, goal = pos, snapshot = snapshot(target)})
        return ok, reason
    end
    local lastPos, lastMove = hrp.Position, os.clock()
    local prevTick, lastTickSpeed = hrp.Position, hum.WalkSpeed
    local function requestRoute()
        if routing or os.clock() < nextPlanAt then return end
        routing = true
        routeSerial += 1
        local serial, origin = routeSerial, hrp.Position
        local horizon = target and CONFIG.pathHorizon or CONFIG.returnPathHorizon
        task.spawn(function()
            local ok, result = pcall(navigationRoute, origin, pos, hrp.Parent, horizon)
            if finished or not active(token) or serial ~= routeSerial then return end
            routing = false
            nextPlanAt = os.clock() + 0.5
            if ok and result then
                clearRoute()
                -- Lewati titik-titik proyeksi di belakang posisi (kalau ada) sebelum
                -- mulai mengikuti rute, supaya rute baru tidak mengajak mundur dulu.
                local idx = #result.points > 1 and 2 or 1
                local toGoal = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z)
                if toGoal.Magnitude >= 1 then
                    while idx < #result.points do
                        local candidate = result.points[idx]
                        local toWp = Vector3.new(candidate.Position.X - origin.X, 0, candidate.Position.Z - origin.Z)
                        if toWp.Magnitude > CONFIG.backskipRadius then break end
                        if (toWp.Unit.X * toGoal.Unit.X + toWp.Unit.Z * toGoal.Unit.Z) > -0.2 then break end
                        idx += 1
                    end
                end
                route, routeIndex, noPathCount = result.points, idx, 0
                blockedConnection = result.path.Blocked:Connect(function(index)
                    if not finished and index >= routeIndex then routeBlocked = true end
                end)
                nextRouteCheck = 0
                debugLog("navigation.route", {waypoints = #route, horizon = horizon})
            elseif not ok or result == false then
                noPathCount += 1
                debugLog("navigation.no-path", {error = not ok and tostring(result) or nil}, "WARN", 2)
            end
        end)
    end
    local function goalDistance()
        local offset = hrp.Position - pos
        -- SpawnPoint markers sit above the floor. A return is complete by X/Z,
        -- rather than waiting forever for the root to match the marker's height.
        if not target then return Vector2.new(offset.X, offset.Z).Magnitude end
        return offset.Magnitude
    end
    local function waypointBehind(waypoint)
        -- Rute dari Pathfinding kadang diawali titik proyeksi DI BELAKANG posisi
        -- (misal kita di slab base yang tak punya navmesh). Menjalaninya =
        -- karakter balik badan; dilewati saja, bukan dikejar.
        -- Pada 2x karakter bisa nglampaui titik lebih dari 25 stud — oleh karena
        -- itu follow-time tidak lagi dibatasi radius: titik yang benar-benar di
        -- belakang arah tujuan selalu di-skip, jangan dikejar balik.
        local toWp = Vector3.new(waypoint.Position.X - hrp.Position.X, 0, waypoint.Position.Z - hrp.Position.Z)
        if toWp.Magnitude < 0.05 then return false end
        local toGoal = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
        if toGoal.Magnitude < 1 then return false end
        return (toWp.Unit.X * toGoal.Unit.X + toWp.Unit.Z * toGoal.Unit.Z) < -0.2
    end
    while os.clock() - t0 < timeout do
        if not active(token) or not State.running then return finish(false, "stopped") end
        if Speed.correction then return finish(false, "koreksi posisi") end
        if hum.Health <= 0 or LP.Character ~= hrp.Parent then return finish(false, "karakter berubah") end
        tryExitTreadmill(hrp, hum, token)
        if target and not targetAvailable(target) then
            return finish(false, "target hilang")
        end
        if target and not validateEggRarity(target) then
            return finish(false, "filter berubah")
        end
        if target and not fieldGateOpen() then return finish(false, "gerbang field tutup") end
        if not target then
            -- Perjalanan pulang diselesaikan walau klaim/carry berubah di jalan…
            -- KECUALI kalau telur sudah lepas JAUH dari base: jalan pulang kosong
            -- cuma bikin bolak-balik ke base tanpa hasil. Batal, biar hunting lanjut.
            if returnContext and carryKnown and not carryState and not returnContext.lossNotified then
                returnContext.lossNotified = true
                if claimRevision <= returnContext.revision and goalDistance() > CONFIG.dropAbortDistance then
                    debugLog("return.abort-drop", {uid = returnContext.uid, distance = goalDistance(), snapshot = snapshot()}, "WARN")
                    return finish(false, "carry-drop-jauh")
                end
                setStatus("TELUR LEPAS • tetap menyelesaikan perjalanan ke base")
                debugLog("return.carry-ended-continue", {uid = returnContext.uid, snapshot = snapshot()}, "WARN")
            end
            resolveAutoBase()
            if not State.home or (not transit and (State.home - pos).Magnitude > 1) then return finish(false, "base berubah/belum ter-load") end
        end
        if goalDistance() <= arrivalRadius then
            return finish(true)
        end
        if routeBlocked then clearRoute(); obstructed = true; nextRouteCheck = 0 end
        local waypoint = route and route[routeIndex]
        if waypoint then
            local reachRadius = math.clamp(hum.WalkSpeed * CONFIG.moveInterval * 0.65, 2, 4)
            -- Maju terus: titik yang sudah terlewati ATAU yang letaknya di belakang
            -- (sampai radius backskip) langsung di-skip, bukan dijalani.
            while waypoint do
                local offset = hrp.Position - waypoint.Position
                local flatMag = Vector2.new(offset.X, offset.Z).Magnitude
                if flatMag <= reachRadius then
                    routeIndex += 1
                    waypoint = route[routeIndex]
                    nextRouteCheck = 0
                    if not waypoint then clearRoute() end
                elseif waypointBehind(waypoint) then
                    debugLog("navigation.backskip", {behind = flatMag, goal = pos}, "WARN", 0.4)
                    routeIndex += 1
                    waypoint = route[routeIndex]
                    nextRouteCheck = 0
                    if not waypoint then clearRoute() end
                else
                    break
                end
            end
        end
        -- Follow a visible straight run rather than braking at every 6-stud
        -- intermediate point. Keep jump waypoints and sharp corners intact.
        if waypoint and os.clock() >= nextRouteCheck then
            local lookahead = math.clamp(hum.WalkSpeed * (Speed.multiplier or 1) * 0.18, 16, 70)
            while route and route[routeIndex + 1] do
                local candidate = route[routeIndex + 1]
                if waypoint.Action == Enum.PathWaypointAction.Jump or candidate.Action == Enum.PathWaypointAction.Jump then break end
                local a = Vector3.new(waypoint.Position.X - hrp.Position.X, 0, waypoint.Position.Z - hrp.Position.Z)
                local b = Vector3.new(candidate.Position.X - hrp.Position.X, 0, candidate.Position.Z - hrp.Position.Z)
                if a.Magnitude < 0.1 or b.Magnitude > lookahead then break end
                local alignment = a.Unit.X * b.Unit.X + a.Unit.Z * b.Unit.Z
                if alignment < 0.94 or navigationObstructed(hrp.Position, candidate.Position, hrp.Parent, hum.WalkSpeed) then break end
                routeIndex += 1
                waypoint = candidate
            end
        end
        if os.clock() >= nextRouteCheck then
            nextRouteCheck = os.clock() + CONFIG.routeCheckInterval
            obstructed = navigationObstructed(hrp.Position, waypoint and waypoint.Position or pos, hrp.Parent, hum.WalkSpeed)
        end
        local jumping = waypoint and waypoint.Action == Enum.PathWaypointAction.Jump
        if obstructed and not jumping and os.clock() - lastMove > CONFIG.blockTimeout then
            -- Terhalang di depan DAN benar-benar tidak maju (dinding solid yang
            -- diabaikan navmesh): berhenti dengan alasan, biar caller skip,
            -- bukan berdiri di depan dinding sampai user OFF.
            return finish(false, "terhalang")
        end
        if waypoint then
            steeringSpeed()
            if waypoint.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
            -- Ikuti saja rute hasil pathfinding. Probe tabsrak tidak lagi
            -- menyetop/mengulang rute (itu penyebab stutter stop-and-replan);
            -- seretan dinding diselesaikan oleh jalur stall di bawah, dinding
            -- beneran oleh cek berbatas di atas.
            local brake = waypointNeedsBraking(route, routeIndex, hrp.Position, pos, arrivalRadius)
            commandMove(jumping and waypoint.Position or centerTarget(waypoint.Position), brake)
        elseif routing and not obstructed then
            commandMove(centerTarget(pos), true, arrivalRadius)
        elseif obstructed then
            steeringSpeed()
            commandMove(hrp.Position)
            requestRoute()
            if noPathCount >= 3 then return finish(false, "tidak ada rute aman") end
        else
            restoreSpeed()
            commandMove(centerTarget(pos), true, arrivalRadius)
        end
        if os.clock() >= nextProgressLog then
            debugLog("move.progress", {distance = goalDistance(), goal = pos, snapshot = snapshot(target)})
            nextProgressLog = os.clock() + 1
        end
        if not waitActive(CONFIG.moveInterval, token) then return finish(false, "stopped") end
        local currentRoot, currentHumanoid = getRig()
        if currentRoot ~= hrp or currentHumanoid ~= hum then return finish(false, "karakter berubah") end
        if hrp.Anchored then
            -- Game bisa mengunci gerakan sesaat (run-back wake setelah nyuri telur).
            -- Tunggu sampai terlepas sendiri; hanya berhenti kalau dikunci terlalu lama.
            anchorWait = anchorWait or os.clock()
            lastMove = os.clock()
            if os.clock() - anchorWait > CONFIG.anchorGrace then
                return finish(false, "gerak tetap dikunci game; keluar treadmill / tekan WASD lalu ON lagi")
            end
            if not anchorNotified then
                anchorNotified = true
                setStatus("gerak dikunci game — menunggu terlepas…")
                debugLog("move.anchor-lock", {pos = hrp.Position, goal = pos, snapshot = snapshot(target)}, "WARN")
            end
        else
            if anchorWait then
                debugLog("move.anchor-free", {waited = os.clock() - anchorWait, goal = pos, snapshot = snapshot(target)}, "WARN")
            end
            anchorWait, anchorNotified = nil, false
        end
        do
            -- LOG RESET: bedakan "skrip menyuruh mundur" vs "server menyentak mundur".
            -- back = seberapa jauh posisi tersentak BERLAWANAN arah tujuan dalam 1 tick.
            local toGoal = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
            if prevTick and toGoal.Magnitude > 1 then
                local back = (prevTick.X - hrp.Position.X) * toGoal.Unit.X + (prevTick.Z - hrp.Position.Z) * toGoal.Unit.Z
                if back > 3 then
                    debugLog("move.yank", {back = back, goal = pos, snapshot = snapshot(target)}, "WARN", 1)
                end
            end
            prevTick = hrp.Position
            local ws = hum.WalkSpeed
            if lastTickSpeed and math.abs(ws - lastTickSpeed) > 1 then
                debugLog("move.speed-shift", {from = lastTickSpeed, to = ws, goal = pos, snapshot = snapshot(target)}, "WARN", 1)
            end
            lastTickSpeed = ws
        end
        if (hrp.Position - lastPos).Magnitude > 1.5 then
            lastPos = hrp.Position
            lastMove = os.clock()
        elseif os.clock() - lastMove > 0.8 and os.clock() - lastMove <= CONFIG.stuckSeconds then
            if not routing and os.clock() >= nextPlanAt then
                debugLog("move.stall-replan", {idleFor = os.clock() - lastMove, goal = pos, snapshot = snapshot(target)}, "WARN", 2)
                clearRoute()
                obstructed = true
                requestRoute()
            end
        elseif os.clock() - lastMove > CONFIG.stuckSeconds then
            return finish(false, "nyangkut")
        end
        if goalDistance() <= arrivalRadius then
            return finish(true)
        end
    end
    return finish(false, "timeout")
end

local function moveLeg(pos, timeout, token, target, arrivalRadius, transit)
    local root = getRig()
    if not root then return false, "no char" end
    local regions = treadmillRegions()
    local points = planTreadmillDetour(root.Position, pos, regions, CONFIG.treadmillCornerGap or 16)
    if not points then
        -- Goal inside a padded footprint (spawn close to the pad): walk to the
        -- nearest free edge; the caller's arrival radius covers the remainder.
        pos = pushOutsidePadding(pos, regions)
        points = planTreadmillDetour(root.Position, pos, regions, CONFIG.treadmillCornerGap or 16)
        debugLog("navigation.treadmill-goal-clamped", {goal = pos}, "WARN", 1)
    end
    if not points then return false, "tidak ada rute bebas treadmill" end
    if #points > 1 then
        debugLog("navigation.treadmill-detour", {legs = #points, first = points[1], goal = pos})
    end
    local started = os.clock()
    for i, point in ipairs(points) do
        local remaining = timeout-(os.clock()-started)
        if remaining <= 0 then return false, "timeout" end
        local last = i == #points
        -- Radius leg terakhir: kalau caller tidak mengirim arrivalRadius, JANGAN
        -- dipaksa 3 — moveRawLeg punya default sendiri (activationDistance utk
        -- target, radius dinamis utk rute pulang). Badan telur memblok karakter di
        -- ~3.5-4.5 stud, jadi radius 3 = diam permanen di depan telur ("nyangkut")
        -- dan pickup tidak pernah dikirim. (Regresi v4.34, diperbaiki v4.35.)
        local legRadius = 3
        if last then legRadius = arrivalRadius end
        local ok, why = moveRawLeg(point, remaining, token, target, legRadius, not last or transit)
        if not ok then return false, why end
    end
    return true
end

-- Corridor geometry (live raycast, read-only): wall utara z≈-294.6..-304,
-- dinding selatan z≈-424..-434, garis tengah aman z=-364.21 untuk x≈480..5100.
-- Base/plot ada di utara koridor (z>-280); kolom pintu keluar yang terukur
-- (celah level tanah di dinding utara) ≈ x 482..492.
-- Semua leg di bawah ini SEJAJAR SUMBU (Z ke tengah → X sepanjang tengah →
-- naik lewat kolom pintu keluar), jadi tidak ada leg panjang serong ke base.
local LANE_Z = -364.21
local function laneExitX()
    local home = State.home
    if not home then return 487 end
    if home.X < 400 or home.X > 600 then return nil end -- plot di luar celah terukur
    return math.clamp(home.X, 481, 493)
end
local function corridorSide(p)
    if p.Z > -280 then return "base" end
    if p.Z >= -460 then return "lane" end
    return nil
end
local function carryEscapePoint(start, home)
    local distance = CONFIG.carryEscapeDistance or 0
    if distance <= 0 or start.X < 560 or math.abs(home.X-start.X) <= 120 then return nil end
    local direction = home.X < start.X and -1 or 1
    return Vector3.new(start.X+direction*math.min(distance, math.abs(home.X-start.X)), start.Y, start.Z)
end
local function beginCarryEscape(token)
    if not active(token) or not isCarrying() or not State.home then return end
    local root, hum = getRig()
    if not root or not hum then return end
    local point = carryEscapePoint(root.Position, State.home)
    if not point then return end
    State.carryEscape = {point=point, root=root, uid=carryUid}
    -- Dispatch before UI/stat updates. Respect game anchors and solid walls.
    if not root.Anchored and not navigationObstructed(root.Position, point, root.Parent, hum.WalkSpeed) then
        Speed.goal, Speed.brakeAtGoal, Speed.goalRadius = point, true, 3
        hum:MoveTo(point)
        debugLog("return.escape-dispatch", {goal=point, pos=root.Position,
            carryToMoveMs=carryUpdatedAt and (os.clock()-carryUpdatedAt)*1000})
    end
end
local directFlightHintAt
-- Penerbangan lurus ala Dice: TIDAK memakai pathfinding. Tiap tick bidikan
-- adalah satu titik di garis lurus dari posisi sekarang, jadi berangkat dan
-- pulang jadi diagonal tunggal (bukan sidestep ke tengah dulu lalu belok).
-- Arah Z memakai lane tengah (LANE_Z) selama X masih jauh; saat X sudah dekat
-- kolom pintu/telur, bidikan pindah ke tujuan asli. Hanya jalan saat preset
-- CFrame (>=100 stud/s) aktif; GAME SPEED tetap memakai rute kaki lama.
local function directAim(pos, from, exitX, target)
    if target then
        if from.Z > LANE_Z + 12 then return exitX, LANE_Z end
        if math.abs(pos.X - from.X) > 40 then return pos.X, LANE_Z end
        return pos.X, pos.Z
    end
    if math.abs(from.X - exitX) > 30 then return exitX, LANE_Z end
    return pos.X, pos.Z
end
local function moveDirect(pos, timeout, token, target, arrivalRadius)
    local hrp, hum = getRig()
    if not hrp or not hum then return false, "no char" end
    local exitX = laneExitX() or 487
    arrivalRadius = arrivalRadius or (target and CONFIG.activationDistance or 3)
    local t0 = os.clock()
    local lastPos, lastMove = hrp.Position, os.clock()
    local prevTick = hrp.Position
    local anchorWait, anchorNotified
    local function cleanupNavigation()
        Speed.goal, Speed.brakeAtGoal, Speed.goalRadius = nil, nil, nil
    end
    cancelNavigation = cleanupNavigation
    debugLog("direct.start", {goal = pos, radius = arrivalRadius, timeout = timeout, exitX = exitX, snapshot = snapshot(target)})
    local function finish(ok, reason)
        cleanupNavigation()
        if cancelNavigation == cleanupNavigation then cancelNavigation = nil end
        if active(token) and hum.Parent and hrp.Parent then hum:MoveTo(hrp.Position) end
        debugLog("direct.finish", {ok = ok, reason = reason or "arrived", elapsed = os.clock() - t0, goal = pos, snapshot = snapshot(target)})
        return ok, reason
    end
    local function goalDistance()
        local offset = hrp.Position - pos
        -- SpawnPoint markers sit above the floor: pulang selesai lewat X/Z saja.
        if not target then return Vector2.new(offset.X, offset.Z).Magnitude end
        return offset.Magnitude
    end
    while os.clock() - t0 < timeout do
        if not active(token) or not State.running then return finish(false, "stopped") end
        if Speed.correction then return finish(false, "koreksi posisi") end
        if hum.Health <= 0 or LP.Character ~= hrp.Parent then return finish(false, "karakter berubah") end
        tryExitTreadmill(hrp, hum, token)
        if target and not targetAvailable(target) then return finish(false, "target hilang") end
        if target and not validateEggRarity(target) then return finish(false, "filter berubah") end
        if target and not fieldGateOpen() then return finish(false, "gerbang field tutup") end
        if not target then
            -- Perjalanan pulang diselesaikan walau klaim/carry berubah di jalan,
            -- kecuali telur sudah lepas JAUH dari base (biar hunting lanjut).
            resolveAutoBase()
            if not State.home or (State.home - pos).Magnitude > 1 then return finish(false, "base berubah/belum ter-load") end
            if returnContext and carryKnown and not carryState and not returnContext.lossNotified then
                returnContext.lossNotified = true
                if claimRevision <= returnContext.revision and goalDistance() > CONFIG.dropAbortDistance then
                    debugLog("return.abort-drop", {uid = returnContext.uid, distance = goalDistance(), snapshot = snapshot()}, "WARN")
                    return finish(false, "carry-drop-jauh")
                end
                setStatus("TELUR LEPAS • tetap menyelesaikan perjalanan ke base")
                debugLog("return.carry-ended-continue", {uid = returnContext.uid, snapshot = snapshot()}, "WARN")
            end
        end
        if goalDistance() <= arrivalRadius then return finish(true) end
        local from = hrp.Position
        local aimX, aimZ = directAim(pos, from, exitX, target)
        local aim = Vector3.new(aimX, from.Y, aimZ)
        if Speed.mode == "cframe" then
            Speed.goal, Speed.brakeAtGoal, Speed.goalRadius = aim, false, arrivalRadius
        else
            -- Preset diganti ke GAME SPEED di tengah jalan: lanjut lurus dengan kaki.
            hum:MoveTo(aim)
        end
        if os.clock() - lastMove > CONFIG.stuckSeconds then return finish(false, "nyangkut") end
        if not waitActive(CONFIG.moveInterval, token) then return finish(false, "stopped") end
        local currentRoot, currentHumanoid = getRig()
        if currentRoot ~= hrp or currentHumanoid ~= hum then return finish(false, "karakter berubah") end
        if hrp.Anchored then
            anchorWait = anchorWait or os.clock()
            lastMove = os.clock()
            if os.clock() - anchorWait > CONFIG.anchorGrace then
                return finish(false, "gerak tetap dikunci game; keluar treadmill / tekan WASD lalu ON lagi")
            end
            if not anchorNotified then
                anchorNotified = true
                setStatus("gerak dikunci game — menunggu terlepas…")
                debugLog("direct.anchor-lock", {pos = hrp.Position, goal = pos, snapshot = snapshot(target)}, "WARN")
            end
        else
            if anchorWait then
                debugLog("direct.anchor-free", {waited = os.clock() - anchorWait, goal = pos, snapshot = snapshot(target)}, "WARN")
            end
            anchorWait, anchorNotified = nil, false
        end
        do
            -- LOG RESET: bedakan "skrip menyuruh mundur" vs "server menyentak mundur".
            local toGoal = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
            if toGoal.Magnitude > 1 then
                local back = (prevTick.X - hrp.Position.X) * toGoal.Unit.X + (prevTick.Z - hrp.Position.Z) * toGoal.Unit.Z
                if back > 3 then
                    debugLog("direct.yank", {back = back, goal = pos, aim = aim, snapshot = snapshot(target)}, "WARN", 1)
                end
            end
            prevTick = hrp.Position
        end
        if (hrp.Position - lastPos).Magnitude > 1.5 then
            lastPos = hrp.Position
            lastMove = os.clock()
        end
        if goalDistance() <= arrivalRadius then return finish(true) end
    end
    return finish(false, "timeout")
end

local function moveTo(pos, timeout, token, target, arrivalRadius)
    local root = getRig()
    if not root then return false, "no char" end
    if CONFIG.directFlight then
        if Speed.mode == "cframe" then
            return moveDirect(pos, timeout, token, target, arrivalRadius)
        end
        if not directFlightHintAt or os.clock() - directFlightHintAt > 30 then
            directFlightHintAt = os.clock()
            setStatus("rute lurus ala Dice butuh preset CFrame (>=100 stud/s)")
            debugLog("navigation.direct-needs-cframe", {selected = Speed.selected}, "WARN", 1)
        end
    end
    local start = root.Position
    local escape
    if not target and isCarrying() then
        local saved = State.carryEscape
        local point = saved and saved.root == root and saved.uid == carryUid and saved.point or carryEscapePoint(start, pos)
        local direction = pos.X < start.X and -1 or 1
        if point and (point.X-start.X)*direction > 10 then
            escape, start = point, point
        end
    end
    local startSide, goalSide = corridorSide(start), corridorSide(pos)
    local legs = {}
    if startSide == "lane" and goalSide == "lane" and math.abs(pos.X - start.X) > 120 then
        -- Jalan jauh di dalam koridor: masuk tengah dulu, lurus, belok di ujung.
        legs = {Vector3.new(start.X, start.Y, LANE_Z), Vector3.new(pos.X, start.Y, LANE_Z)}
    else
        local exitX = laneExitX()
        if exitX then
            if startSide == "lane" and goalSide == "base" then
                -- Pulang: lurus ke tengah → lurus ke kolom pintu keluar → baru naik ke base.
                legs = {Vector3.new(start.X, start.Y, LANE_Z), Vector3.new(exitX, start.Y, LANE_Z)}
            elseif startSide == "base" and goalSide == "lane" then
                -- Berangkat: kolom pintu keluar → lurus di tengah → baru ke telur.
                legs = {Vector3.new(exitX, start.Y, LANE_Z), Vector3.new(pos.X, start.Y, LANE_Z)}
            end
        end
    end
    if escape then
        table.insert(legs, 1, escape)
        debugLog("navigation.escape-first", {goal=escape, lane=LANE_Z})
    end
    if #legs > 0 then
        local started = os.clock()
        debugLog("navigation.fixed-lane", {z = LANE_Z, from = start, goal = pos, legs = #legs})
        for _, point in ipairs(legs) do
            local remaining = timeout - (os.clock() - started)
            if remaining <= 0 then return false, "timeout" end
            local ok, why = moveLeg(point, remaining, token, target, 10, true)
            if not ok then return false, why end
        end
        timeout = timeout - (os.clock() - started)
        if timeout <= 0 then return false, "timeout" end
    end
    return moveLeg(pos, timeout, token, target, arrivalRadius)
end

local function returnEgg(token, claimBefore)
    debugPhase = "returning"
    debugLog("return.start", snapshot())
    if not State.returnHomePending then
        State.returnHomePending = true
        State.returnClaimRevision, State.returnUid = claimBefore or claimRevision, carryUid
    end
    if not resolveAutoBase() then
        requestBaseSnapshot()
        retryWait(token, "menunggu data base", 2)
        return false
    end
    local revision = State.returnClaimRevision
    returnContext = {revision = revision, uid = State.returnUid}
    debugLog("return.dispatch", {carryToMoveMs = carryUpdatedAt and (os.clock() - carryUpdatedAt) * 1000})
    setStatus("PULANG KE BASE • target pulang diprioritaskan")
    local reached, why = moveTo(State.home, CONFIG.returnTimeout, token, nil, 3)
    if not active(token) then returnContext = nil; return false end
    if not reached and why == "nyangkut" then
        -- One new route attempt; keep home pending if it also fails.
        reached, why = moveTo(State.home, 12, token, nil, 3)
        if not active(token) then returnContext = nil; return false end
    end
    returnContext = nil
    if not reached and (why == "koreksi posisi" or why == "karakter berubah" or why == "no char") then
        debugLog("return.wait-recovery", {reason = why, pending = State.returnHomePending}, "WARN")
        return false
    end
    if not reached and why == "carry-drop-jauh" then
        -- A lost egg must pause instead of immediately reversing toward a new target.
        State.returnHomePending, State.returnClaimRevision, State.returnUid = false, nil, nil
        debugLog("return.aborted-drop", {snapshot = snapshot()}, "WARN")
        retryWait(token, "telur lepas; cari target baru setelah jeda", 2)
        return false
    end
    if not reached then
        debugLog("return.route-failed", {reason = why, snapshot = snapshot()}, "WARN")
        retryWait(token, "rute pulang terhambat: " .. tostring(why), 3)
        return false
    end
    -- Only arrival clears this priority. Claim/carry changes on the way never do.
    State.returnHomePending, State.returnClaimRevision, State.returnUid = false, nil, nil
    State.carryEscape = nil
    local deadline = os.clock() + CONFIG.claimConfirmTimeout
    debugPhase = "confirming-claim"
    while active(token) and claimRevision == revision and isCarrying() and os.clock() < deadline do
        setStatus("di base — nunggu konfirmasi klaim…")
        task.wait(0.05)
    end
    if not active(token) then return false end
    if claimRevision == revision and not isCarrying() then
        -- carry berakhir tepat di base: kemungkinan baru di-redeem — beri waktu verdict
        local grace = os.clock() + 0.35
        while active(token) and claimRevision == revision and os.clock() < grace do task.wait(0.05) end
    end
    if not active(token) then return false end
    if claimRevision > revision then
        State.claimed += 1
        refreshStats()
        local v = lastVerdict
        local label = (v and tostring(v.name or v.cat)) or "telur"
        local rar = (v and v.rar) and (" • " .. tostring(v.rar)) or ""
        addLog("✅ klaim: " .. label .. rar)
        debugLog("return.claimed", snapshot())
        return true
    end
    -- Telur ke-drop di jalan (ketangkep guard) atau klaim tak terkonfirmasi.
    -- Carry loss is not a confirmed claim and does not identify who caused it.
    local dropped = not isCarrying()
    debugLog("return.unconfirmed", {dropped = dropped, reached = reached, why = why}, "WARN")
    addLog(dropped and "Telur lepas; belum tercatat masuk base." or "klaim belum terkonfirmasi — tetap ON, tunggu dan cek lagi")
    if dropped then
        setStatus("Sampai base, tetapi game belum mengonfirmasi telur tersimpan.")
    else
        -- Otherwise the outer loop would call returnEgg forever with 7 s pauses.
        retryWait(token, "masih membawa telur; menunggu konfirmasi game", 2)
    end
    return false
end

-- The reference calls CarryFieldEgg repeatedly. Use its verified request schema
-- only once per attempt instead. Never hold the worker inside InvokeServer or
-- fireproximityprompt: a matching carry event must dispatch the return immediately.
local function pickupEgg(egg, token)
    if pendingPickup then return false, "request sebelumnya belum selesai" end
    if not fieldGateOpen() then return false, "gerbang field tutup" end
    if not active(token) or not targetAvailable(egg) then return false, "target hilang/stopped" end
    local rarityAllowed, rarityReason = validateEggRarity(egg)
    if not rarityAllowed then
        debugLog("pickup.rarity-rejected", {uid = egg.uid, reason = rarityReason, snapshot = snapshot(egg)}, "WARN")
        return false, rarityReason
    end
    local hrp, hum = getRig()
    if not hrp or not hum or hum.Health <= 0 or hrp.Anchored then return false, "karakter belum siap" end
    if (hrp.Position - egg.part.Position).Magnitude > math.min(CONFIG.activationDistance, egg.prompt.MaxActivationDistance) then
        return false, "di luar jarak"
    end
    local useServer = CONFIG.pickupMode == "server" and not CONFIG.useRealInput
    local ask = networking and networking:FindFirstChild("RF/EggWorld/AskFieldEggCarry")
    local record = Field.records[egg.uid]
    if useServer and (not record or not ask or not ask:IsA("RemoteFunction")) then
        return false, "UID/API carry belum tersedia"
    end
    local beforeRevision, started = carryRevision, os.clock()
    local request = {done = false, accepted = false}
    local releaseInput
    pendingPickup = request
    debugLog("pickup.request", {uid = egg.uid, mode = useServer and "server" or "prompt", snapshot = snapshot(egg)})
    task.spawn(function()
        local ok, accepted, denial = xpcall(function()
            -- The worker may start after a filter or snapshot change.
            if not active(token) or not State.running then return false, "stopped" end
            local allowed, reason = validateEggRarity(egg)
            if not allowed then return false, reason end
            if useServer then
                local slotKey
                -- Verified Shared.Util.AreaEggSlotIdentity.SlotKey/LooksLikeFirstAreaUid.
                if egg.uid:sub(1, 13) == "FirstAreaEgg_" then
                    if type(record.AreaId) ~= "string" or type(record.NestId) ~= "string" then
                        return false, "FirstArea slot identity missing"
                    end
                    slotKey = record.AreaId .. ":" .. record.NestId
                end
                return ask:InvokeServer({Uid = egg.uid, FirstAreaSlotKey = slotKey})
            end
            if CONFIG.useRealInput then
                local vim = game:GetService("VirtualInputManager")
                local released = false
                releaseInput = function()
                    if not released then released = true; vim:SendKeyEvent(false, Enum.KeyCode.E, false, game) end
                end
                vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                waitActive(math.max(egg.prompt.HoldDuration, 0.4) + 0.15, token)
                releaseInput()
            else
                fireproximityprompt(egg.prompt, egg.prompt.HoldDuration)
            end
            return nil
        end, debug.traceback)
        request.done, request.ok, request.accepted = true, ok, ok and accepted == true
        request.reason = ok and denial or tostring(accepted)
        request.finishedAt = os.clock()
        if pendingPickup == request then pendingPickup = nil end
        if alive then debugLog("pickup.reply", {uid = egg.uid, ok = ok, accepted = request.accepted,
            reason = request.reason, elapsed = os.clock() - started}, ok and "INFO" or "ERROR") end
    end)
    local deadline = started + CONFIG.carryConfirmTimeout + (useServer and 0 or egg.prompt.HoldDuration + 0.15)
    local missingSince
    local function finish(ok, reason)
        if releaseInput then pcall(releaseInput) end
        return ok, reason
    end
    while active(token) and State.running do
        if carryKnown and carryState then
            if carryUid == egg.uid then return finish(true, "carry UID confirmed") end
            return finish(false, "membawa UID lain")
        end
        if request.done then
            if not request.ok then return finish(false, request.reason) end
            if useServer then
                if not request.accepted then return finish(false, request.reason or "server menolak carry") end
                -- A true reply confirms THIS request's UID, unless a newer carry
                -- update has already reported it lost/dropped. Never overwrite it.
                if carryRevision == beforeRevision then
                    carryKnown, carryState, carryUid, carryUpdatedAt = true, true, egg.uid, os.clock()
                    return finish(true, "server accepted UID")
                end
                return finish(false, "carry sudah berakhir setelah request")
            end
        end
        if LP.Character ~= hrp.Parent or hum.Health <= 0 then return finish(false, "karakter berubah/terkunci") end
        if not State.selected[egg.rarity] then return finish(false, "filter berubah") end
        if not hrp.Anchored and (hrp.Position - egg.part.Position).Magnitude > egg.prompt.MaxActivationDistance then
            return finish(false, "keluar jarak saat ambil")
        end
        if not targetAvailable(egg) then
            missingSince = missingSince or os.clock()
            if os.clock() - missingSince > 0.2 then return finish(false, "target hilang/diambil pemain lain") end
        else missingSince = nil end
        if os.clock() >= deadline then return finish(false, "carry timeout (request tidak diulang selama pending)") end
        task.wait(0.025)
    end
    return finish(false, "stopped")
end

ensureWorker = function()
    if Worker.alive or not alive or rawget(_G, "AutoStealEggsEpoch") ~= myEpoch then return end
    if Worker.retryAt and os.clock() < Worker.retryAt then return end
    Worker.retryAt, Worker.error = nil, nil
    Worker.alive, Worker.lastActivity = true, os.clock()
    Worker.starts += 1
    debugLog("worker.start", {starts = Worker.starts})
    task.spawn(function()
    local ok, err = xpcall(function()
    while alive and rawget(_G, "AutoStealEggsEpoch") == myEpoch do
        task.wait(0.1)
        Worker.lastActivity = os.clock()
        if not alive then break end
        if not State.running then continue end
        local token = generation
        debugPhase = "scanning"

        local hrp, hum = getRig()
        if not hrp or not hum then
            Worker.waitingRig = true
            debugPhase = "waiting-character"
            setStatus("menunggu karakter siap")
            waitActive(0.1, token)
            continue
        end
        if hrp.Anchored then
            tryExitTreadmill(hrp, hum, token)
            -- Kunci singkat (wake run-back) ditunggu, bukan langsung OFF;
            -- kalau lewat parkir treadmill AFK kuncinya permanen.
            local lockDeadline = os.clock() + 6
            debugPhase = "waiting-character"
            setStatus("gerak dikunci game — menunggu terlepas…")
            repeat
                task.wait(0.2)
                Worker.lastActivity = os.clock()
                hrp, hum = getRig()
                if hrp and hum then tryExitTreadmill(hrp, hum, token) end
            until not active(token) or not (hrp and hrp.Anchored) or os.clock() >= lockDeadline
            if not active(token) then continue end
            hrp, hum = getRig()
            if not hrp or not hum then
                Worker.waitingRig = true
                debugPhase = "waiting-character"
                setStatus("menunggu karakter siap")
                continue
            end
            if hrp and hrp.Anchored then
                retryWait(token, "gerak masih dikunci game; menunggu terlepas", 1)
                continue
            end
        end
        if Worker.waitingRig then
            Worker.waitingRig = false
            debugLog("worker.character-ready", {position = hrp.Position})
        end
        if Speed.correction then
            local correction = Speed.correction
            debugPhase = "waiting-position"
            if correction.root ~= hrp then
                Speed.correction = nil
            else
                if (hrp.Position - correction.pos).Magnitude > 2 then
                    correction.pos, correction.stableSince = hrp.Position, os.clock()
                end
                if os.clock() - correction.at > 10 then
                    correction.at = os.clock()
                    retryWait(token, "posisi belum stabil; boost OFF, menunggu", 1)
                    continue
                end
                if os.clock() - correction.stableSince < 1 then
                    hum:MoveTo(hrp.Position)
                    setStatus("koreksi posisi — menunggu stabil; boost OFF")
                    waitActive(0.1, token)
                    continue
                end
                Speed.correction = nil
                debugLog("speed.position-stable", {position = hrp.Position, activeMultiplier = Speed.multiplier})
            end
        end
        if State.returnHomePending or isCarrying() then
            returnEgg(token)
            continue
        end

        if not fieldGateOpen() then
            setStatus("gerbang field tutup — menunggu game membukanya (bukan scan/loading)")
            waitActive(0.1, token)
            continue
        end

        requestFieldSnapshot()
        if CONFIG.pickupMode == "server" and not Field.ready then
            setStatus(Field.error and "snapshot server gagal — tunggu retry 10s" or "menunggu snapshot server (tanpa warm scan mesh)…")
            waitActive(0.1, token)
            continue
        end
        if pendingPickup then
            setStatus("request carry server belum selesai — tidak dikirim ulang")
            waitActive(0.1, token)
            continue
        end

        local eggs, detected = collectEggs()
        if uiHooks.filterSummary then uiHooks.filterSummary(filterScanText()) end
        gui:SetAttribute("ScanMs", lastScanMs)
        gui:SetAttribute("ScanCount", scanCount)
        gui:SetAttribute("RarityResolves", resolveCount)
        if #eggs == 0 then
            setStatus(string.format("Cocok di server %d • ter-render %d • siap 0 (rarity DAN tempat)",
                lastFilterScan.serverMatches, lastFilterScan.renderedMatches))
            waitActive(0.25, token)
            continue
        end

        local egg = eggs[1]
        lastTarget, debugPhase = egg, "approaching"
        debugLog("target.selected", snapshot(egg))
        local label = egg.rarity
        if egg.category and egg.category ~= "" then label = label .. " (" .. egg.category .. ")" end
        local farHint = egg.dist > 1200 and " • jauh (filter tier tinggi)" or ""
        hrp, hum = getRig()
        if not hrp or not hum then Worker.waitingRig = true; continue end
        local estimateSpeed = math.max(hum.WalkSpeed, 16) * math.max(Speed.multiplier or 1, 1)
        setStatus(string.format("menuju %s • %d stud • perkiraan %.0f dtk%s", label, math.floor(egg.dist), egg.dist / estimateSpeed, farHint))

        -- Timeout travel dibuat proporsional jarak, agar telur jauh tidak di-skip
        -- cuma karena waktu jalan 18 detik tidak cukup mantau sampai dekat.
        local moveSpeed = math.max(hum.WalkSpeed, 16) * math.max(Speed.multiplier or 1, 1) * 0.75
        local travelTimeout = math.clamp(egg.dist / moveSpeed + 10, CONFIG.arriveTimeout, 90)
        local reached, why = moveTo(egg.pos, travelTimeout, token, egg)
        if not active(token) then continue end
        if not reached then
            if why == "filter berubah" then
                -- Deselection is not a failed pickup: do not blacklist a valid
                -- egg for 120 seconds when the user merely changes a filter.
                lastTarget = nil
                continue
            end
            if why == "koreksi posisi" or why == "karakter berubah" or why == "no char" then
                lastTarget = nil
                continue
            end
            local wait = CONFIG.eggBlacklistSeconds
            -- Terhalang dinding / gerbang tutup biasanya hilang dalam hitungan detik
            -- (gerbang buka lagi, wall clear kalau lewat pintu lain) — blacklist
            -- lama hanya memboros telur yang masih valid.
            if why == "gerbang field tutup" then wait = 15
            elseif why == "terhalang" then wait = 20 end
            State.blacklist[egg.prompt] = os.clock() + wait
            debugLog("target.blacklist", {reason = why, seconds = wait, snapshot = snapshot(egg)}, "WARN")
            setStatus("skip: " .. tostring(why))
            task.wait(0.5)
            continue
        end

        -- Disabled/contested targets are skipped, not waited on for another second.
        local useServer = CONFIG.pickupMode == "server" and not CONFIG.useRealInput
        local ready = targetAvailable(egg) and (useServer or egg.prompt.Enabled)
        if not ready then
            debugLog("prompt.not-ready", snapshot(egg), "WARN")
            setStatus("prompt belum aktif — skip telur")
            State.blacklist[egg.prompt] = os.clock() + 40
            debugLog("target.blacklist", {reason = "prompt not ready", seconds = 40, snapshot = snapshot(egg)}, "WARN")
            continue
        end

        -- catat status carry sebelum fire
        local carryingBefore = isCarrying()
        local currentRoot = getRig()
        if carryingBefore then returnEgg(token); continue end
        if not currentRoot or not egg.part.Parent or not egg.prompt.Parent
            or (not useServer and not egg.prompt.Enabled) or not State.selected[egg.rarity]
            or (currentRoot.Position - egg.part.Position).Magnitude > math.min(CONFIG.activationDistance, egg.prompt.MaxActivationDistance) then
            debugLog("prompt.precheck-rejected", snapshot(egg), "WARN", 1)
            continue
        end

        local tries = (State.tries[egg.prompt] or 0) + 1
        State.tries[egg.prompt] = tries
        setStatus(string.format("ambil %s (coba %d/%d)", egg.rarity, tries, CONFIG.maxTriesPerEgg))

        debugPhase = useServer and "requesting-carry" or "activating-prompt"
        debugAttempt += 1
        debugLog("pickup.attempt", snapshot(egg))
        local attemptStarted = os.clock()
        local claimBefore = claimRevision
        local success, pickupReason = pickupEgg(egg, token)
        if not active(token) then continue end
        debugLog("carry.result", {success = success, reason = pickupReason, elapsed = os.clock() - attemptStarted, snapshot = snapshot(egg)}, success and "INFO" or "WARN")

        if success then
            beginCarryEscape(token)
            State.stolen += 1
            State.consecutiveFails = 0
            refreshStats()
            local l = "🫳 " .. egg.rarity
            if egg.category then l = l .. " (" .. egg.category .. ")" end
            addLog(l .. " @" .. os.date("%H:%M:%S") .. " — lari pulang!")
            -- Jangan diam di tempat (guard bisa drop telur). Langsung pulang ke base.
            returnEgg(token, claimBefore)
        else
            State.failed += 1
            State.consecutiveFails += 1
            refreshStats()
            addLog("❌ " .. egg.rarity .. ": " .. tostring(pickupReason))
            if tries >= CONFIG.maxTriesPerEgg then
                State.blacklist[egg.prompt] = os.clock() + CONFIG.eggBlacklistSeconds
                setStatus("gagal — telur di-blacklist sementara")
            else
                setStatus("gagal — coba lagi telur lain")
            end
            if State.consecutiveFails >= CONFIG.stopAfterFails then
                local failures = State.consecutiveFails
                State.consecutiveFails = 0
                retryWait(token, "gagal " .. failures .. "x; tetap ON", 5)
            end
            State.blacklist[egg.prompt] = math.max(State.blacklist[egg.prompt] or 0, os.clock() + CONFIG.retryCooldown)
            debugLog("target.retry", {seconds = math.max(0, State.blacklist[egg.prompt] - os.clock()), snapshot = snapshot(egg)}, "WARN")
            waitActive(CONFIG.retryCooldown, token)
        end
    end
    end, debug.traceback)
    Worker.alive = false
    if not ok and alive then
        Worker.error = tostring(err)
        Worker.lastError = Worker.error
        debugLog("worker.error", {traceback = err, snapshot = snapshot()}, "ERROR")
        if cancelNavigation then pcall(cancelNavigation); cancelNavigation = nil end
        Speed.goal = nil
        pcall(releaseSpeed, "error proses; boost OFF")
        if State.running then
            debugPhase = "retry-wait"
            Worker.retryAt = os.clock() + 3
            pcall(setStatus, "ON • proses error; mulai ulang otomatis dalam 3 dtk")
            local retryToken = generation
            task.spawn(function()
                if waitActive(3, retryToken) and State.running then ensureWorker() end
            end)
        end
        warn("[AutoStealEggs v4.35] " .. tostring(err))
    end
    end)
end
ensureWorker()

local runControl = new("BindableFunction", {Name = "RunControl"}, gui)
runControl.OnInvoke = function(on)
    if type(on) ~= "boolean" then return {ok = false, reason = "expected boolean"} end
    setRunning(on)
    return {ok = State.running == on, running = State.running, workerAlive = Worker.alive,
        workerStarts = Worker.starts, error = Worker.error}
end

-- MCP-facing bounded log reader; does not start automation or manipulate remotes.
local debugReader = new("BindableFunction", {Name = "DebugLogs"}, gui)
debugReader.OnInvoke = function(action, limit, eventFilter)
    if action == "snapshot" then return clean(snapshot()) end
    if action == "mark" then
        debugLog("manual.snapshot", snapshot())
        return debugSession
    end
    local records = {}
    limit = math.clamp(tonumber(limit) or 30, 1, CONFIG.debugLogLimit)
    for i = #debugRecords, 1, -1 do
        if not eventFilter or debugRecords[i].event:find(tostring(eventFilter), 1, true) then
            -- Return a copy, so callers cannot modify the retained records.
            table.insert(records, 1, HttpService:JSONDecode(HttpService:JSONEncode(debugRecords[i])))
            if #records >= limit then break end
        end
    end
    return {session = debugSession, totalRetained = #debugRecords, lastSequence = debugSequence, records = records}
end
local debugButton = new("TextButton", {
    Name = "Debug", Text = "Debug", Font = Enum.Font.GothamMedium, TextSize = 10,
    BackgroundColor3 = Color3.fromRGB(40, 42, 52), TextColor3 = Color3.fromRGB(200, 202, 214),
    BorderSizePixel = 0, Size = UDim2.fromOffset(44, 18), Position = UDim2.new(1, -44, 1, -46),
}, body)
new("UICorner", {CornerRadius = UDim.new(0, 5)}, debugButton)
statsLabel.Size = UDim2.new(1, -48, 0, 16)
connect(debugButton.MouseButton1Click, function()
    debugLog("manual.snapshot", snapshot())
    addLog("Debug snapshot disimpan: " .. debugSession)
end)
local logFileButton = new("TextButton", {
    Name = "LogFile", Text = "File", Font = Enum.Font.GothamMedium, TextSize = 10,
    BackgroundColor3 = Color3.fromRGB(40, 42, 52), TextColor3 = Color3.fromRGB(200, 202, 214),
    BorderSizePixel = 0, Size = UDim2.fromOffset(44, 18), Position = UDim2.new(1, -92, 1, -46),
}, body)
new("UICorner", {CornerRadius = UDim.new(0, 5)}, logFileButton)
local presentLog -- forward: dipakai tombol File, didefinisikan setelah viewer
connect(logFileButton.MouseButton1Click, function()
    presentLog()
end)

-- Penampil log dalam game (copy manual): executor tanpa writefile/
-- setclipboard tetap bisa kirim log — klik kotak, Ctrl+A, Ctrl+C.
local logViewer = new("Frame", {
    Name = "LogViewer", Visible = false,
    Size = UDim2.fromOffset(500, 380), Position = UDim2.new(0.5, -250, 0.5, -190),
    BackgroundColor3 = Color3.fromRGB(18, 19, 24), BorderSizePixel = 0,
}, miniGui)
new("UICorner", {CornerRadius = UDim.new(0, 12)}, logViewer)
new("UIStroke", {Color = Color3.fromRGB(64, 66, 82), Thickness = 1.2, Transparency = 0.2}, logViewer)
new("TextLabel", {
    Text = "Log — klik kotak, Ctrl+A, Ctrl+C, paste ke Notepad", Font = Enum.Font.GothamBold, TextSize = 13,
    TextColor3 = Color3.fromRGB(235, 236, 242), BackgroundTransparency = 1,
    Size = UDim2.new(1, -70, 0, 26), Position = UDim2.fromOffset(12, 6),
    TextXAlignment = Enum.TextXAlignment.Left,
}, logViewer)
local logViewerClose = new("TextButton", {
    Name = "Close", Text = "X", Font = Enum.Font.GothamBold, TextSize = 14,
    TextColor3 = Color3.fromRGB(255, 255, 255), BackgroundColor3 = Color3.fromRGB(160, 50, 50),
    BorderSizePixel = 0, Size = UDim2.fromOffset(28, 24), Position = UDim2.new(1, -36, 0, 6),
}, logViewer)
new("UICorner", {CornerRadius = UDim.new(0, 6)}, logViewerClose)
connect(logViewerClose.MouseButton1Click, function() logViewer.Visible = false end)
local logViewerStatus = new("TextLabel", {
    Text = "", Font = Enum.Font.Gotham, TextSize = 11,
    TextColor3 = Color3.fromRGB(150, 200, 150), BackgroundTransparency = 1,
    Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 32),
    TextXAlignment = Enum.TextXAlignment.Left,
}, logViewer)
local logViewerBox = new("TextBox", {
    MultiLine = true, ClearTextOnFocus = false, Text = "",
    Font = Enum.Font.Code, TextSize = 12,
    TextColor3 = Color3.fromRGB(220, 222, 232), BackgroundColor3 = Color3.fromRGB(28, 29, 36),
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    BorderSizePixel = 0, Size = UDim2.new(1, -24, 1, -62), Position = UDim2.fromOffset(12, 52),
}, logViewer)
new("UICorner", {CornerRadius = UDim.new(0, 6)}, logViewerBox)
presentLog = function()
    local text, err = buildLogText()
    if not text then addLog("Log gagal: " .. tostring(err)) return end
    local wf = rawget(_G, "writefile")
    if type(wf) == "function" then
        local ok, msg = saveLogToFile(false)
        logViewerStatus.Text = ok and ("tersimpan: " .. tostring(msg)) or ("gagal simpan: " .. tostring(msg))
    else
        logViewerStatus.Text = "tanpa writefile — copy manual dari kotak di bawah"
    end
    logViewerBox.Text = text
    gui.Enabled = false
    logViewer.Visible = true
    addLog("Log ditampilkan (" .. #text .. " char) — Ctrl+A Ctrl+C.")
end
gui:SetAttribute("DebugSession", debugSession)
local function invalidateCharacter(reason)
    generation += 1
    Worker.waitingRig = true
    if cancelNavigation then pcall(cancelNavigation); cancelNavigation = nil end
    Speed.goal, Speed.correction = nil, nil
    releaseSpeed("respawn; pilih ulang boost")
    lastTarget, returnContext = nil, nil
    State.returnHomePending, State.returnClaimRevision, State.returnUid = false, nil, nil
    Field.epoch += 1
    Field.ready, Field.lastRequest, Field.error = false, -math.huge, nil
    Field.records, Field.revisions, Field.sequence = {}, {}, 0
    carryKnown, carryState, carryUid, carryUpdatedAt = false, false, nil, nil
    carryRevision += 1
    if State.running then debugPhase = "waiting-character"; setStatus("menunggu karakter siap") end
    debugLog(reason, {generation = generation, fieldEpoch = Field.epoch, running = State.running})
end
connect(LP.CharacterRemoving, function() invalidateCharacter("character.removing") end)
connect(LP.CharacterAdded, function(character)
    invalidateCharacter("character.reset")
    debugLog("character.added", {character = character})
end)
warn("[ASE-BOOT 4.35] 07 host-ready")
gui:SetAttribute("Version", "4.39-straight-flight")
gui:SetAttribute("WindUILoader", "1.6.66-static-icons")
gui:SetAttribute("UIReadyMs", (os.clock() - debugStarted) * 1000)
debugLog("session.ready", {startupMs = (os.clock() - debugStarted) * 1000, snapshot = snapshot()})

-- DELIVERY RECORDER CORE: injected clock/sampler; never controls gameplay.
local function newDeliveryRecorder(clock, readSample)
    local r = {current = nil, previous = nil, sequence = 0, nextSampleAt = 0, notices = {}}
    local function copy(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for k, v in pairs(value) do out[k] = copy(v) end
        return out
    end
    local function append(list, entry, now, limit)
        table.insert(list, entry)
        while #list > limit or (#list > 0 and list[1].serverTime < now - 30) do table.remove(list, 1) end
    end
    function r:event(kind, data)
        local now = clock()
        local event = {serverTime = now, kind = kind, data = copy(data or {})}
        append(self.notices, event, now, 200)
        local c = self.current
        if c and (c.active or now <= (c.endedAt or 0) + 2) then append(c.events, event, now, 200) end
    end
    function r:sample(force)
        local c, now = self.current, clock()
        if not c or (not c.active and now > (c.endedAt or 0) + 2) then return end
        if not force and now < self.nextSampleAt then return end
        self.nextSampleAt = now + 0.1
        local sample, root = readSample(c.uid)
        sample.serverTime = now
        local prior = c.samples[#c.samples]
        if prior and self.lastRoot == root and root and sample.position and prior.position then
            local dt = now - prior.serverTime
            if dt > 0 then
                local a, b = sample.position, prior.position
                sample.displacementSpeed = math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2) / dt
            end
        end
        self.lastRoot = root
        append(c.samples, sample, now, 300)
        c.lastSampleAt = now
        if not c.startPosition then c.startPosition = copy(sample.position) end
    end
    function r:onCarry(payload)
        if type(payload) ~= "table" or type(payload.IsCarrying) ~= "boolean" then return end
        local c = self.current
        if payload.IsCarrying then
            if not c or not c.active or c.uid ~= payload.Uid then
                self.previous = c
                self.sequence += 1
                c = {id = self.sequence, uid = payload.Uid, category = payload.AssetCategory,
                    area = payload.AreaId, startedAt = clock(), active = true,
                    outcome = "carrying", samples = {}, events = {}}
                self.current, self.lastRoot, self.nextSampleAt = c, nil, 0
            end
            c.carryMultiplier = payload.SpeedMultiplier
            c.guardDisabled = payload.GuardDisabled
        elseif c and c.active then
            c.active, c.endedAt = false, clock()
            if c.outcome == "carrying" then c.outcome = "carry-ended-unknown" end
        end
        self:event("carry", payload)
        self:sample(true)
    end
    function r:onClaim(payload)
        self:event("claim-feedback", payload)
        local c, now = self.current, clock()
        if c and type(payload) == "table" and payload.AssetCategory == c.category
            and (c.active or now - (c.endedAt or 0) <= 2) then
            c.outcome, c.outcomeTime = "claimed", now
            c.correlation = "latest-local-carry-category"
        end
    end
    function r:onToast(args, text)
        self:event("toast", {args = args, text = text})
        local c, now = self.current, clock()
        local lower = string.lower(text)
        if c and c.outcome ~= "claimed" and (c.active or now - (c.endedAt or 0) <= 2)
            and (lower:find("delivery failed", 1, true) or lower:find("returned to its nest", 1, true)) then
            c.outcome, c.outcomeTime, c.message = "delivery-rejected", now, text
            c.reason = "detail penyebab belum diberikan game"
            c.correlation = "latest-local-carry-time-window"
        end
    end
    function r:onField(uid, record)
        if self.current and self.current.uid == uid then
            self:event("field", {uid = uid, state = record and record.State or "Gone",
                version = record and record.Version, droppedAt = record and record.DroppedAt})
        end
    end
    function r:onSpeed(selected, active, reason)
        self:event("speed-mode", {selected = selected, active = active, reason = reason})
    end
    function r:read(which, limit)
        local c = self.current
        if which == "previous" then c = self.previous end
        local result = {serverTime = clock(), sampleInterval = 0.1, windowSeconds = 30,
            maxSamples = 300, maxEvents = 200, recording = c ~= nil and c.active == true,
            notices = copy(self.notices), capture = c and copy(c) or nil}
        if result.capture then
            limit = math.clamp(tonumber(limit) or 300, 1, 300)
            while #result.capture.samples > limit do table.remove(result.capture.samples, 1) end
        end
        return result
    end
    return r
end
-- END DELIVERY RECORDER CORE

Delivery = newDeliveryRecorder(function() return Workspace:GetServerTimeNow() end, function(uid)
    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local force = root and root:FindFirstChild("ASESpeedVelocity")
    local record = Field.records[uid]
    local sample = {
        position = root and clean(root.Position), velocity = root and clean(root.AssemblyLinearVelocity),
        walkSpeed = hum and hum.WalkSpeed, anchored = root and root.Anchored,
        humanoidState = hum and tostring(hum:GetState()), health = hum and hum.Health,
        ragdollEndTime = LP:GetAttribute("RagdollEndTime"), running = State.running,
        selectedBoost = Speed.selected, activeBoost = Speed.multiplier,
        carryMultiplier = Delivery and Delivery.current and Delivery.current.carryMultiplier,
        forcePresent = force ~= nil, forceEnabled = force and force.Enabled,
        forceTarget = force and {x = force.PlaneVelocity.X, z = force.PlaneVelocity.Y}, fieldReady = Field.ready,
        fieldState = record and record.State, fieldVersion = record and record.Version,
        characterReady = root ~= nil and hum ~= nil,
    }
    return sample, root
end)
do
    local toastFeed = networking and networking:FindFirstChild("RE/Toasts/Line")
    if toastFeed and toastFeed:IsA("RemoteEvent") then
        connect(toastFeed.OnClientEvent, function(...)
            local args, strings = table.pack(...), {}
            local function gather(value, depth)
                if type(value) == "string" then table.insert(strings, value:sub(1, 2000))
                elseif type(value) == "table" and depth < 3 then
                    local n = 0
                    for _, child in pairs(value) do
                        n += 1; if n > 40 then break end
                        gather(child, depth + 1)
                    end
                end
            end
            gather(args, 0)
            local message = table.concat(strings, " "):sub(1, 6000)
            Delivery:onToast(clean(args), message)
            debugLog("delivery.toast", {message = message, args = args})
        end)
    end
    connect(game:GetService("RunService").Heartbeat, guarded("delivery.sample", function()
        Delivery:sample(false)
    end))
    local trace = new("BindableFunction", {Name = "DeliveryTrace"}, gui)
    trace.OnInvoke = function(which, limit) return Delivery:read(which, limit) end
    gui:SetAttribute("DeliveryToastFeed", toastFeed ~= nil)
    debugLog("delivery.recorder-ready", {toastFeed = toastFeed ~= nil, interval = 0.1, window = 30})
    if carryKnown and carryState then
        local record = Field.records[carryUid]
        Delivery:onCarry({IsCarrying = true, Uid = carryUid,
            AssetCategory = record and record.AssetCategory, AreaId = record and record.AreaId})
    end
end

-- Read-only diagnostics: scan/cache checks without enabling movement or prompts.
local diagnostic = new("BindableFunction", {Name = "Diagnostics"}, gui)
diagnostic.OnInvoke = function()
    local matches, detected = collectEggs()
    return {
        version = "4.39-straight-flight", alive = alive, running = State.running,
        phase = debugPhase, workerAlive = Worker.alive, workerStarts = Worker.starts,
        workerLastActivity = Worker.lastActivity,
        workerActivityAge = Worker.lastActivity and os.clock() - Worker.lastActivity,
        workerError = Worker.error, waitingCharacter = Worker.waitingRig,
        workerLastError = Worker.lastError, workerRetryAt = Worker.retryAt,
        selectedAreas = table.clone(State.selectedAreas),
        filterScan = lastFilterScan,
        filterPrefsSource = previousPrefsSource,
        filterPrefsFile = findExecutorGlobal("readfile") ~= nil and PREF_FILE or nil,
        autoNewAreas = State.autoNewAreas,
        startupMs = gui:GetAttribute("UIReadyMs"), fieldReady = Field.ready,
        fieldPending = Field.pending, fieldError = Field.error,
        pickupMode = CONFIG.useRealInput and "input" or CONFIG.pickupMode,
        returnHomePending = State.returnHomePending,
        pathHorizon = CONFIG.pathHorizon, navigationTurnSpeed = CONFIG.navigationTurnSpeed,
        speedMultiplier = Speed.multiplier, speedRequested = Speed.applied, speedOverwritten = Speed.rejected,
        speedMethod = Speed.mode or (Speed.force and "physics" or "game"),
        speedTargetStuds = Speed.target, speedMoving = Speed.moving,
        speedSelectedMultiplier = Speed.selected, speedStopReason = Speed.reason,
        speedForceEnabled = Speed.force ~= nil and Speed.force.Enabled == true,
        speedBraking = Speed.goal ~= nil and Speed.brakeAtGoal ~= false,
        detected = detected, matching = #matches, scanMs = lastScanMs,
        scans = scanCount, rarityResolves = resolveCount,
        hasBase = resolveAutoBase() ~= nil, basePlot = State.homePlot, baseSource = State.homeSource,
        carryFeed = carryFeed ~= nil, claimFeed = claimFeed ~= nil,
        deliveryRecording = Delivery.current ~= nil and Delivery.current.active == true,
        deliverySamples = Delivery.current and #Delivery.current.samples or 0,
        deliveryOutcome = Delivery.current and Delivery.current.outcome,
        deliveryToastFeed = gui:GetAttribute("DeliveryToastFeed"),
    }
end

--==============================================================
-- WINDUI (optional community UI library). Loaded over HTTP; if it fails the
-- built-in panel above stays visible as the fallback. The headless host GUI
-- keeps DebugLogs / Diagnostics / attributes for external tooling either way.
--==============================================================
do
    local WINDUI_URLS = {
        "https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua",
    }
    -- WindUI diunduh BELAKANGAN (task.spawn); panel bawaan tayang instan,
    -- jadi tidak ada jeda "loading" sebelum UI muncul dan script siap pakai.
    gui.Enabled = true
    main.Visible = true
    local canLoad = type(loadstring) == "function" and type(game.HttpGet) == "function"

    task.spawn(function()
    warn("[ASE-BOOT 4.35] 08 before-windui-download")
    local WindUI
    if canLoad then
        for _, url in ipairs(WINDUI_URLS) do
            local ok, lib = pcall(function()
                warn("[ASE-BOOT 4.35] 09 fetching " .. url)
                local source = game:HttpGet(url)
                if not alive or rawget(_G, "AutoStealEggsEpoch") ~= myEpoch then
                    error("startup superseded by newer execution")
                end
                -- v1.6.66's no-writefile branch loads its Studio icon shim,
                -- which waits for ReplicatedStorage.GetIcons for 99999 seconds.
                -- Replace only that exact dependency with static Lucide data.
                local studioIcons = 'local d=b(game:GetService"ReplicatedStorage":WaitForChild("GetIcons",99999):InvokeServer())'
                local first, last = source:find(studioIcons, 1, true)
                if not first or source:find(studioIcons, last + 1, true) then
                    error("unsupported WindUI icon loader; refusing to run")
                end
                source = source:sub(1, first - 1)
                    .. 'local d={Icons={lucide=ASE_LUCIDE},IconsType="lucide"}'
                    .. source:sub(last + 1)
                warn("[ASE-BOOT 4.35] 10 windui-compile bytes=" .. tostring(#source))
                -- The observed native crash occurs inside library init, before
                -- CreateWindow. Avoid optional executor-native GUI/reference
                -- helpers in this chunk only; never modify executor globals.
                -- These lexical locals are inherited by the bundled modules.
                local compatibility = [[
local function cloneref(value) return value end
local clonereference = cloneref
local function protectgui() end
local syn = nil
local writefile = nil
local ASE_LUCIDE = {
    egg="rbxassetid://117851493400222", play="rbxassetid://135609604299893",
    zap="rbxassetid://130551565616516", info="rbxassetid://124560466474914",
    x="rbxassetid://110786993356448", minus="rbxassetid://118026365011536",
    check="rbxassetid://93898873302694", search="rbxassetid://121018724060431",
    menu="rbxassetid://77021539815611", camera="rbxassetid://79950339943067",
    copy="rbxassetid://78979572434545", folder="rbxassetid://80846616596607",
    settings="rbxassetid://80758916183665", maximize="rbxassetid://76045941763188",
    ["chevron-down"]="rbxassetid://134243273101015",
    ["chevron-right"]="rbxassetid://92473583511724",
    ["arrow-left"]="rbxassetid://102531941843733",
    ["arrow-right"]="rbxassetid://113692007244654",
    ["external-link"]="rbxassetid://129331830773832",
    -- Complete set of literal Lucide names referenced by this pinned release.
    -- CreateWindow indexes expand[1]/expand[2] directly: partial packs break it.
    ["expand"]="rbxassetid://137492887754537",
    ["chevrons-up-down"]="rbxassetid://131833120209646",
    ["code"]="rbxassetid://107380207681249",
    ["command"]="rbxassetid://93648221906330",
    ["key"]="rbxassetid://96510194465420",
    ["lock"]="rbxassetid://134724289526879",
    ["log-out"]="rbxassetid://84895399304975",
    ["minimize"]="rbxassetid://121304296213645",
    ["mouse-pointer-click"]="rbxassetid://107150227368485",
    ["move"]="rbxassetid://116138709011735",
    ["palette"]="rbxassetid://86350350950064",
    ["panda"]="rbxassetid://132509022802512",
    ["repeat"]="rbxassetid://121886242955173",
    ["server"]="rbxassetid://92188766517878",
    ["signature"]="rbxassetid://114402748013000",
    ["sliders-horizontal"]="rbxassetid://85538382643347",
    ["square-mouse-pointer"]="rbxassetid://76141850603920",
    ["table"]="rbxassetid://109109148250737",
    ["table-of-contents"]="rbxassetid://135044763275414",
    ["terminal"]="rbxassetid://106783148545356",
    ["text-cursor-input"]="rbxassetid://107551944047171",
    ["toggle-right"]="rbxassetid://90411952142550",
    ["triangle-alert"]="rbxassetid://125920361880643",
    ["alert-triangle"]="rbxassetid://125920361880643",
    ["type"]="rbxassetid://133543553793564",
    ["user"]="rbxassetid://81589895647169",
    ["watch"]="rbxassetid://130544621618405",
}
local function gethui()
    return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end
warn("[ASE-BOOT 4.35] 11a windui-static-icons-playergui")
]]
                local chunk, compileError = loadstring(compatibility .. source)
                if not chunk then error(compileError) end
                warn("[ASE-BOOT 4.35] 11 windui-library-init")
                return chunk()
            end)
            warn("[ASE-BOOT 4.35] 12 library-result=" .. tostring(ok))
            if ok and type(lib) == "table" and type(lib.CreateWindow) == "function" then
                WindUI = lib
                break
            end
        end
    end

    if WindUI then
        if not alive or rawget(_G, "AutoStealEggsEpoch") ~= myEpoch then return end
        local syncingToggle, syncingFilter = false, false
        local function selectedList()
            local list = {}
            for _, name in ipairs(TIER_ORDER) do
                if State.selected[name] then table.insert(list, name) end
            end
            return list
        end
        local tierList = {}
        for i, name in ipairs(TIER_ORDER) do tierList[i] = name end

        local built, buildErr = pcall(function()
            warn("[ASE-BOOT 4.35] 13 before-create-window")
            local window = WindUI:CreateWindow({
                Title = "Steal An Egg — Auto Steal",
                Icon = "egg",
                Author = "v4.39 • straight flight",
                Folder = "AutoStealEggs",
                Size = UDim2.fromOffset(560, 470),
                ToggleKey = Enum.KeyCode.RightControl,
                Transparent = true,
                Theme = "Dark",
                Resizable = true,
                SideBarWidth = 170,
            })
            warn("[ASE-BOOT 4.35] 14 window-created")
            windWindow = window
            if not alive or rawget(_G, "AutoStealEggsEpoch") ~= myEpoch then
                window:Destroy()
                windWindow = nil
                return
            end

            local mainTab = window:Tab({ Title = "Utama", Icon = "play" })
            local boostTab = window:Tab({ Title = "Boost", Icon = "zap" })
            local infoTab = window:Tab({ Title = "Info", Icon = "info" })

            local statusPara = mainTab:Paragraph({ Title = "Status", Desc = (statusText.Text:gsub("^Status: ", "")) })
            local statsPara = mainTab:Paragraph({ Title = "Statistik", Desc = statsLabel.Text })
            local logPara = mainTab:Paragraph({ Title = "Log", Desc = logLabel.Text })

            local toggle = mainTab:Toggle({
                Title = "Auto Steal",
                Desc = "RightShift juga bisa (toggle key bawaan skrip)",
                Value = State.running,
                Callback = function(state)
                    if syncingToggle then return end
                    setRunning(state == true)
                end,
            })
            mainTab:Button({ Title = "Auto Base", Desc = "Baca ulang plot base (B)", Callback = function() refreshBase() end })
            mainTab:Button({
                Title = "Ambil Snapshot Debug",
                Desc = "session " .. debugSession,
                Callback = function()
                    debugLog("manual.snapshot", snapshot())
                    addLog("Debug snapshot: " .. debugSession)
                    pcall(function() WindUI:Notify({ Title = "Snapshot disimpan", Content = debugSession, Duration = 3, Icon = "camera" }) end)
                end,
            })
            mainTab:Button({
                Title = "Lihat / Salin Log",
                Desc = "tampilkan 150 log terakhir (copy manual Ctrl+C)",
                Callback = function() presentLog() end,
            })

            local dropdown = mainTab:Dropdown({
                Title = "Filter kelangkaan",
                Desc = "Dropdown = tier yang dicentang. ≥ Legendary juga memasukkan Mythic dst.; Legendary saja = tepat satu tier.",
                Values = tierList,
                Value = selectedList(),
                Multi = true,
                AllowNone = true,
                Callback = function(option)
                    if syncingFilter or type(option) ~= "table" then return end
                    if not applyFilterSelection(State.selected, option) then return end
                    debugLog("filter.change", { source = "windui" })
                    refreshChips()
                    collectEggs()
                    if uiHooks.filterSummary then uiHooks.filterSummary(filterScanText()) end
                end,
            })
            local syncingAreas = false
            collectEggs()
            local filterPara = mainTab:Paragraph({Title = "Hasil filter (rarity DAN tempat)", Desc = filterScanText()})
            uiHooks.filterSummary = function(text) pcall(function() filterPara:SetDesc(text) end) end
            local function selectedAreaList()
                local result = {}
                for _, area in ipairs(AREA_LIST) do
                    if State.selectedAreas[area] then table.insert(result, area) end
                end
                return result
            end
            warn("[ASE-BOOT 4.35] 15 before-area-dropdown")
            local areaDropdown = mainTab:Dropdown({
                Title = "Filter tempat",
                Desc = "Pilih area asal telur. Wajib lolos tempat DAN rarity. Kosong = tidak ambil.",
                Values = AREA_LIST, Value = selectedAreaList(), Multi = true, AllowNone = true,
                Callback = function(options)
                    if syncingAreas or type(options) ~= "table" then return end
                    if not applyFilterSelection(State.selectedAreas, options) then return end
                    debugLog("filter.area-change", {areas = table.concat(selectedAreaList(), ",")})
                    collectEggs()
                    uiHooks.filterSummary(filterScanText())
                end,
            })
            warn("[ASE-BOOT 4.35] 16 area-dropdown-created")
            local function setAllAreas(enabled)
                for _, area in ipairs(AREA_LIST) do State.selectedAreas[area] = enabled end
                syncingAreas = true
                pcall(function() areaDropdown:Select(selectedAreaList()) end)
                syncingAreas = false
                debugLog("filter.area-change", {areas = table.concat(selectedAreaList(), ",")})
                if saveFilterPrefs then saveFilterPrefs() end
                collectEggs()
                uiHooks.filterSummary(filterScanText())
            end
            mainTab:Button({Title = "Semua tempat", Callback = function() setAllAreas(true) end})
            mainTab:Button({Title = "Kosongkan tempat", Callback = function() setAllAreas(false) end})
            mainTab:Toggle({
                Title = "Auto ambil area baru",
                Desc = "Area di luar daftar 13 (event/update baru game) otomatis ikut diindex. OFF = hanya area di dropdown.",
                Value = State.autoNewAreas,
                Callback = function(state)
                    State.autoNewAreas = state == true
                    debugLog("filter.auto-new-areas", {enabled = State.autoNewAreas})
                    collectEggs()
                    uiHooks.filterSummary(filterScanText())
                end,
            })
            mainTab:Button({ Title = "Semua tier", Callback = function() setFromTier(-1); refreshChips() end })
            mainTab:Button({ Title = "Kosongkan", Callback = function() setFromTier(999, true); refreshChips() end })
            mainTab:Button({ Title = "≥ Epic", Callback = function() setFromTier(4); refreshChips() end })
            mainTab:Button({ Title = "≥ Legendary", Callback = function() setFromTier(5); refreshChips() end })
            mainTab:Button({ Title = "Legendary saja", Callback = function()
                if applyFilterSelection(State.selected, {"Legendary"}) then
                    debugLog("filter.change", {source = "legendary-only"})
                    refreshChips()
                end
            end })
            mainTab:Button({ Title = "≥ Secret", Callback = function() setFromTier(8); refreshChips() end })

            local speedPara = boostTab:Paragraph({ Title = "Kecepatan", Desc = speedLabel.Text })
            boostTab:Button({ Title = "GAME SPEED (tanpa boost)", Callback = function() requestSpeed(1); addLog("Boost dimatikan.") end })
            for _, multiplier in ipairs({100, 200, 300, 400, 500, 600, 800, 1000}) do
                boostTab:Button({ Title = tostring(multiplier) .. " stud/s • CFrame", Callback = function()
                    requestSpeed(multiplier)
                    addLog("CFrame speed " .. tostring(multiplier) .. " stud/s dipilih.")
                end })
            end

            infoTab:Paragraph({ Title = "Build", Desc = "v4.39 • straight flight + filter\nsession " .. debugSession })
            infoTab:Paragraph({ Title = "Diagnostik delivery", Desc = "Rekaman 30 detik per percobaan aktif otomatis, termasuk saat Auto Steal OFF dan kamu bermain manual." })
            infoTab:Paragraph({ Title = "Catatan", Desc = "GAME SPEED memakai Humanoid:MoveTo. Preset 100–1000 memakai CFrame step horizontal dari metode Dice, mengikuti rute script. Belum menjamin delivery diterima server. Rute memutar footprint treadmill; kalau tetap terjebak/ke-anchor di treadmill, script mengirim Space otomatis (maks 3x per 5s, hanya saat terkonfirmasi di treadmill)." })

            uiHooks.toggle = function(on)
                if syncingToggle then return end
                syncingToggle = true
                pcall(function() toggle:Set(on == true) end)
                syncingToggle = false
            end
            uiHooks.status = function(t) pcall(function() statusPara:SetDesc(t) end) end
            uiHooks.stats = function(t) pcall(function() statsPara:SetDesc(t) end) end
            uiHooks.log = function(t) pcall(function() logPara:SetDesc(t) end) end
            uiHooks.speed = function(t) pcall(function() speedPara:SetDesc(t) end) end
            uiHooks.filter = function()
                if syncingFilter then return end
                syncingFilter = true
                pcall(function() dropdown:Select(selectedList()) end)
                syncingFilter = false
                collectEggs()
                if uiHooks.filterSummary then uiHooks.filterSummary(filterScanText()) end
            end
            uiHooks.notify = function(title, content)
                pcall(function() WindUI:Notify({ Title = title, Content = content, Duration = 6, Icon = "alert-triangle" }) end)
            end

            gui.Enabled = false
            gui:SetAttribute("WindUI", true)
            -- Pegang container window untuk takeover eksekusi berikutnya.
            -- Upaya pertama sinkron (tanpa yield) supaya killer berkala tidak
            -- sempat mengira window sendiri sebagai rival.
            do
                local container = stealWindowContainer(gui)
                if container then rawset(_G, "AutoStealEggsWindUI", container) end
            end
            task.spawn(function()
                for _ = 1, 6 do
                    if typeof(rawget(_G, "AutoStealEggsWindUI")) == "Instance" then break end
                    local container = stealWindowContainer(gui)
                    if container then rawset(_G, "AutoStealEggsWindUI", container) break end
                    task.wait(0.5)
                end
            end)
        end)

        if not built then
            gui:SetAttribute("WindUI", false)
            if windWindow then pcall(function() windWindow:Destroy() end); windWindow = nil end
            warn("[AutoStealEggs] WindUI gagal dipasang; panel bawaan tetap dipakai: " .. tostring(buildErr))
        else
            main.Visible = false
            gui.Enabled = false
            pcall(function() WindUI:Notify({ Title = "Auto Steal siap", Content = "v4.39", Duration = 4, Icon = "egg" }) end)
            debugLog("windui.ready", { version = WindUI.Version })
        end
    else
        gui:SetAttribute("WindUI", false)
        debugLog("windui.unavailable", nil, "WARN")
    end
    end)
end

requestFieldSnapshot()
refreshBase()
addLog("map: " .. (function()
    local n = 0
    for _ in pairs(CATEGORY_RARITY) do n += 1 end
    return n
end)() .. " kategori raritas baked")
if CONFIG.autoStart then setRunning(true) end
