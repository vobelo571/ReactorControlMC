-- Reactor Control v1.1 build 3

-- ----------------------------------------------------------------------------------------------------
local computer = require("computer")
local image = require("image")
local buffer = require("doubleBuffering")
local shell = require("shell")
local event = require("event")
local component = require("component")
local fs = require("filesystem")
local term = require("term")
local unicode = require("unicode")
local bit = require("bit32")
-- ----------------------------------------------------------------------------------------------------

buffer.setResolution(160, 50)
buffer.clear(0x000000)

local lastTime = computer.uptime()
local exit = false
local version = "1.1"
local build = "3"
local progVer = version .. "." .. build

local imagesFolder = "/home/images/" -- Путь к изображению
local dataFolder = "/home/data/"
local imgPath = imagesFolder .. "reactorGUI.pic"
local imgPathWhite = imagesFolder .. "reactorGUI_white.pic"
local configPath = dataFolder .. "config.lua"

if not fs.exists(imagesFolder) then
    fs.makeDirectory(imagesFolder)
end
if not fs.exists(dataFolder) then
    fs.makeDirectory(dataFolder)
end
if not fs.exists(configPath) then
    local file = io.open(configPath, "w")
    if file then
        file:write("-- Конфигурация программы Reactor Control v" .. version .."\n")
        file:write("-- Прежде чем что-то изменять, пожалуйста внимательно читайте описание!\n\n")
        file:write("porog = 50000 -- Минимальное значение порога жидкости в mB\n\n")
        file:write("-- Впишите никнеймы игроков которым будет разрешеннен доступ к ПК, обязательно ради вашей безопасности!\n")
        file:write("users = {} -- Пример: {\"Flixmo\", \"Nickname1\"} -- Именно что с кавычками и запятыми!\n")
        file:write("usersold = {} -- Не трогайте, может заблокировать ПК!\n\n")
        file:write("-- Тема интерфейса в системе по стандарту\n")
        file:write("theme = false -- (false темная, true светлая)\n\n")
        file:write("updateCheck = true -- (false не проверять на наличие обновлений, true проверять обновления)\n\n")
        file:write("debugLog = false\n\n")
        file:write("isFirstStart = true\n\n")
        file:write("-- После внесение изменений сохраните данные (Ctrl+S) и выйдите из редактора (Ctrl+W)\n")
        file:write("-- Если в будущем захотите поменять данные то пропишите \"cd data\" затем \"edit config.lua\"\n")
        file:close()
    else
        io.stderr:write("Ошибка: не удалось создать файл " .. configPath .. "\n")
    end
end

local ok, err = pcall(function()
    dofile(configPath)
end)
if not ok then
    io.stderr:write("Ошибка загрузки конфига: " .. tostring(err) .. "\n")
    return
end

local any_reactor_on = false
local any_reactor_off = false

local reactors = 0
local metric = 0
local status_metric = "Auto"
local metricRf = "Rf"
local metricMb = "Mb"
local second = 0
local minute = 0
local hour = 0
local testvalue = 0
local rf = 0
local fluidInMe = 0
local flux_network = false
local flux_checked = false

local consoleLines = {}
local work = false
local starting = false
local offFluid = false

local reactor_work       = {}
local reactor_aborted    = {}
local temperature        = {}
local reactor_type       = {}
local reactor_address    = {}
local reactors_proxy     = {}
local reactor_rf         = {}
local reactor_getcoolant = {}
local reactor_maxcoolant = {}
local reactor_depletionTime = {}
local reactor_ConsumptionPerSecond = {}
local reactor_level = {}
local reactor_rods_filled = {}
local reactor_rods_total = {}
local reactor_rods_type = {}
local reactor_rods_cache_at = {}
local adapters_proxy = {}
local adapters_address = {}
local reactor_adapter_index = {}
-- transposer-скан делаем лениво (только по команде @rods), чтобы не нагружать старт
local transposers_proxy = {}
local transposers_address = {}
local last_me_address = nil
local me_network = false
local me_proxy = nil
local lastValidFluid = 0
local maxThreshold = 10^12
local reason = nil
local depletionTime = 0
local consumeSecond = 0
local changelog = nil

local isChatBox = component.isAvailable("chat_box") or false
local chatBox = isChatBox and component.chat_box or nil
local chatThread = nil
local chatCommands = {
    ["@help"] = true,
    ["@status"] = true,
    ["@rods"] = true,
    ["@tpscan"] = true,
    ["@api"] = true,
    ["@setporog"] = true,
    ["@start"] = true,
    ["@stop"] = true,
    ["@restart"] = true,
    ["@exit"] = true,
    -- ["@changelog"] = true,
    ["@useradd"] = true,
    ["@userdel"] = true,
    ["@info"] = true
}

local widgetCoords = {
    {10, 6}, {36, 6}, {65, 6}, {91, 6},
    {10, 18}, {36, 18}, {65, 18}, {91, 18},
    {10, 30}, {36, 30}, {65, 30}, {91, 30}
}

local config = {
    clickArea19 = {x1=4,  y1=44, x2=9,  y2=46}, -- Кнопка 🔧 (x:5, y:44)
    clickArea20 = {x1=4,  y1=47, x2=9,  y2=49}, -- Кнопка ⓘ (x:5, y:47)

    clickArea1  = {x1=12,  y1=44, x2=37, y2=46}, -- Отключить реакторы (x:13, y:44)
    clickArea2  = {x1=12,  y1=47, x2=37, y2=49}, -- Рестарт программы (x:13, y:47)

    clickArea4  = {x1=40, y1=44, x2=64, y2=46}, -- Запуск реакторов (x:41, y:44)
    clickArea3  = {x1=40, y1=47, x2=64, y2=49}, -- Выход из программы (x:41, y:47)

    clickArea5  = {x1=67, y1=44, x2=86, y2=46}, -- Обновить МЭ (x:68, y:44)
    clickArea6  = {x1=67, y1=47, x2=86, y2=49}, -- Метрика (x:68, y:47)
    -- Координаты для кнопок на виджетах
    clickArea7 = {x1=widgetCoords[1][1]+5, y1=widgetCoords[1][2]+9, x2=widgetCoords[1][1]+11, y2=widgetCoords[1][2]+10}, -- Реактор 1
    clickArea8 = {x1=widgetCoords[2][1]+5, y1=widgetCoords[2][2]+9, x2=widgetCoords[2][1]+11, y2=widgetCoords[2][2]+10}, -- Реактор 2
    clickArea9 = {x1=widgetCoords[3][1]+5, y1=widgetCoords[3][2]+9, x2=widgetCoords[3][1]+11, y2=widgetCoords[3][2]+10}, -- Реактор 3
    clickArea10 = {x1=widgetCoords[4][1]+5, y1=widgetCoords[4][2]+9, x2=widgetCoords[4][1]+11, y2=widgetCoords[4][2]+10}, -- Реактор 4
    clickArea11 = {x1=widgetCoords[5][1]+5, y1=widgetCoords[5][2]+9, x2=widgetCoords[5][1]+11, y2=widgetCoords[5][2]+10}, -- Реактор 5
    clickArea12 = {x1=widgetCoords[6][1]+5, y1=widgetCoords[6][2]+9, x2=widgetCoords[6][1]+11, y2=widgetCoords[6][2]+10}, -- Реактор 6
    clickArea13 = {x1=widgetCoords[7][1]+5, y1=widgetCoords[7][2]+9, x2=widgetCoords[7][1]+11, y2=widgetCoords[7][2]+10}, -- Реактор 7
    clickArea14 = {x1=widgetCoords[8][1]+5, y1=widgetCoords[8][2]+9, x2=widgetCoords[8][1]+11, y2=widgetCoords[8][2]+10}, -- Реактор 8
    clickArea15 = {x1=widgetCoords[9][1]+5, y1=widgetCoords[9][2]+9, x2=widgetCoords[9][1]+11, y2=widgetCoords[9][2]+10}, -- Реактор 9
    clickArea16 = {x1=widgetCoords[10][1]+5, y1=widgetCoords[10][2]+9, x2=widgetCoords[10][1]+11, y2=widgetCoords[10][2]+10}, -- Реактор 10
    clickArea17 = {x1=widgetCoords[11][1]+5, y1=widgetCoords[11][2]+9, x2=widgetCoords[11][1]+11, y2=widgetCoords[11][2]+10}, -- Реактор 11
    clickArea18 = {x1=widgetCoords[12][1]+5, y1=widgetCoords[12][2]+9, x2=widgetCoords[12][1]+11, y2=widgetCoords[12][2]+10}, -- Реактор 12
}
local colors = {
    bg = 0x202020,
    bg2 = 0x101010,
    bg3 = 0x3c3c3c,
    bg4 = 0x969696,
    bg5 = 0xff0000,
    textclr = 0xcccccc,
    textbtn = 0xffffff,
    whitebtn = nil,
    whitebtn2 = 0x38afff,
    msginfo = 0x61ff52,
    msgwarn = 0xfff700,
    msgerror = 0xff0000,
}

-- ----------------------------------------------------------------------------------------------------

-- Блок обработки топливных стержней удалён по запросу пользователя.

local function brailleChar(dots)
    return unicode.char(
        10240 +
        (dots[8] or 0) * 128 +
        (dots[7] or 0) * 64 +
        (dots[6] or 0) * 32 +
        (dots[4] or 0) * 16 +
        (dots[2] or 0) * 8 +
        (dots[5] or 0) * 4 +
        (dots[3] or 0) * 2 +
        (dots[1] or 0)
    )
end

local braill0 = {
    {1,1,1,0,1,0,1,0},
    {1,0,1,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill1 = {
    {0,1,1,1,0,1,0,1},
    {0,0,0,0,0,0,0,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill2 = {
    {1,1,0,0,1,1,1,0},
    {1,0,1,0,1,0,0,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill3 = {
    {1,1,0,0,1,1,0,0},
    {1,0,1,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill4 = {
    {1,0,1,0,1,1,0,0},
    {1,0,1,0,1,0,1,0},
    {0,0,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill5 = {
    {1,1,1,0,1,1,0,0},
    {1,0,0,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill6 = {
    {1,1,1,0,1,1,1,0},
    {1,0,0,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill7 = {
    {1,1,0,0,0,0,0,0},
    {1,0,1,0,1,0,1,0},
    {0,0,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill8 = {
    {1,1,1,0,1,1,1,0},
    {1,0,1,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill9 = {
    {1,1,1,0,1,1,0,0},
    {1,0,1,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill_minus = {
    {0,0,0,0,1,1,0,0},
    {0,0,0,0,1,0,0,0},
    {0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0},
}
local braill_dot = {
    {0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0},
}

local brail_console = {
    {0,0,0,0,1,1,1,1},
    {0,0,1,1,0,0,0,0}
}

local brail_fluid = {
    {0,1,0,1,1,1,1,1},
    {1,0,1,0,1,1,1,1},
    {1,1,0,1,0,0,0,0},
    {1,1,1,0,0,0,0,0}
}

local brail_greenbtn = {
    {0,0,0,1,1,1,0,1},
    {0,0,0,0,1,0,0,0},
    {0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0},
}

local brail_redbtn = {
    {0,0,0,0,0,1,0,0},
    {0,0,0,0,1,1,0,0},
    {0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0},
}

local brail_thunderbolt = {
    {0,0,0,0,0,1,0,0},
    {0,1,1,0,1,1,0,1},
    {0,0,0,1,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}

local brail_cherta = {
    {1,0,1,0,1,0,1,0},
    {1,0,1,1,1,0,1,0},
    {0,0,0,0,1,0,1,0},
    {1,0,1,0,1,0,1,0},
    {0,0,1,1,0,1,0,1},
    {0,1,0,1,0,1,0,1},
    {0,0,1,1,1,0,1,0},
}

local brail_time = {
    {1,1,1,0,0,1,1,0},
    {1,1,0,1,1,0,0,1},
    {1,0,1,1,0,0,0,0},
    {0,1,1,1,0,0,0,0},
}

local button1 = {
    {0,0,0,0,1,1,1,1},
    {0,0,0,0,1,0,1,1},
    {1,1,1,1,1,1,1,1},
    {0,0,0,0,0,1,1,1},
    {1,1,0,1,0,0,0,0},
    {1,1,1,0,0,0,0,0},
    {1,1,1,1,0,0,0,0},
    {1,1,1,1,1,1,1,0},
    {1,1,1,1,1,1,0,1},
}

local button1_push = {
    {0,0,0,0,0,0,1,1},
    {0,0,0,0,0,0,1,0},
    {1,1,1,1,1,1,1,1},
    {0,0,0,0,0,0,0,1},
    {0,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
    {1,1,0,0,0,0,0,0},
}

local brail_status = {
    {0,0,0,1,1,1,1,1}, -- Уголки
    {0,0,1,0,1,1,1,1},
    {1,1,1,1,1,0,0,0},
    {1,1,1,1,0,1,0,0},
}

local brail_fields = {
    {0,0,0,0,0,1,1,1},
    {0,0,0,0,1,0,1,1},
    {1,1,1,0,0,0,0,0},
    {1,1,0,1,0,0,0,0},
    {1,1,0,0,1,1,1,1},
    {1,1,1,1,0,0,0,0},
}
local brail_verticalbar = {
    {0,0,0,0,0,0,1,1},
    {0,0,0,0,1,1,1,1},
    {0,0,1,1,1,1,1,1},
    {1,1,1,1,1,1,1,1},
}

-- ----------------------------------------------------------------------------------------------------
local function saveCfg(param)
    local file = io.open(configPath, "w")
    if not file then
        io.stderr:write("Ошибка: не удалось открыть файл для записи.\n")
        return
    end

    file:write("-- Конфигурация программы Reactor Control v" .. version .."\n")
    file:write("-- Прежде чем что-то изменять, пожалуйста внимательно читайте описание!\n\n")
    file:write(string.format("porog = %d -- Минимальное значение порога жидкости в mB\n\n", math.max(0, porog)))
    
    -- users
    file:write("-- Впишите никнеймы игроков которым будет разрешеннен доступ к ПК, обязательно ради вашей безопасности!\n")
    file:write("users = {")
    for i, user in ipairs(users) do
        file:write(string.format("%q", user))
        if i < #users then
            file:write(", ")
        end
    end
    file:write("} -- Пример: {\"Flixmo\", \"Nickname1\"} -- Именно что с кавычками и запятыми!\n")

    file:write("usersold = {")
    for i, user in ipairs(usersold) do
        file:write(string.format("%q", user))
        if i < #users then
            file:write(", ")
        end
    end
    file:write("} -- Не трогайте вообще, даже при удалении пользователей, оставьте оно само очистится, можно трогать только users но не usersold, может заблокировать ПК!\n\n")
    
    -- theme
    file:write("-- Тема интерфейса в системе по стандарту\n")
    file:write(string.format("theme = %s -- Тема интерфейса (false тёмная, true светлая)\n\n", tostring(theme)))
    file:write(string.format("updateCheck = %s -- (false не проверять на наличие обновлений, true проверять обновления)\n\n", tostring(updateCheck)))
    file:write(string.format("debugLog = %s\n\n", tostring(debugLog)))
    file:write(string.format("isFirstStart = %s\n\n", tostring(isFirstStart)))
    file:write("-- После внесение изменений сохраните данные (Ctrl+S) и выйдите из редактора (Ctrl+W)\n")
    file:write("-- Для запуска основой программы перейдите в домашнюю директорию \"cd ..\", и напишите \"main.lua\"\n")
    
    file:close()
end

local function switchTheme(val)
    if theme == true then
        colors = {
            bg = 0x000000,
            bg2 = 0x202020,
            bg3 = 0xffffff,
            bg4 = 0x5a5a5a,
            bg5 = 0xff0000,
            textclr = 0x3f3f3ff,
            textbtn = 0x303030,
            whitebtn = nil,
            whitebtn2 = 0x38afff,
            msginfo = 0x61ff52,
            msgwarn = 0xfff700,
            msgerror = 0xff0000,
        }
        saveCfg()
    else
        colors = {
            bg = 0x202020,
            bg2 = 0x101010,
            bg3 = 0x3c3c3c,
            bg4 = 0x969696,
            bg5 = 0xff0000,
            textclr = 0xcccccc,
            textbtn = 0xffffff,
            whitebtn = nil,
            whitebtn2 = 0x38afff,
            msginfo = 0x61ff52,
            msgwarn = 0xfff700,
            msgerror = 0xff0000,
        }
        saveCfg()
    end
end

local function initReactors()
    reactors = 0
    reactor_address = {}
    reactors_proxy = {}

    for address, ctype in component.list("htc_reactors") do
        reactors = reactors + 1
        reactor_address[reactors] = address
        reactors_proxy[reactors] = component.proxy(address)
        if reactors >= 12 then
            break
        end
    end
    for i = 1, reactors do
        reactor_rf[i] = 0
        reactor_getcoolant[i] = 0
        reactor_maxcoolant[i] = 0
        temperature[i] = 0
        reactor_aborted[i] = false
        reactor_depletionTime[i] = 0
        reactor_level[i] = 1
    end
end

local function initAdapters()
    adapters_address = {}
    adapters_proxy = {}
    reactor_adapter_index = {}
    local idx = 0
    for address in component.list("adapter") do
        idx = idx + 1
        adapters_address[idx] = address
        adapters_proxy[idx] = component.proxy(address)
    end
    for i = 1, math.min(reactors, idx) do
        reactor_adapter_index[i] = i
    end
end

local function initTransposers()
    transposers_address = {}
    transposers_proxy = {}
    local idx = 0
    for address in component.list("transposer") do
        idx = idx + 1
        transposers_address[idx] = address
        transposers_proxy[idx] = component.proxy(address)
    end
end

local function initMe()
    me_network = false
    me_proxy = nil
    current_me_address = nil
    offFluid = false
    reason = nil

    if component.isAvailable("me_interface") then
        for address in component.list("me_interface") do
            current_me_address = address
            me_proxy = component.proxy(address)
            me_network = me_proxy ~= nil
            break
        end
    elseif component.isAvailable("me_controller") then
        for address in component.list("me_controller") do
            current_me_address = address
            me_proxy = component.proxy(address)
            me_network = me_proxy ~= nil
            break
        end
    end

    return current_me_address
end

local function initChatBox()
    isChatBox = component.isAvailable("chat_box") or false
    if isChatBox then
        chatBox = component.chat_box
        chatBox.setName("§6§lКомплекс§7§o")
    end
end

local function initFlux()
    flux_network = (component.isAvailable("flux_controller") and true or false)
end

local function drawDigit(x, y, braill, color)
    buffer.drawText(x,     y,     color, brailleChar(braill[1]))
    buffer.drawText(x,     y + 1, color, brailleChar(braill[3]))
    buffer.drawText(x + 1, y,     color, brailleChar(braill[2]))
    buffer.drawText(x + 1, y + 1, color, brailleChar(braill[4]))
end

-- Работа с текстом
local function centerText(text, totalWidth)
    local textLen = unicode.len(text)
    local pad = math.floor((totalWidth - textLen) / 2)
    if pad < 0 then pad = 0 end
    return string.rep(" ", pad) .. text
end

local function shortenNameCentered(name, maxLength)
    maxLength = maxLength or 12
    if unicode.len(name) > maxLength then
        name = unicode.sub(name, 1, maxLength - 3) .. "..."
    end
    return centerText(name, maxLength)
end

local function shortenText(text, maxLength)
    maxLength = maxLength or 18
    if unicode.len(text) > maxLength then
        return unicode.sub(text, 1, maxLength - 3) .. "..."
    end
    return text
end

-- local function centerMSG(x, y, msg, color)
--     local len = unicode.len(msg)
--     local startX = x - math.floor(len / 2)
--     buffer.drawText(startX, y, color, msg)
--     buffer.drawChanges()
-- end

-- ----------------------------------------------------------------------------------------------------
local function animatedButton(push, x, y, text, tx, ty, length, time, clearWidth, color, textcolor)
    local btn = push == 1 and button1 or button1_push
    local bgColor = color or 0x059bff
    local tColor = textcolor or colors.textbtn
    local clear = clearWidth or length
    if not text then tx = x  end
    local ftext = text or "* Клик *"
    local ftx = tx or x
    local fty = ty or y + 1
    local ftime = time or 0.3

    if push == 1 then
        buffer.drawRectangle(x, y + 1, length, 1, bgColor, 0, " ")
        buffer.drawText(ftx, fty, tColor, shortenNameCentered(ftext, length))
    end
    -- Левая граница
    buffer.drawText(x - 1, y, bgColor, brailleChar(btn[4]))
    buffer.drawText(x - 1, y + 1, bgColor, brailleChar(btn[3]))
    buffer.drawText(x - 1, y + 2, bgColor, brailleChar(btn[5]))

    -- Правая граница
    buffer.drawText(x + length, y, bgColor, brailleChar(btn[2]))
    buffer.drawText(x + length, y + 1, bgColor, brailleChar(btn[3]))
    buffer.drawText(x + length, y + 2, bgColor, brailleChar(btn[6]))

    -- Центральная линия
    for i = 0, length - 1 do
        buffer.drawText(x + i, y,     bgColor, brailleChar(btn[1]))
        buffer.drawText(x + i, y + 2, bgColor, brailleChar(btn[7]))
    end

    if push == 0 and clearWidth and clearWidth > length then
        buffer.drawText(x - 2, y + 1, tColor, " ")
        buffer.drawText(x - 2, y, tColor, " ")
        buffer.drawText(x - 2, y + 2, tColor, " ")
        buffer.drawText(x + length + 1, y + 1, tColor, " ")
        buffer.drawText(x + length + 1, y, tColor, " ")
        buffer.drawText(x + length + 1, y + 2, tColor, " ")
        buffer.drawRectangle(x, y + 1, length, 1, bgColor, 0, " ")
        buffer.drawText(ftx, fty, tColor, shortenNameCentered(ftext, length))
    end

    if push == 0 then os.sleep(ftime) end
end

-- ----------------------------------------------------------------------------------------------------
local function lerpColor(c1, c2, t)
    local r1, g1, b1 = bit.rshift(c1, 16) % 0x100, bit.rshift(c1, 8) % 0x100, c1 % 0x100
    local r2, g2, b2 = bit.rshift(c2, 16) % 0x100, bit.rshift(c2, 8) % 0x100, c2 % 0x100
    local r = r1 + (r2 - r1) * t
    local g = g1 + (g2 - g1) * t
    local b = b1 + (b2 - b1) * t
    return bit.lshift(math.floor(r), 16) + bit.lshift(math.floor(g), 8) + math.floor(b)
end

-- НЕВЕРОЯТНЫЙ КОСТЫЛЬ, ПРОСТИТЕ)
local function safeCallwg(proxy, method, default, ...)
    if proxy and proxy[method] then
        local ok, result = pcall(proxy[method], proxy, ...)
        if ok and result ~= nil then
            -- Для числовых значений по умолчанию гарантируем возврат числа
            if type(default) == "number" then
                local numberResult = tonumber(result)
                if numberResult then
                    return numberResult
                else
                    -- Логируем нечисловой результат
                    local logFile = io.open("/home/reactor_errors.log", "a")
                    if logFile then
                        logFile:write(string.format("[%s] safeCall non-number error: method=%s, result=%s\n",
                            os.date("%Y-%m-%d %H:%M:%S"),
                            tostring(method),
                            tostring(result)))
                        logFile:close()
                    end
                    return default
                end
            else
                return result
            end
        else
            -- Логируем ошибку
            local logFile = io.open("/home/reactor_errors.log", "a")
            if logFile then
                logFile:write(string.format("[%s] safeCall error: method=%s, result=%s\n",
                    os.date("%Y-%m-%d %H:%M:%S"),
                    tostring(method),
                    tostring(result)))
                logFile:close()
            end

            -- Убрал рекурсивный вызов safeCall чтобы избежать потенциальной бесконечной рекурсии
            -- Вместо этого просто возвращаем значение по умолчанию
            return default
        end
    end
    return default
end

local function callMethodFlexible(proxy, method, ...)
    -- Некоторые методы OC-драйверов работают как "free function" и НЕ ожидают self.
    -- Пробуем оба варианта: with self и without self.
    if not proxy or not proxy[method] then
        return false, nil
    end
    local fn = proxy[method]

    local ok, res = pcall(fn, proxy, ...)
    if ok and res ~= nil then
        return true, res
    end

    ok, res = pcall(fn, ...)
    if ok and res ~= nil then
        return true, res
    end

    return false, nil
end

local function secondsToHMS(totalSeconds)
    if type(totalSeconds) ~= "number" or totalSeconds < 0 then
        totalSeconds = 0
    end
    local hours   = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = math.floor(totalSeconds % 60)
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function getDepletionTime(num)
    if reactors == 0 then
        return 0
    end

    local minReactorTime = math.huge
    
    if #reactor_depletionTime == 0 then
        for i = 1, reactors do
            reactor_depletionTime[i] = 0
        end
    end

    for i = 1, reactors do
        local rods = safeCallwg(reactors_proxy[i], "getAllFuelRodsStatus", nil)
        local isFluid = reactor_type[i] == "Fluid"
        local reactorTime = 0

        if type(rods) == "table" and #rods > 0 then
            local maxRod = 0
            for _, rod in ipairs(rods) do
                if type(rod) == "table" and rod[6] then
                    -- Добавлена проверка на число
                    local fuelLeft = tonumber(rod[6]) or 0
                    if isFluid then
                        fuelLeft = fuelLeft / 2
                    end
                    if fuelLeft > maxRod then
                        maxRod = fuelLeft
                    end
                end
            end

            reactorTime = maxRod
            reactor_depletionTime[i] = reactorTime
            
            if reactorTime > 0 and reactorTime < minReactorTime then
                minReactorTime = reactorTime
            end
        else
            reactor_depletionTime[i] = 0
        end
    end

    if minReactorTime == math.huge then
        return 0
    else
        return math.floor(minReactorTime or 0)
    end
end

local function drawVerticalProgressBar(x, y, height, value, maxValue, colorBottom, colorTop, colorInactive)
    if not maxValue or maxValue <= 0 then
        maxValue = 1
    end
    if not value or value < 0 then
        value = 0
    end
    value = math.min(value, maxValue)
    if value > maxValue then
        value = maxValue
    end

    local totalParts = height * 4
    local filledParts = math.floor(totalParts * (value / maxValue))

    buffer.drawRectangle(x, y, 1, height, colorInactive, 0, " ")

    local fullBlocks = math.floor(filledParts / 4)
    local remainder = filledParts % 4

    for i = 0, fullBlocks - 1 do
        local pos = (i + 1) / height
        local clr = lerpColor(colorBottom, colorTop, pos)
        buffer.drawText(x, y + height - i - 1, clr, brailleChar(brail_verticalbar[4]))
    end

    if remainder > 0 then
        local pos = (fullBlocks + 1) / height
        local clr = lerpColor(colorBottom, colorTop, pos)
        buffer.drawText(x, y + height - fullBlocks - 1, clr, brailleChar(brail_verticalbar[remainder]))
    end
end


local function formatRFwidgets(value)
    if type(value) ~= "number" then
        return "Ген: 0 RF/t"
    end

    local suffixes = {"", "k", "m", "g"}
    local i = 1

    if value < 10000 then
        return "Ген: " .. tostring(value) .. " RF/t"
    end

    while value >= 1000 and i < #suffixes do
        value = value / 1000
        i = i + 1
    end

    local str = string.format("%.1f", value)
    str = str:gsub("%.0$", "")

    return "Ген: " .. str .. " " .. suffixes[i] .. "RF/t"
end

local function getRodTotalSlotsByLevel(level)
    -- Общее количество позиций в сетке стержней в GUI.
    -- ВАЖНО: внутри могут стоять "реакторные обшивки", их учитывать не нужно:
    -- реальная ёмкость по стержням = (позиции, где реально может стоять стержень) * уровень.
    -- Эти "позиции под стержни" мы берём из getSelectStatusRod (кол-во table-ответов).
    -- Но если по какой-то причине API недоступен — fallback на 24.
    local lvl = tonumber(level)
    if lvl and lvl >= 1 then
        return 24
    end
    return nil
end

-- forward declaration (UI uses it before definition later in file)
local getFuelRodsFromSelectStatus

local function formatFuelTypeName(itemId)
    itemId = tostring(itemId or "")
    local lower = itemId:lower()
    if lower:find("mox", 1, true) then
        return "MOX"
    end
    if lower:find("uranium", 1, true) then
        return "Уран"
    end
    if lower:find("thorium", 1, true) then
        return "Торий"
    end
    if lower:find("plutonium", 1, true) then
        return "Плутоний"
    end
    if lower:find("americium", 1, true) then
        return "Америций"
    end
    if lower:find("neptun", 1, true) then
        return "Нептуний"
    end
    local short = itemId:match(":(.+)$") or itemId
    short = short:gsub("_", " ")
    return short
end

local function refreshReactorRodsInfo(i)
    if not reactors_proxy[i] then
        reactor_rods_filled[i] = 0
        reactor_rods_total[i] = getRodTotalSlotsByLevel(reactor_level[i])
        reactor_rods_type[i] = "-"
        reactor_rods_cache_at[i] = computer.uptime()
        return
    end

    -- Для UI нам нужно:
    -- 1) Сколько ячеек занято стержнями (filledCells)
    -- 2) Сколько всего ячеек "под стержни" (totalCells) — без реакторных обшивок
    -- 3) Основной тип топлива (по самому частому itemId)
    local filledCells = 0
    local totalCells = 0
    local countsByItem = {}

    if reactors_proxy[i] and reactors_proxy[i].getSelectStatusRod then
        -- Индексация у драйвера может быть 0-based/1-based, поэтому сканируем 0..64.
        for idx = 0, 64 do
            local ok, rod = callMethodFlexible(reactors_proxy[i], "getSelectStatusRod", idx)
            if ok and type(rod) == "table" then
                totalCells = totalCells + 1
                -- формат как key-value массив: {"item", "<id>", "type", "...", ...}
                local itemId = nil
                if rod[1] == "item" and type(rod[2]) == "string" then
                    itemId = rod[2]
                end
                if itemId and itemId ~= "" and itemId ~= "nil" then
                    filledCells = filledCells + 1
                    countsByItem[itemId] = (countsByItem[itemId] or 0) + 1
                end
            end
        end
    end

    if totalCells <= 0 then
        -- fallback: если поиндексный API временно недоступен
        totalCells = getRodTotalSlotsByLevel(reactor_level[i]) or 0
    end

    local mainType = nil
    local mainSlots = 0
    for itemId, n in pairs(countsByItem) do
        if n > mainSlots then
            mainSlots = n
            mainType = itemId
        end
    end

    reactor_rods_filled[i] = filledCells
    reactor_rods_total[i] = totalCells
    reactor_rods_type[i] = mainType and formatFuelTypeName(mainType) or "-"
    reactor_rods_cache_at[i] = computer.uptime()
end

local function ensureReactorRodsInfoFresh(i)
    local now = computer.uptime()
    local last = reactor_rods_cache_at[i]
    if type(last) ~= "number" or (now - last) >= 5 then
        local ok = pcall(refreshReactorRodsInfo, i)
        if not ok then
            -- никогда не роняем UI из‑за стержней
            reactor_rods_filled[i] = reactor_rods_filled[i] or 0
            reactor_rods_total[i] = reactor_rods_total[i] or getRodTotalSlotsByLevel(reactor_level[i])
            reactor_rods_type[i] = reactor_rods_type[i] or "-"
            reactor_rods_cache_at[i] = now
        end
    end
end


local function drawWidgets()
    if reactors <= 0 then
        buffer.drawRectangle(5, 5, 114, 37, colors.bg4, 0, " ")
        buffer.drawRectangle(37, 19, 50, 3, colors.bg2, 0, " ")
        buffer.drawRectangle(36, 20, 52, 1, colors.bg2, 0, " ")
        local cornerPos = {
            {36, 19, 1}, {87, 19, 2},
            {87, 21, 3}, {36, 21, 4}
        }
        for _, c in ipairs(cornerPos) do
            buffer.drawText(c[1], c[2], colors.bg2, brailleChar(brail_status[c[3]]))
        end
        buffer.drawText(43, 20, 0xcccccc, "У вас не подключенно ни одного реактора!")
        buffer.drawText(40, 20, 0xffd900, "⚠")
        return
    end

    buffer.drawRectangle(5, 5, 114, 37, colors.bg4, 0, " ")

    for i = 1, math.min(reactors, #widgetCoords) do
        if reactor_aborted[i] == false then
            local x, y = widgetCoords[i][1], widgetCoords[i][2]
            buffer.drawRectangle(x + 1, y, 20, 12, colors.bg, 0, " ")
            buffer.drawRectangle(x, y + 1, 22, 10, colors.bg, 0, " ")

            buffer.drawText(x,  y,  colors.bg, brailleChar(brail_status[1]))
            buffer.drawText(x + 21, y,  colors.bg, brailleChar(brail_status[2]))
            buffer.drawText(x + 21, y + 11,  colors.bg, brailleChar(brail_status[3]))
            buffer.drawText(x,  y + 11,  colors.bg, brailleChar(brail_status[4]))

            if reactor_work[i] then
                if (reactor_depletionTime[i] or 0) <= 0 then
                    local newTime = getDepletionTime(i)
                    if newTime > 0 then
                        reactor_depletionTime[i] = newTime
                    else
                        reactor_depletionTime[i] = 0
                    end
                else
                    reactor_depletionTime[i] = reactor_depletionTime[i] - 1
                end
            else
                reactor_depletionTime[i] = 0
            end

            ensureReactorRodsInfoFresh(i)

            buffer.drawText(x + 6,  y + 1,  colors.textclr, "Реактор #" .. i)
            buffer.drawText(x + 4,  y + 2,  colors.textclr, "Нагрев: " .. (temperature[i] or "-") .. "°C")
            buffer.drawText(x + 4,  y + 3,  colors.textclr, formatRFwidgets(reactor_rf[i]))
            local cellsFilled = tonumber(reactor_rods_filled[i]) or 0
            local cellsTotal = reactor_rods_total[i]
            local lvl = tonumber(reactor_level[i]) or 1
            if lvl < 1 then lvl = 1 end

            local rodsFilled = cellsFilled * lvl
            local rodsLine = "Стержни: " .. tostring(rodsFilled)
            if type(cellsTotal) == "number" and cellsTotal > 0 then
                local rodsTotal = cellsTotal * lvl
                rodsLine = rodsLine .. "/" .. tostring(rodsTotal)
            end
            buffer.drawText(x + 4,  y + 4,  colors.textclr, rodsLine)
            buffer.drawText(x + 4,  y + 5,  colors.textclr, "Топливо: " .. tostring(reactor_rods_type[i] or "-"))
            buffer.drawText(x + 4,  y + 6,  colors.textclr, "Распад: " .. secondsToHMS(reactor_depletionTime[i] or 0))
            animatedButton(1, x + 6, y + 9, (reactor_work[i] and "Отключить" or "Включить"), nil, nil, 10, nil, nil, (reactor_work[i] and 0xfd3232 or 0x2beb1a))
            if reactor_type[i] == "Fluid" then
                drawVerticalProgressBar(x + 1, y + 1, 9, reactor_getcoolant[i], reactor_maxcoolant[i], 0x0044FF, 0x00C8FF, colors.bg2)
            end
        else
            local x, y = widgetCoords[i][1], widgetCoords[i][2]
            buffer.drawRectangle(x + 1, y, 20, 12, colors.msgwarn, 0, " ")
            buffer.drawRectangle(x, y + 1, 22, 10, colors.msgwarn, 0, " ")

            buffer.drawText(x,  y,  colors.msgwarn, brailleChar(brail_status[1]))
            buffer.drawText(x + 21, y,  colors.msgwarn, brailleChar(brail_status[2]))
            buffer.drawText(x + 21, y + 11,  colors.msgwarn, brailleChar(brail_status[3]))
            buffer.drawText(x,  y + 11,  colors.msgwarn, brailleChar(brail_status[4]))

            buffer.drawText(x + 6,  y + 1,  colors.msgerror, "Реактор #" .. i)
            buffer.drawText(x + 4,  y + 3,  colors.msgerror, "Нагрев: " .. (temperature[i] or "-") .. "°C")
            buffer.drawText(x + 4,  y + 4,  colors.msgerror, "Тип: " .. (reactor_type[i] or "-"))
            buffer.drawText(x + 4,  y + 5,  colors.msgerror, "Cтатус:")
            buffer.drawText(x + 4,  y + 6,  colors.msgerror, "Аварийно отключен!")
            buffer.drawText(x + 4,  y + 7,  colors.msgerror, "Причина:")
            buffer.drawText(x + 4,  y + 8,  colors.msgerror, (reason or "Неизвестная ошибка!"))
            if reactor_type[i] == "Fluid" then
                drawVerticalProgressBar(x + 1, y + 1, 9, reactor_getcoolant[i], reactor_maxcoolant[i], 0x0044FF, 0x00C8FF, colors.bg2)
            end
        end
    end
end

local braillMap = {
    [0] = braill0,
    [1] = braill1,
    [2] = braill2,
    [3] = braill3,
    [4] = braill4,
    [5] = braill5,
    [6] = braill6,
    [7] = braill7,
    [8] = braill8,
    [9] = braill9,
    ["-"] = braill_minus,
    ["."] = braill_dot,
}

local function drawNumberWithText(centerX, centerY, number, digitWidth, color, suffix, suffixColor)
    suffixColor = suffixColor or color

    local digits = {}
    local widths = {}
    local strNum = tostring(number)

    for i = 1, #strNum do
        local ch = strNum:sub(i, i)
        local n = tonumber(ch)
        if n then
            table.insert(digits, braillMap[n])
            table.insert(widths, digitWidth)
        elseif braillMap[ch] then
            table.insert(digits, braillMap[ch])
            if ch == "." then
                table.insert(widths, 1)
            else
                table.insert(widths, digitWidth)
            end
        end
    end

    local suffixWidth = suffix and #suffix or 0
    local totalWidth = 0
    for _, w in ipairs(widths) do totalWidth = totalWidth + w end
    totalWidth = totalWidth + (suffixWidth > 0 and (suffixWidth + 1) or 0)

    local startX = math.floor(centerX - totalWidth / 2)

    buffer.drawText(startX, centerY, colors.bg, string.rep(" ", totalWidth))

    local x = startX
    for i, digit in ipairs(digits) do   
        drawDigit(x, centerY, digit, color)
        x = x + widths[i]
    end

    if suffix and suffixWidth > 0 then
        buffer.drawText(x, centerY, suffixColor, suffix)
    end
end

local function utf8len(str)
    local _, count = str:gsub("[^\128-\191]", "")
    return count
end

-- вырезаем подстроку по символам
local function utf8sub(str, startChar, numChars)
    local startIndex = 1
    while startChar > 1 do
        local c = str:byte(startIndex)
        if not c then break end
        if c < 128 or c >= 192 then
            startChar = startChar - 1
        end
        startIndex = startIndex + 1
    end

    local currentIndex = startIndex
    while numChars > 0 and currentIndex <= #str do
        local c = str:byte(currentIndex)
        if not c then break end
        if c < 128 or c >= 192 then
            numChars = numChars - 1
        end
        currentIndex = currentIndex + 1
    end

    return str:sub(startIndex, currentIndex - 1)
end

-- перенос текста с учётом UTF-8
local function wrapText(msg, limit)
    local result = {}
    limit = limit or 34

    while utf8len(msg) > limit do
        local chunk = utf8sub(msg, 1, limit)
        local spacePos = chunk:match(".*()%s")

        if spacePos then
            -- перенос по пробелу
            table.insert(result, msg:sub(1, spacePos - 1))
            msg = msg:sub(spacePos + 1)
        else
            -- перенос с дефисом
            table.insert(result, utf8sub(msg, 1, limit - 1) .. "-")
            msg = utf8sub(msg, limit)
        end
    end

    if utf8len(msg) > 0 then
        table.insert(result, msg)
    end

    return result
end

local function drawRightMenu()
    local startColor = colors.textclr
    local endColor   = colors.textclr
    local totalLines = #consoleLines
    local windowHeight = flux_network and 19 or 22
    buffer.drawRectangle(123, 5, 35, windowHeight, colors.bg, 0, " ")
    
    for i = 1, math.min(totalLines, windowHeight) do
        local entry = consoleLines[i]
        local t = (i - 1) / math.max(totalLines - 1, 1)
        local baseColor = entry.color or lerpColor(startColor, endColor, t)
        local alpha = 1 - t
        buffer.drawText(124, 4 + i, baseColor, entry.text or "", alpha)
    end

    -- if supportersText then
    --     buffer.drawText(124, 5, colors.textclr, "Спасибо за поддержку:")
    --     drawMarquee(124, 6, supportersText ..  "                            ", 0xF15F2C)
    -- end
    
    buffer.drawChanges()
end



local function message(msg, colormsg, limit, noStack)
    limit = limit or 34
    msg = tostring(msg)

    -- режем сообщение
    local parts = wrapText(msg, limit)

    local found = false

    if not noStack then
        -- ищем совпадение среди последних строк
        for i = #consoleLines, 11, -1 do
            local line = consoleLines[i]
            if line.textBase == msg then
                line.count = (line.count or 1) + 1

                -- пересобираем все части, икс только на последней
                local lastPart = parts[#parts] .. "(x" .. line.count .. ")"

                -- если влезает → заменяем последнюю строку
                if utf8len(lastPart) <= limit then
                    -- обновляем существующие строки
                    for j = 1, #parts - 1 do
                        local idx = i - (#parts - j)
                        if consoleLines[idx] then
                            consoleLines[idx].text = parts[j]
                        end
                    end
                    consoleLines[i].text = lastPart
                    found = true
                end

                break
            end
        end
    end

    -- если не нашли или не влезло → добавляем как новые строки
    if not found then
        for _, part in ipairs(parts) do
            table.remove(consoleLines, 1)
            table.insert(consoleLines, {
                text = part,
                textBase = msg, -- вся строка как ключ для стака
                color = colormsg,
                count = 1
            })
        end
    end

    drawRightMenu()
end


local function userUpdate()
    if not users or type(users) ~= "table" then
        message("Ошибка: users должен быть таблицей", nil, 34)
        return
    end

    if #users == 0 then
        message("Компьютер не защищен!", colors.msgwarn, 34)
        message("Перейдите в настройки и добавьте никнеймы в белый список", colors.msgwarn, 34)
    end

    local desiredUsers = {}
    for _, name in ipairs(users) do
        desiredUsers[name] = true
    end

    for _, name in ipairs(users) do
        local found = false
        for _, old in ipairs(usersold) do
            if old == name then
                found = true
                break
            end
        end
        if not found then
            table.insert(usersold, name)
            message("Добавлен новый пользователь:", nil, 34)
            message(name, nil, 34)
            computer.addUser(name)
            saveCfg()
        end
    end

    local i = 1
    while i <= #usersold do
        local name = usersold[i]
        if not desiredUsers[name] then
            table.remove(usersold, i)
            message("Пользователь удален:", nil, 34)
            message(name, nil, 34)
            computer.removeUser(name)
            saveCfg()
        else
            i = i + 1
        end
    end
end


local function safeCall(proxy, method, default, ...)
    if proxy and proxy[method] then
        local ok, result = pcall(proxy[method], proxy, ...)
        if ok and result ~= nil then
            -- Для числовых значений по умолчанию гарантируем возврат числа
            if type(default) == "number" then
                local numberResult = tonumber(result)
                if numberResult then
                    return numberResult
                else
                    -- Логируем нечисловой результат
                    local logFile = io.open("/home/reactor_errors.log", "a")
                    if logFile then
                        logFile:write(string.format("[%s] safeCall non-number error: method=%s, result=%s\n",
                            os.date("%Y-%m-%d %H:%M:%S"),
                            tostring(method),
                            tostring(result)))
                        logFile:close()
                    end
                    return default
                end
            else
                return result
            end
        else
            -- Логируем ошибку
            local logFile = io.open("/home/reactor_errors.log", "a")
            if logFile then
                logFile:write(string.format("[%s] safeCall error: method=%s, result=%s\n",
                    os.date("%Y-%m-%d %H:%M:%S"),
                    tostring(method),
                    tostring(result)))
                logFile:close()
            end

            if debugLog == true then
                message("'" .. method .. "': " .. tostring(result), colors.msgwarn, 34)
            end

            -- Убрал рекурсивный вызов safeCall чтобы избежать потенциальной бесконечной рекурсии
            -- Вместо этого просто возвращаем значение по умолчанию
            return default
        end
    end
    return default
end

local function getInventorySize(proxy)
    local size = safeCall(proxy, "getInventorySize", nil)
    if type(size) == "number" and size > 0 then
        return size, nil
    end
    for side = 0, 5 do
        size = safeCall(proxy, "getInventorySize", nil, side)
        if type(size) == "number" and size > 0 then
            return size, side
        end
    end
    size = safeCall(proxy, "getSizeInventory", nil)
    if type(size) == "number" and size > 0 then
        return size, nil
    end
    return nil, nil
end

local function getStackInSlot(proxy, side, slot)
    local stack
    if side == nil then
        stack = safeCall(proxy, "getStackInSlot", nil, slot)
        if type(stack) == "table" then
            return stack
        end
        stack = safeCall(proxy, "getStackInSlot", nil, slot, nil)
        if type(stack) == "table" then
            return stack
        end
    else
        stack = safeCall(proxy, "getStackInSlot", nil, side, slot)
        if type(stack) == "table" then
            return stack
        end
    end
    return nil
end

local function getAllStacks(proxy, side)
    local stacks
    if side == nil then
        stacks = safeCall(proxy, "getAllStacks", nil)
    else
        stacks = safeCall(proxy, "getAllStacks", nil, side)
    end
    if type(stacks) == "table" and type(stacks.getAll) == "function" then
        local ok, result = pcall(stacks.getAll, stacks)
        if ok then
            stacks = result
        end
    end
    if type(stacks) == "table" then
        return stacks
    end
    return nil
end

local function isFuelRodStack(stack)
    if type(stack) ~= "table" then
        return false
    end
    local name = tostring(stack.name or ""):lower()
    local label = tostring(stack.label or ""):lower()
    if name == "" and label == "" then
        return false
    end
    -- мягкая эвристика: в модах стержни почти всегда содержат rod/fuel или "стерж" в label
    if name:find("fuel", 1, true) or name:find("rod", 1, true) then
        return true
    end
    if label:find("стерж", 1, true) or label:find("rod", 1, true) then
        return true
    end
    return false
end

local function addFuelRodAgg(agg, key, addCount, stack)
    if not key or key == "" then
        key = "unknown"
    end
    addCount = tonumber(addCount) or 0
    if addCount <= 0 then
        addCount = 1
    end
    local e = agg[key]
    if not e then
        e = {count = 0, slots = 0, minP = nil, maxP = nil, sumP = 0, pN = 0}
        agg[key] = e
    end
    e.count = e.count + addCount
    e.slots = e.slots + 1

    -- если предмет отдаёт durability через damage/maxDamage — посчитаем сводку
    if type(stack) == "table" then
        local dmg = tonumber(stack.damage)
        local maxDmg = tonumber(stack.maxDamage)
        if dmg and maxDmg and maxDmg > 0 then
            local p = math.max(0, math.min(1, 1 - (dmg / maxDmg)))
            if e.minP == nil or p < e.minP then e.minP = p end
            if e.maxP == nil or p > e.maxP then e.maxP = p end
            e.sumP = e.sumP + p
            e.pN = e.pN + 1
        end
    end
end

local function addFuelRodAggPercent(agg, key, addCount, percent)
    addFuelRodAgg(agg, key, addCount, nil)
    local e = agg[key]
    if not e then
        return
    end
    if type(percent) == "number" then
        local p = math.max(0, math.min(1, percent))
        if e.minP == nil or p < e.minP then e.minP = p end
        if e.maxP == nil or p > e.maxP then e.maxP = p end
        e.sumP = e.sumP + p
        e.pN = e.pN + 1
    end
end

local function getInventorySizeOnSide(proxy, side)
    if side == nil then
        return safeCall(proxy, "getInventorySize", nil)
    end
    return safeCall(proxy, "getInventorySize", nil, side)
end

local function scanInventorySideForRods(proxy, side, size, agg)
    local stacks = getAllStacks(proxy, side)
    if stacks then
        for slot = 1, size do
            local stack = stacks[slot]
            if isFuelRodStack(stack) then
                addFuelRodAgg(agg, tostring(stack.name or stack.label or "unknown"), tonumber(stack.size) or 1, stack)
            end
        end
        return
    end
    for slot = 1, size do
        local stack = getStackInSlot(proxy, side, slot)
        if isFuelRodStack(stack) then
            addFuelRodAgg(agg, tostring(stack.name or stack.label or "unknown"), tonumber(stack.size) or 1, stack)
        end
    end
end

local function getFuelRodsFromInventory(proxy)
    -- Важно: некоторые компоненты имеют несколько "инвентарей" на разных сторонах.
    -- Чтобы не недосчитывать — сканируем все стороны (и вариант без side).
    local agg = {}
    local any = false

    -- сначала вариант без side (если компонент его поддерживает)
    local sizeNil = getInventorySizeOnSide(proxy, nil)
    if type(sizeNil) == "number" and sizeNil > 0 then
        scanInventorySideForRods(proxy, nil, sizeNil, agg)
        any = true
    end

    -- затем все стороны
    for side = 0, 5 do
        local size = getInventorySizeOnSide(proxy, side)
        if type(size) == "number" and size > 0 then
            scanInventorySideForRods(proxy, side, size, agg)
            any = true
        end
    end

    if any then
        return agg
    end
    return nil
end

local function getFuelRodsFromBestTransposer()
    -- Ищем среди всех транспозеров и их сторон инвентарь, где реально лежат стержни.
    -- Возвращаем agg и строку источника (для вывода).
    local bestAgg = nil
    local bestInfo = nil
    local bestScore = -1

    local tidx = 0
    for address in component.list("transposer") do
        tidx = tidx + 1
        local tp = component.proxy(address)
        if tp then
            for side = 0, 5 do
                -- some implementations may return a string -> force numeric conversion via numeric default
                local size = safeCall(tp, "getInventorySize", 0, side)
                if type(size) == "number" and size > 0 then
                    local stacks = safeCall(tp, "getAllStacks", nil, side)
                    if type(stacks) == "table" and type(stacks.getAll) == "function" then
                        local ok, all = pcall(stacks.getAll, stacks)
                        if ok then
                            stacks = all
                        end
                    end

                    local agg = {}
                    local found = 0
                    if type(stacks) == "table" then
                        for slot = 1, size do
                            local st = stacks[slot]
                            if isFuelRodStack(st) then
                                addFuelRodAgg(agg, tostring(st.name or st.label or "unknown"), tonumber(st.size) or 1, st)
                                found = found + 1
                            end
                        end
                    else
                        for slot = 1, size do
                            local st = safeCall(tp, "getStackInSlot", nil, side, slot)
                            if isFuelRodStack(st) then
                                addFuelRodAgg(agg, tostring(st.name or st.label or "unknown"), tonumber(st.size) or 1, st)
                                found = found + 1
                            end
                        end
                    end

                    if found > 0 and next(agg) ~= nil then
                        -- score: побольше найденных rod-слотов, затем побольше size (на случай 20 слотов)
                        local score = found * 1000 + size
                        if score > bestScore then
                            bestScore = score
                            bestAgg = agg
                            bestInfo = "Transposer #" .. tostring(tidx) .. " side " .. tostring(side) .. " (size " .. tostring(size) .. ")"
                        end
                    end
                end
            end
        end
    end

    return bestAgg, bestInfo
end

local function extractFirstStringWithColon(t)
    if type(t) ~= "table" then
        return nil
    end
    for _, v in pairs(t) do
        if type(v) == "string" and v:find(":", 1, true) then
            return v
        end
    end
    return nil
end

local function collectEligibleIntValuesFromRodRecord(rod, outSet)
    -- Пытаемся найти "размер стака" в статусе стержня.
    -- Часто первые 2-3 числа — координаты/позиции, а один из полей — размер стака (например 6).
    if type(rod) ~= "table" then
        return
    end
    outSet = outSet or {}
    for k, v in pairs(rod) do
        if type(v) == "number" then
            local iv = math.floor(v)
            if v == iv and iv >= 1 and iv <= 64 then
                -- отбрасываем наиболее вероятные "координатные" индексы и fuelLeft (6-й индекс уже встречался)
                if k ~= 1 and k ~= 2 and k ~= 3 and k ~= 6 then
                    outSet[iv] = true
                end
            end
        end
    end
    return outSet
end

local function recordHasEligibleIntValue(rod, target)
    if type(rod) ~= "table" or type(target) ~= "number" then
        return false
    end
    for k, v in pairs(rod) do
        if k ~= 1 and k ~= 2 and k ~= 3 and k ~= 6 and type(v) == "number" then
            if v == target then
                return true
            end
        end
    end
    return false
end

local function formatRodDebugValue(v)
    local tv = type(v)
    if tv == "string" then
        v = v:gsub("§.", "")
        if #v > 70 then
            v = v:sub(1, 67) .. "..."
        end
        return '"' .. v .. '"'
    elseif tv == "number" or tv == "boolean" then
        return tostring(v)
    elseif tv == "table" then
        return "{table}"
    else
        return "<" .. tv .. ">"
    end
end

local function dumpRodRecordToChat(rod, prefix)
    prefix = prefix or "rod"
    if not isChatBox then
        return
    end
    if type(rod) ~= "table" then
        chatBox.say("§7" .. prefix .. ": " .. tostring(rod))
        return
    end

    local parts = {}
    local n = #rod
    if n and n > 0 then
        for i = 1, math.min(n, 20) do
            table.insert(parts, tostring(i) .. "=" .. formatRodDebugValue(rod[i]))
        end
        if n > 20 then
            table.insert(parts, "...(#=" .. tostring(n) .. ")")
        end
    else
        table.insert(parts, "#=0")
    end

    local skeys = {}
    for k, _ in pairs(rod) do
        if type(k) == "string" then
            table.insert(skeys, k)
        end
    end
    table.sort(skeys)
    for i = 1, math.min(#skeys, 18) do
        local k = skeys[i]
        table.insert(parts, k .. "=" .. formatRodDebugValue(rod[k]))
    end
    if #skeys > 18 then
        table.insert(parts, "...(keys=" .. tostring(#skeys) .. ")")
    end

    local line = "§e" .. prefix .. ": "
    for _, p in ipairs(parts) do
        if #line + #p + 2 > 220 then
            chatBox.say(line)
            line = "§e" .. prefix .. "…: "
        end
        line = line .. p .. "; "
    end
    chatBox.say(line)
end

local function decodeKvArray(t)
    -- getAllFuelRodsStatus в твоей версии возвращает массив вида:
    -- {"item","modid:item","type","fuelrod","fuel",12568,"maxFuel",20000,...}
    if type(t) ~= "table" then
        return nil
    end
    local m = {}
    local n = #t
    if not n or n <= 1 then
        return m
    end
    local i = 1
    while i <= n - 1 do
        local k = t[i]
        local v = t[i + 1]
        if type(k) == "string" then
            m[k] = v
        end
        i = i + 2
    end
    return m
end

local function extractCountFromKv(kv)
    if type(kv) ~= "table" then
        return nil
    end
    return tonumber(
        kv.count or kv.size or kv.amount or kv.qty or kv.stack or kv.stackSize or kv.stack_size or kv.items
    )
end

getFuelRodsFromSelectStatus = function(proxy)
    -- Пытаемся получить состояние по каждому "индексу стержня".
    -- На практике метод есть в htc_reactors и требует integer index.
    if not proxy or not proxy.getSelectStatusRod then
        return nil
    end

    local agg = {}
    local any = false
    -- пробуем 0-based и 1-based индексы
    for idx = 0, 64 do
        local ok, rod = callMethodFlexible(proxy, "getSelectStatusRod", idx)
        if ok and type(rod) == "table" then
            local kv = decodeKvArray(rod) or {}
            local itemId = tostring(kv.item or rod.itemName or rod.item or rod.name or "")
            if itemId == "" or itemId == "nil" then
                itemId = tostring(extractFirstStringWithColon(rod) or "unknown")
            end

            -- Если мод отдаёт stack-size (1..6), обычно это будет count/size/amount.
            local cnt = extractCountFromKv(kv)
            if not cnt or cnt <= 0 then
                cnt = 1
            end

            local fuel = tonumber(kv.fuel or rod.fuel)
            local maxFuel = tonumber(kv.maxFuel or rod.maxFuel)
            local pct = nil
            if fuel and maxFuel and maxFuel > 0 then
                pct = fuel / maxFuel
            end

            -- Если слот пустой, в некоторых реализациях item может быть nil/"" — пропускаем такие.
            if itemId ~= "" and itemId ~= "nil" and itemId ~= "unknown" then
                addFuelRodAggPercent(agg, itemId, cnt, pct)
                any = true
            end
        end
    end

    if any and next(agg) ~= nil then
        return agg
    end
    return nil
end

local function getFuelRodsFromStatus(proxy)
    -- Самая точная попытка: поиндексно через getSelectStatusRod (если отдаёт stack-size).
    local byIdx = getFuelRodsFromSelectStatus(proxy)
    if byIdx and next(byIdx) ~= nil then
        return byIdx
    end

    local rods = safeCallwg(proxy, "getAllFuelRodsStatus", nil)
    if type(rods) ~= "table" or #rods == 0 then
        return nil
    end

    local agg = {}
    for _, rod in ipairs(rods) do
        if type(rod) == "table" then
            local kv = decodeKvArray(rod)
            local itemId = tostring((kv and kv.item) or rod.itemName or rod.item or rod.name or "")
            if itemId == "" or itemId == "nil" then
                itemId = tostring(extractFirstStringWithColon(rod) or "unknown")
            end

            -- В твоём debug нет поля с количеством "1..6", только fuel/maxFuel.
            -- Поэтому точное число предметов в слоте через adapter получить нельзя — считаем слоты.
            local fuel = kv and tonumber(kv.fuel) or tonumber(rod.fuel)
            local maxFuel = kv and tonumber(kv.maxFuel) or tonumber(rod.maxFuel)
            local pct = nil
            if fuel and maxFuel and maxFuel > 0 then
                pct = fuel / maxFuel
            end

            addFuelRodAggPercent(agg, itemId, 1, pct)
        else
            addFuelRodAgg(agg, "unknown", 1, nil)
        end
    end
    return agg
end

local function scanTransposersToChat()
    if not isChatBox then
        return
    end
    local foundAny = false
    local tidx = 0
    for address in component.list("transposer") do
        tidx = tidx + 1
        local tp = component.proxy(address)
        if tp then
            local anyInv = false
            for side = 0, 5 do
                -- some implementations may return a string -> force numeric conversion via numeric default
                local size = safeCall(tp, "getInventorySize", 0, side)
                if type(size) == "number" and size > 0 then
                    anyInv = true
                    foundAny = true

                    -- Быстрый поиск стержней на этой стороне
                    local rodSlots = 0
                    local exampleName = nil
                    local stacks = safeCall(tp, "getAllStacks", nil, side)
                    if type(stacks) == "table" and type(stacks.getAll) == "function" then
                        local ok, all = pcall(stacks.getAll, stacks)
                        if ok then
                            stacks = all
                        end
                    end
                    if type(stacks) == "table" then
                        for slot = 1, size do
                            local st = stacks[slot]
                            if isFuelRodStack(st) then
                                rodSlots = rodSlots + 1
                                if not exampleName then
                                    exampleName = tostring(st.name or st.label or "unknown")
                                end
                            end
                        end
                    else
                        for slot = 1, size do
                            local st = safeCall(tp, "getStackInSlot", nil, side, slot)
                            if isFuelRodStack(st) then
                                rodSlots = rodSlots + 1
                                if not exampleName then
                                    exampleName = tostring(st.name or st.label or "unknown")
                                end
                            end
                        end
                    end

                    local msg = "§7TP#" .. tostring(tidx) .. " side " .. tostring(side) .. " size " .. tostring(size)
                    if rodSlots > 0 then
                        msg = msg .. " §aRODS " .. tostring(rodSlots)
                        if exampleName then
                            msg = msg .. " §e(" .. exampleName .. ")"
                        end
                    end
                    chatBox.say(msg)
                end
            end
            if not anyInv then
                -- не спамим: выводим только если у транспозера вообще нет доступных инвентарей
                chatBox.say("§7TP#" .. tostring(tidx) .. " §8нет инвентарей на сторонах 0..5")
            end
        end
    end
    if tidx == 0 then
        chatBox.say("§cТранспозеры не найдены.")
        return
    end
    if not foundAny then
        chatBox.say("§eТранспозеры найдены, но инвентари на сторонах 0..5 не видны (или стержней там нет).")
    end
end

local function listFilteredMethodsToChat(title, proxy, patterns, maxLines)
    if not isChatBox then
        return
    end
    maxLines = maxLines or 18
    if not proxy or not proxy.address then
        chatBox.say("§7" .. title .. ": §8proxy=nil")
        return
    end

    local ok, methods = pcall(component.methods, proxy.address)
    if not ok or type(methods) ~= "table" then
        chatBox.say("§7" .. title .. ": §8нет component.methods")
        return
    end

    local names = {}
    for name, _ in pairs(methods) do
        if type(name) == "string" then
            local lower = name:lower()
            local matched = false
            for _, p in ipairs(patterns) do
                if lower:find(p, 1, true) then
                    matched = true
                    break
                end
            end
            if matched then
                table.insert(names, name)
            end
        end
    end
    table.sort(names)

    chatBox.say("§e" .. title .. " §7(фильтр, найдено " .. tostring(#names) .. "):")
    if #names == 0 then
        chatBox.say("§8(ничего подходящего)")
        return
    end

    local shown = 0
    local line = "§7"
    for _, n in ipairs(names) do
        local chunk = n
        if #line + #chunk + 2 > 220 then
            chatBox.say(line)
            line = "§7"
        end
        if line ~= "§7" then
            line = line .. ", "
        end
        line = line .. chunk
        shown = shown + 1
        if shown >= maxLines then
            break
        end
    end
    if line ~= "§7" then
        chatBox.say(line)
    end
    if #names > shown then
        chatBox.say("§7... и ещё " .. tostring(#names - shown))
    end
end

local function tryCallInterestingMethodsToChat(title, proxy, patterns, maxCalls)
    if not isChatBox then
        return
    end
    maxCalls = maxCalls or 8
    if not proxy then
        return
    end

    local ok, methods = pcall(component.methods, proxy.address)
    if not ok or type(methods) ~= "table" then
        return
    end

    local names = {}
    for name, _ in pairs(methods) do
        if type(name) == "string" then
            local lower = name:lower()
            local matched = false
            for _, p in ipairs(patterns) do
                if lower:find(p, 1, true) then
                    matched = true
                    break
                end
            end
            if matched then
                table.insert(names, name)
            end
        end
    end
    table.sort(names)

    local called = 0
    for _, n in ipairs(names) do
        if called >= maxCalls then
            break
        end
        -- вызываем только методы без аргументов (если нужен аргумент — будет ошибка, покажем её)
        local ok2, res = pcall(proxy[n], proxy)
        if ok2 then
            chatBox.say("§7" .. title .. "." .. n .. " -> §a" .. tostring(res))
        else
            -- чтобы не спамить, показываем только короткую ошибку
            local err = tostring(res)
            if #err > 120 then err = err:sub(1, 117) .. "..." end
            chatBox.say("§7" .. title .. "." .. n .. " -> §8(err) " .. err)
        end
        called = called + 1
    end
end

local function getFuelRodsSummary(inventoryProxy, statusProxy)
    -- 1) Самый точный путь без робота: transposer, подключённый к блоку реактора (видит реальный инвентарь)
    local tAgg, tInfo = getFuelRodsFromBestTransposer()
    if tAgg and next(tAgg) ~= nil then
        return tAgg, tInfo
    end

    -- 2) Если вдруг adapter экспонирует инвентарь — используем
    if inventoryProxy then
        local agg = getFuelRodsFromInventory(inventoryProxy)
        if agg and next(agg) ~= nil then
            return agg, nil
        end
    end

    -- 3) Фоллбек: статусные данные (НЕ дают stack-size 1..6, только записи/ресурс)
    if statusProxy then
        return getFuelRodsFromStatus(statusProxy), nil
    end
    return nil, nil
end

local function getReactorLevel(proxy)
    if not proxy then
        return 1
    end
    local methods = {
        "getReactorLevel",
        "getLevel",
        "getTier",
        "getReactorTier",
        "getStructureLevel",
    }
    for _, method in ipairs(methods) do
        local lvl = safeCall(proxy, method, nil)
        if type(lvl) == "number" and lvl >= 1 and lvl <= 6 then
            return math.floor(lvl)
        end
    end
    return 1
end

local function checkReactorStatus(num)
    any_reactor_on = false
    any_reactor_off = false

    for i = num or 1, num or reactors do
        local status = safeCall(reactors_proxy[i], "hasWork", false)
        if status == true then
            reactor_work[i] = true
            any_reactor_on = true
            work = true
        else
            reactor_work[i] = false
            any_reactor_off = true
        end
        if any_reactor_on and any_reactor_off then
            break
        end
    end
end


local function drawTimeInfo()
    local fl_y1 = 45
    if flux_network == true then
        fl_y1 = 46
    end
    buffer.drawRectangle(123, fl_y1, 35, 4, colors.bg, 0, " ") 
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1-1, colors.bg, brailleChar(brail_console[1]))
    end
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1+1, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(141, fl_y1, colors.textclr, "Время работы:")
    buffer.drawText(139, fl_y1, colors.bg2, brailleChar(brail_cherta[1]))
    buffer.drawText(139, fl_y1+1, colors.bg2, brailleChar(brail_cherta[2]))
    buffer.drawText(139, fl_y1+2, colors.bg2, brailleChar(brail_cherta[1]))
    buffer.drawText(139, fl_y1+3, colors.bg2, brailleChar(brail_cherta[1]))
    drawDigit(125, fl_y1+2, brail_time, 0xaa4b2e)
    -- ---------------------------------------------------------------------------
    buffer.drawRectangle(127, fl_y1+2, 12, 2, colors.bg, 0, " ")
    
    
    buffer.drawRectangle(140, fl_y1+2, 18, 2, colors.bg, 0, " ")

    if hour > 0 then
        if hour >= 100 and hour < 1000 and minute < 10 then 
            drawNumberWithText(146, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            drawNumberWithText(154, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
        elseif hour >= 100 and hour < 1000 and minute >= 10 then
            drawNumberWithText(145, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            drawNumberWithText(154, fl_y1+2, minute , 2, colors.textclr, "Min", colors.textclr)
        elseif hour >= 1000 then
            drawNumberWithText(150, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
        elseif hour < 10 and minute < 10 then
            drawNumberWithText(146, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            drawNumberWithText(152, fl_y1+2, minute , 2, colors.textclr, "Min", colors.textclr)
        elseif hour < 10 and minute >= 10 then
            drawNumberWithText(146, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            drawNumberWithText(153, fl_y1+2, minute , 2, colors.textclr, "Min", colors.textclr)
        elseif hour >= 10 and minute < 10 then
            drawNumberWithText(146, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            drawNumberWithText(153, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
        else
            drawNumberWithText(146, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            if minute < 10 then
                drawNumberWithText(153, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
            else
                drawNumberWithText(154, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
            end
        end
    else
        if minute < 10 and second < 10 then
            drawNumberWithText(147, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
            drawNumberWithText(153, fl_y1+2, second, 2, colors.textclr, "Sec", colors.textclr)
        elseif minute < 10 and second >= 10 then
            drawNumberWithText(146, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
            drawNumberWithText(153, fl_y1+2, second, 2, colors.textclr, "Sec", colors.textclr)
        elseif minute >= 10 and second < 10 then
            drawNumberWithText(146, fl_y1+2, minute , 2, colors.textclr, "Min", colors.textclr)
            drawNumberWithText(153, fl_y1+2, second, 2, colors.textclr, "Sec", colors.textclr)
        else
            drawNumberWithText(146, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
            if second < 10 then
                drawNumberWithText(153, fl_y1+2, second, 2, colors.textclr, "Sec", colors.textclr)
            else
                drawNumberWithText(154, fl_y1+2, second, 2, colors.textclr, "Sec", colors.textclr)
            end
        end
    end
    buffer.drawChanges()
end

local function drawStatic()
    local picture
    if theme == false then
        picture = image.load(imgPath)
    else
        picture = image.load(imgPathWhite)
    end

    if picture then
        buffer.drawImage(1, 1, picture)
    else
        buffer.drawText(1, 1, colors.msgerror, "Ошибка загрузки изображения! Проверьте наличие файлов 'image/reactorGUI.pic'")
        return
    end
    animatedButton(1, 5, 44, "🔧", nil, nil, 4, nil, nil, 0xa91df9, 0xffffff)
    animatedButton(1, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0xa91df9, 0x05e2ff)
    animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
    animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
    animatedButton(1, 68, 44, "МЭ: выкл.", nil, nil, 18, nil, nil, nil)
    animatedButton(1, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn)
    animatedButton(1, 41, 47, "Выход из программы.", nil, nil, 23, nil, nil, colors.whitebtn)
    animatedButton(1, 68, 47, "Метрика: " .. status_metric, nil, nil, 18, nil, nil, colors.whitebtn)

    buffer.drawText(123, 50, (theme and 0xc3c3c3 or 0x666666), "Reactor Control v" .. version .. "." .. build .. " by Flixmo")
    -- buffer.drawText(130, 50, (theme and 0xc3c3c3 or 0x666666), "by P1KaChU337") -- Контакты: VK: @p1kachu337, Discord: p1kachu337 TG: @sh1zurz
    
    buffer.drawChanges()
end

local function getTotalFluidConsumption()
    local total = 0
    local consumeSecond = 0
    
    for i = 1, #reactors_proxy do
        local reactor = reactors_proxy[i]
        if reactor_type[i] == "Fluid" then
            if reactor_work[i] then
                consumeSecond = safeCall(reactor, "getFluidCoolantConsume", 0) or 0
                reactor_ConsumptionPerSecond[i] = consumeSecond
                total = total + consumeSecond
            end
        end
    end
    
    return total
end

local function drawStatus(num)
    checkReactorStatus()
    if reactors >= 12 then
        reactors = 12
    end

    -- Сдвиг x с 87 на 89
    buffer.drawRectangle(89, 44, 31, 6, colors.bg, 0, " ")
    -- Сдвиг x с 88 на 90
    buffer.drawText(90, 44, colors.textclr, "Статус комплекса:")
    
    for i = 0, 31 - 1 do
        -- Сдвиг x с 87 на 89
        buffer.drawText(89 + i, 43, colors.bg, brailleChar(brail_console[1]))
    end
    for i = 0, 31 - 1 do
        -- Сдвиг x с 87 на 89
        buffer.drawText(89 + i, 45, colors.bg2, brailleChar(brail_console[2]))
    end

    -- Сдвиг x с 108 на 110
    buffer.drawText(110, 45, colors.bg2, brailleChar(brail_cherta[5]))
    buffer.drawText(110, 46, colors.bg2, brailleChar(brail_cherta[6]))
    buffer.drawText(110, 47, colors.bg2, brailleChar(brail_cherta[6]))
    buffer.drawText(110, 48, colors.bg2, brailleChar(brail_cherta[6]))
    buffer.drawText(110, 49, colors.bg2, brailleChar(brail_cherta[6]))

    -- Сдвиг x с 88 на 90
    buffer.drawText(90, 46, colors.textclr, "Кол-во реакторов: " .. reactors)

    if any_reactor_on == true then
        -- Сдвиг координат индикатора (110->112, 111->113, 115->117)
        buffer.drawRectangle(112, 47, 6, 1, 0x61ff52, 0, " ")
        buffer.drawRectangle(113, 46, 4, 3, 0x61ff52, 0, " ")
        buffer.drawText(112, 46, 0x61ff52, brailleChar(brail_status[1]))
        buffer.drawText(117, 46, 0x61ff52, brailleChar(brail_status[2]))
        buffer.drawText(117, 48, 0x61ff52, brailleChar(brail_status[3]))
        buffer.drawText(112, 48, 0x61ff52, brailleChar(brail_status[4]))
        buffer.drawText(113, 47, 0x0d9f00, "Work") 
    else
        -- Сдвиг координат индикатора (110->112, 111->113, 115->117)
        buffer.drawRectangle(112, 47, 6, 1, 0xfd3232, 0, " ")
        buffer.drawRectangle(113, 46, 4, 3, 0xfd3232, 0, " ")
        buffer.drawText(112, 46, 0xfd3232, brailleChar(brail_status[1]))
        buffer.drawText(117, 46, 0xfd3232, brailleChar(brail_status[2]))
        buffer.drawText(117, 48, 0xfd3232, brailleChar(brail_status[3])) 
        buffer.drawText(112, 48, 0xfd3232, brailleChar(brail_status[4]))
        buffer.drawText(113, 47, 0x9d0000, "Stop")
    end

    buffer.drawChanges()
end

local function round(num, digits)
    local mult = 10 ^ (digits or 0)
    local result = math.floor(num * mult + 0.5) / mult
    if result == math.floor(result) then
        return tostring(math.floor(result))
    else
        return tostring(result)
    end
end

local function formatRF(value)
    if type(value) ~= "number" then value = 0 end
    if metric == 0 then
        -- Auto
        if value >= 1e9 then
            return round(value / 1e9, 1), "gRf"
        elseif value >= 1e6 then
            return round(value / 1e6, 1), "mRf"
        elseif value >= 1e3 then
            return round(value / 1e3, 1), "kRf"
        else
            return round(value, 1), "Rf"
        end
    elseif metric == 1 then
        return round(value, 1), "Rf"
    elseif metric == 2 then
        return round(value / 1e3, 1), "kRf"
    elseif metric == 3 then
        return round(value / 1e6, 1), "mRf"
    elseif metric == 4 then
        return round(value / 1e9, 1), "gRf"
    end
end

local function formatFluxRF(value)
    if type(value) ~= "number" then
        return "0 Rf"
    end

    local suffixes = {"Rf", "kRf", "mRf", "gRf"}
    local i = 1

    while value >= 1000 and i < #suffixes do
        value = value / 1000
        i = i + 1
    end

    local str
    if value < 10 then
        str = string.format("%.2f", value)
    elseif value < 100 then
        str = string.format("%.1f", value)
    else
        str = string.format("%.0f", value)
    end

    str = str:gsub("%.0$", "")

    return str, suffixes[i]
end

local function formatFluid(value)
    if type(value) ~= "number" then value = 0 end
    if metric == 0 then
        -- Auto
        if value >= 1e9 then
            return round(value / 1e9, 1), "gMb"
        elseif value >= 1e6 then
            return round(value / 1e6, 1), "mMb"
        elseif value >= 1e3 then
            return round(value / 1e3, 1), "kMb"
        else
            return round(value, 1), "Mb"
        end
    elseif metric == 1 then
        return round(value, 1), "Mb"
    elseif metric == 2 then
        return round(value / 1e3, 1), "kMb"
    elseif metric == 3 then
        return round(value / 1e6, 1), "mMb"
    elseif metric == 4 then
        return round(value / 1e9, 1), "gMb"
    end
end

local function drawFluidinfo()
    local fl_y1 = 30
    if flux_network == true then fl_y1 = 27 end
    buffer.drawRectangle(123, fl_y1-1, 35, 4, colors.bg, 0, " ")
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1-2, colors.bg, brailleChar(brail_console[1]))
    end
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, fl_y1-1, colors.textclr, "Жидкости МЭ: выкл.")
    
    drawDigit(125, fl_y1+1, brail_fluid, 0x0088ff)

    local val, unit = formatFluid(fluidInMe or 0)
    drawNumberWithText(143, fl_y1+1, (me_network and (val or 0) or 0), 2, colors.textclr, unit, colors.textclr)
end

local function drawFluxRFinfo()
    initFlux()
    if flux_network == true then
        local energyInfo = component.flux_controller.getEnergyInfo()
        local rf1 = energyInfo.energyInput
        local rf2 = energyInfo.energyOutput
        local fl_y1 = 36

        buffer.drawRectangle(123, fl_y1, 35, 4, colors.bg, 0, " ")
        for i = 0, 35 - 1 do
            buffer.drawText(123 + i, fl_y1-1, colors.bg, brailleChar(brail_console[1]))
        end
        for i = 0, 35 - 1 do
            buffer.drawText(123 + i, fl_y1+1, colors.bg2, brailleChar(brail_console[2]))
        end
        buffer.drawText(124, fl_y1, colors.textclr, "Общий вход/выход в Flux сети:")
        
        buffer.drawText(142, fl_y1+1, colors.bg2, brailleChar(brail_cherta[7]))
        buffer.drawText(142, fl_y1+2, colors.bg2, brailleChar(brail_cherta[1]))
        buffer.drawText(142, fl_y1+3, colors.bg2, brailleChar(brail_cherta[1]))

        drawDigit(125, fl_y1+2, brail_thunderbolt, 0xff2200)

        local valIn, unitIn = formatFluxRF(rf1)
        drawNumberWithText(136, fl_y1+2, (valIn or 0), 2, colors.textclr, unitIn .. "/t", colors.textclr)

        local valOut, unitOut = formatFluxRF(rf2)
        drawNumberWithText(152, fl_y1+2, (valOut or 0), 2, colors.textclr, unitOut .. "/t", colors.textclr)
    end
end

local function drawRFinfo()
    rf = 0
    for i = 1, reactors do
        rf = rf + (reactor_rf[i] or 0)
    end 
    local fl_y1 = 40
    if flux_network == true then fl_y1 = 41 end

    buffer.drawRectangle(123, fl_y1, 35, 4, colors.bg, 0, " ")
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1-1, colors.bg, brailleChar(brail_console[1]))
    end
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1+1, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, fl_y1, colors.textclr, "Генерация всех реакторов:")

    drawDigit(125, fl_y1+2, brail_thunderbolt, 0xffc400)

    local val, unit = formatRF(rf)
    drawNumberWithText(144, fl_y1+2, (any_reactor_on and val or 0), 2, colors.textclr, unit .. "/t", colors.textclr)
end
local function clearRightWidgets()
    color = (theme and 0xffffff or 0x3c3c3c)
    buffer.drawRectangle(123, 3, 35, 47, color, 0, " ")
end

local function drawDynamic()
    buffer.drawRectangle(123, 3, 35, (flux_network and 22 or 24), colors.bg, 0, " ")
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, 2, colors.bg, brailleChar(brail_console[1]))
    end
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, 4, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, 3, colors.textclr, "Информационное окно отладки:")
    drawStatus()

    -- -----------------------------------------------------------
    drawFluxRFinfo()

    -- -----------------------------------------------------------
    drawRFinfo()
    
    -- -----------------------------------------------------------
    drawTimeInfo()

    -- -----------------------------------------------------------

    drawWidgets()
    drawRightMenu()
    buffer.drawChanges()
end

local function updateReactorData(num)
    for i = num or 1, num or reactors do
        local proxy = reactors_proxy[i]
        temperature[i]      = safeCall(proxy, "getTemperature", 0)
        reactor_type[i]     = safeCall(proxy, "isActiveCooling", false) and "Fluid" or "Air"
        reactor_rf[i]       = safeCall(proxy, "getEnergyGeneration", 0)
        reactor_work[i]     = safeCall(proxy, "hasWork", false)

        if reactor_type[i] == "Fluid" then
            reactor_getcoolant[i] = safeCall(proxy, "getFluidCoolant", 0) or 0
            reactor_maxcoolant[i] = safeCall(proxy, "getMaxFluidCoolant", 0) or 1
        end
    end
    drawWidgets()
    drawRFinfo()
end

local function start(num)
    if num then
        message("Запускаю реактор #" .. num .. "...", colors.textclr, 34)
    else
        message("Запуск реакторов...", colors.textclr, 34)
    end
    for i = num or 1, num or reactors do
        local rType = reactor_type[i]
        local proxy = reactors_proxy[i]

        if rType == "Fluid" then
            if offFluid == false then
                safeCall(proxy, "activate")
                reactor_work[i] = true
                if num then
                    message("Реактор #" .. i .. " (жидкостный) запущен!", colors.msginfo, 34)
                end
            else
                if fluidInMe <= porog then
                    if num then
                        message("Ошибка по жидкости! Реактор #" .. i .. " (жидкостный) не был запущен!", colors.msgwarn, 34)
                    end
                    offFluid = true
                    if reason == nil then
                        reason = "Ошибка жидкости!"
                        reactor_aborted[i] = true
                    end
                else
                    offFluid = false
                    safeCall(proxy, "activate")
                    reactor_work[i] = true
                    if num then
                        message("Реактор #" .. i .. " (жидкостный) запущен!", colors.msginfo, 34)
                    end
                end
            end
        else
            safeCall(proxy, "activate")
            reactor_work[i] = true
            if num then
                message("Реактор #" .. i .. " (воздушный) запущен!", colors.msginfo, 34)
            end
        end
    end
    if not num then
        if offFluid == true then
            local isAir = false
            for i = 1, reactors do
                local rType = reactor_type[i]
                if rType == "Air" then
                    isAir = true
                    break
                end
            end
            if isAir == true then
                message("Воздушные реакторы запущены!", colors.msginfo, 34)
            end
            message("Ошибка по жидкости! Жидкостные реакторы не будут запущены!", colors.msgwarn, 34)
        else
            message("Реакторы запущены!", colors.msginfo, 34)
        end
    end
    drawWidgets()
end


local function stop(num)
    if num then
        message("Отключаю реактор #" .. num .. "...", colors.textclr, 34)
    else
        message("Отключение реакторов...", colors.textclr, 34)
    end
    for i = num or 1, num or reactors do
        local proxy = reactors_proxy[i]
        local rType = reactor_type[i]
        safeCall(proxy, "deactivate")
        reactor_work[i] = false
        drawStatus()
        if rType == "Fluid" then
            if num then
                message("Реактор #" .. i .. " (жидкостный) отключен!", colors.msginfo, 34)
            end
        else
            if num then
                message("Реактор #" .. i .. " (воздушный) отключен!", colors.msginfo, 34)
            end
        end

        if any_reactor_on == false then
            work = false
        end
    end
    if not num then
        message("Реакторы отключены!", colors.msginfo, 34)
    end
end

local function silentstop(num)
    for i = num or 1, num or reactors do
        local proxy = reactors_proxy[i]
        local rType = reactor_type[i]
        safeCall(proxy, "deactivate")
        reactor_work[i] = false
        if any_reactor_on == false then
            work = false
        end
    end
end

function onInterrupt()
    message("Обнаружено прерывание!", colors.msgerror)
    os.sleep(0.2)
    if work == true then
        stop()
        updateReactorData()
        os.sleep(0.2)
        drawWidgets()
        drawRFinfo()
        os.sleep(0.3)
    end
    message("Завершаю работу программы...", colors.msgerror, 34)

    if chatThread then
        chatThread:kill()
    end

    buffer.drawChanges()
    os.sleep(0.5)
    buffer.clear(0x000000)
    buffer.drawChanges()
    shell.execute("clear")
    exit = true
    os.exit()
end

_G.__NR_ON_INTERRUPT__ = function()
    onInterrupt()
end

local function reactorsChanged()
    local currentCount = 0
    local current = {}

    for address in component.list("htc_reactors") do
        current[address] = true
        currentCount = currentCount + 1
    end

    if currentCount ~= reactors then
        return true
    end

    for i = 1, #reactor_address do
        local addr = reactor_address[i]
        if addr and not current[addr] then
            return true
        end
    end

    return false
end

-- -------------------------------------------------------------------------------------------------------------------------------------

local function logError(err)
    if debugLog == true then
        local f = io.open("/home/reactor_errors.log", "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(err) .. "\n")
            f:write("starting=" .. tostring(starting) ..
                    ", reactors=" .. tostring(reactors) ..
                    ", me_network=" .. tostring(me_network) ..
                    ", fluidInMe=" .. tostring(fluidInMe) ..
                    ", work=" .. tostring(work) ..
                    ", any_reactor_on=" .. tostring(any_reactor_on) .. "\n")

            if reactors > 0 then
                local coolant_line = "coolant_levels="
                for i = 1, reactors do
                    coolant_line = coolant_line .. tostring(reactor_getcoolant[i] or "nil")
                    if i < reactors then
                        coolant_line = coolant_line .. ", "
                    end
                end
                f:write(coolant_line .. "\n")
            end

            f:write("\n")
            f:close()
        end
    end
end

-- -----------------------------------------------------[MD.GUI Functions]--------------------------------------------------------------

-- --------------------------------[SWITCH]----------------------------------------
local function drawSwitch(x, y, w, pipePos, state, activeClr, passiveClr, pipeClr, bgClr)
    local activeCol = activeClr or 0x0088ff
    local passiveCol = passiveClr or 0x444444
    local pipeCol = pipeClr or 0xFFFFFF
    local bgCol = bgClr or 0xcccccc

    -- Очищаем область под ним (опционально, если фон однотонный)
    buffer.drawRectangle(x, y, w, 1, bgCol, 0, " ") 

    -- Левый край
    if pipePos > 1 then
        buffer.drawText(x, y, activeCol, "◖")
    end
    -- Правый край
    if pipePos < w - 1 then
        buffer.drawText(x + w - 1, y, passiveCol, "◗")
    end
    -- Фон
    if pipePos - 1 > 0 then
        buffer.drawRectangle(x + 1, y, pipePos - 1, 1, activeCol, 0, " ")
    end
    if w - pipePos - 1 > 0 then
        buffer.drawRectangle(x + pipePos, y, w - pipePos - 1, 1, passiveCol, 0, " ")
    end
    -- Ползунок
    buffer.drawText(x + pipePos - 1, y, pipeCol, "◖")
    buffer.set(x + pipePos, y, pipeCol, pipeCol, " ")
    buffer.drawText(x + pipePos + 1, y, pipeCol, "◗")
end

-- ------------------------------[SEARCH FIELD]------------------------------------
local searchFields = {}
local function createSearchField(x, y, width, placeholder, hidden, clr, bgclr, placeholderClr)
    table.insert(searchFields, {
        x = x,
        y = y,
        width = width,
        placeholder = placeholder or "Введите текст...",
        text = "",
        cursorPos = 1,
        scrollOffset = 0,
        cursorVisible = false,
        lastBlink = computer.uptime(),
        active = false,
        hidden = (hidden and true or false),
        clr = clr or 0x444444,
        bgclr = bgclr or 0xcccccc,
        placeholderClr = placeholderClr or 0xececec,
    })
end

local function removeSearchField(index)
    if searchFields[index] then
        table.remove(searchFields, index)
    end
end


-- функция отрисовки одного поля
local function drawSearchField(field)
    local fieldColor = field.clr
    local fieldBgColor = field.bgclr
    local placeholderColor = field.placeholderClr
    local fieldTextColor = 0xffffff

    buffer.drawRectangle(field.x, field.y, field.width, 1, fieldColor, fieldBgColor, " ")
    buffer.drawRectangle(field.x+1, field.y-1, field.width-2, 1, fieldColor, fieldBgColor, brailleChar(brail_fields[6]))
    buffer.drawRectangle(field.x+1, field.y+1, field.width-2, 1, fieldColor, fieldBgColor, brailleChar(brail_fields[5]))
    buffer.drawText(field.x, field.y-1, fieldColor, brailleChar(brail_fields[1]))
    buffer.drawText(field.x, field.y+1, fieldColor, brailleChar(brail_fields[4]))
    buffer.drawText(field.x + field.width-1, field.y-1, fieldColor, brailleChar(brail_fields[2]))
    buffer.drawText(field.x + field.width-1, field.y+1, fieldColor, brailleChar(brail_fields[3]))

    local visibleText
    local maxVisible = field.width - 2
    local startX, startY = field.x + 1, field.y

    if not field.active then
        if field.text == "" then
            -- плейсхолдер
            buffer.drawText(startX, startY, placeholderColor, centerText(field.placeholder, field.width))
        else
            buffer.drawText(startX, startY, placeholderColor, shortenNameCentered((field.hidden and string.rep("*", unicode.len(field.text:sub(field.scrollOffset + 1, field.scrollOffset + maxVisible))) or field.text), maxVisible))
        end
    else
        -- скролл текста
        if field.cursorPos - field.scrollOffset > maxVisible then
            field.scrollOffset = field.cursorPos - maxVisible
        elseif field.cursorPos <= field.scrollOffset then
            field.scrollOffset = math.max(0, field.cursorPos - 1)
        end
        if field.hidden == true then
            visibleText = string.rep("*", unicode.len(field.text:sub(field.scrollOffset + 1, field.scrollOffset + maxVisible)))
        else
            visibleText = field.text:sub(field.scrollOffset + 1, field.scrollOffset + maxVisible)
        end

        -- вывод текста
        buffer.drawText(startX, startY, fieldTextColor, visibleText)

        if field.cursorVisible then
            local cursorX = startX + (field.cursorPos - 1 - field.scrollOffset)
            buffer.drawText(cursorX, startY, fieldTextColor, "|")
        end
    end
end

-- функция отрисовки всех полей
local function drawAllFields()
    for _, f in ipairs(searchFields) do
        drawSearchField(f)
    end
    buffer.drawChanges()
end

local function removeAllFields()
    for i = #searchFields, 1, -1 do
        removeSearchField(i)
    end
    buffer.drawChanges()
end
-- --------------------------------------------------------------------------------

-- -----------------------------------------------------[MODAL WINDOWS]-----------------------------------------------------------------
-- -----------------------------{SETTINGS MENU}------------------------------------
local function drawSettingsMenu()
    local isSaved = false
    local isStart = false
    if work == true and any_reactor_on == true then
        isStart = true
        stop()
    end

    local modalX, modalY, modalW, modalH = 35, 10, 65, 23 -- Размеры модального окна, w - ширина, h - высота
    local old = buffer.copy(1, 1, 160, 50)
    buffer.drawRectangle(1, 1, 160, 50, 0x000000, 0, " ", 0.4)
    buffer.drawRectangle(modalX, modalY, modalW, modalH, 0xcccccc, 0, " ")
    buffer.drawRectangle(modalX-1, modalY+1, modalW+2, modalH-2, 0xcccccc, 0, " ")
    local cornerPos = {
        {modalX-1, modalY, 1}, {modalX+modalW, modalY, 2},
        {modalX+modalW, modalY+modalH-1, 3}, {modalX-1, modalY+modalH-1, 4}
    }
    for _, c in ipairs(cornerPos) do
        buffer.drawText(c[1], c[2], 0xcccccc, brailleChar(brail_status[c[3]]))
    end
    removeAllFields()
    -- Заголовки
    buffer.drawText(modalX + 11, modalY + 1, 0x000000, "Меню настроек приложения ReactorControl v" .. version .. "." .. build)

    buffer.drawText(modalX + 5, modalY + 7, 0x000000, "Тема по умолчанию")
    animatedButton(1, modalX + 4, modalY + 8, "Светлая      ", nil, nil, 20, nil, nil, 0x444444, 0xffffff)
    local sw1_x, sw1_y, sw1_w = modalX+16, modalY+9, 7
    local sw1_state = theme -- текущее состояние
    local sw1_pipePos = (sw1_state and (sw1_w - 2) or 1)   -- позиция (1 - лево, sw1_w-2 - право)
    drawSwitch(sw1_x, sw1_y, sw1_w, sw1_pipePos, sw1_state, nil, 0x777777, nil, 0x444444)

    buffer.drawText(modalX + 3, modalY + 11, 0x000000, "Новые версии приложения")
    animatedButton(1, modalX + 4, modalY + 12, "Проверять        ", nil, nil, 20, nil, nil, 0x444444, 0xffffff)
    local sw2_x, sw2_y, sw2_w = modalX+16, modalY+13, 7
    local sw2_state = updateCheck -- текущее состояние
    local sw2_pipePos = (sw2_state and (sw2_w - 2) or 1)   -- позиция (1 - лево, sw2_w-2 - право)
    drawSwitch(sw2_x, sw2_y, sw2_w, sw2_pipePos, sw2_state, nil, 0x777777, nil, 0x444444)

    buffer.drawText(modalX + 3, modalY + 15, 0x000000, "Расширенное логирование")
    animatedButton(1, modalX + 4, modalY + 16, "Включенно         ", nil, nil, 20, nil, nil, 0x444444, 0xffffff)
    local sw3_x, sw3_y, sw3_w = modalX+16, modalY+17, 7
    local sw3_state = debugLog -- текущее состояние
    local sw3_pipePos = (sw3_state and (sw3_w - 2) or 1)   -- позиция (1 - лево, sw3_w-2 - право)
    drawSwitch(sw3_x, sw3_y, sw3_w, sw3_pipePos, sw3_state, nil, 0x777777, nil, 0x444444)

    -- nickname widget
    local function drawNicknameWidget(placeholder, clr)
        if placeholder == nil then
            placeholder = "Введите никнейм"
        end
        buffer.drawText(modalX + 29, modalY + 3, 0x000000, "Игроки добавленные в белый список:")
        local winX, winY, winW, winH = modalX+30, modalY+4, 32, 18
        buffer.drawRectangle(winX, winY, winW, 1, 0x333333, 0, " ")
        buffer.drawRectangle(winX-1, winY+1, winW+2, winH-2, 0x333333, 0, " ")

        buffer.drawRectangle(winX, winY, winW, 1, 0x333333, 0xcccccc, brailleChar(button1[7]))
        buffer.drawRectangle(winX, winY+(winH-1), winW, 1, 0x333333, 0xcccccc, " ")

        local winCornerPos = {
            {winX-1, winY, 4}, {winX+winW, winY, 2},
            {winX+winW, winY+winH-1, 8}, {winX-1, winY+winH-1, 9}
        }
        for _, c in ipairs(winCornerPos) do
            buffer.drawText(c[1], c[2], 0x333333, brailleChar(button1[c[3]]))
        end

        local maxRows = 14
        local startY = modalY + 4
        for i = 1, maxRows do
            local y = startY + i
            local bg = (i % 2 == 0) and 0x444444 or 0x555555

            buffer.drawRectangle(winX, y, winW, 1, bg, 0, " ")

            local name = users[i]
            if name then
                buffer.drawText(modalX + 33, y, 0xffffff, shortenNameCentered(name, winW - 7))
                buffer.drawText(modalX + 58, y, 0xff2121, "Del")
            else
                buffer.drawText(modalX + 31, y, 0xcbcbcb, shortenNameCentered("* Пусто *", winW - 2))
            end
        end
        removeSearchField(1)
        createSearchField(modalX + 30, modalY + 20, 24, placeholder, false, 0x353535, 0x333333, clr)
        animatedButton(1, modalX + 56, modalY + 19, "ADD", nil, nil, 5, nil, nil, 0x37c72a, 0xffffff) -- 0x21ff21
        drawAllFields()
    end

    local function nicknameExists(nick)
        for _, user in ipairs(users) do
            if user == nick then
                return true
            end
        end
        return false
    end

    -- function msgModal(x, y, w, h, color, text, textclr)
    --     local winX, winY, winW, winH = x, y, w, h
    --     buffer.drawRectangle(winX, winY, winW, winH-2, color, 0x3a3a3a, brailleChar(button1[7]))

    --     buffer.drawRectangle(winX-1, winY+1, winW+2, winH-2, color, 0, " ")

    --     buffer.drawRectangle(winX, winY+(winH-1), winW, 1, color, 0x3a3a3a, brailleChar(button1[1]))

    --     local winCornerPos = {
    --         {winX-1, winY, 4}, {winX+winW, winY, 2},
    --         {winX+winW, winY+winH-1, 6}, {winX-1, winY+winH-1, 5}
    --     }
    --     for _, c in ipairs(winCornerPos) do
    --         buffer.drawText(c[1], c[2], color, brailleChar(button1[c[3]]))
    --     end
    --     buffer.drawText(winX, winY+1, textclr or 0x000000, text)
    -- end
    -- ---------

    buffer.drawText(modalX + 1, modalY + modalH - 1, 0x999999, "P.S. Нажмите в любом месте вне окна, чтобы выйти без сохранения")
    animatedButton(1, modalX + 5, modalY + modalH - 4, "Сохранить и выйти", nil, nil, 18, nil, nil, 0x8100cc, 0xffffff)
    -- buffer.drawText(modalX + 64, modalY, 0xff0000, "✕")
    drawNicknameWidget()

    local themetoggle = theme

    local NSTheme = theme
    local NSUpdateCheck = updateCheck
    local NSDebugLog = debugLog
    local NSusers = {}
    for _, u in ipairs(users) do
        table.insert(NSusers, u)
    end

    while true do
        local eventData = {event.pull(0.05)}
        local eventType = eventData[1]

        -- Блинкер
        for _, f in ipairs(searchFields) do
            if f.active and computer.uptime() - f.lastBlink >= 0.5 then
                f.cursorVisible = not f.cursorVisible
                f.lastBlink = computer.uptime()
                drawAllFields()
            end
        end

        if eventType == "touch" then
            local _, _, x, y, button, uuid = table.unpack(eventData)

            for i, f in ipairs(searchFields) do
                if y == f.y and x >= f.x and x <= f.x + f.width - 1 then
                    -- активация полей
                    for _, f2 in ipairs(searchFields) do
                        f2.active, f2.cursorVisible = false, false
                    end
                    f.active = true
                    f.cursorVisible = true
                    f.lastBlink = computer.uptime()
                else
                    -- снимаем активность если клик не по полю
                    if f.active then
                        f.active = false
                        f.cursorVisible = false
                    end
                end
            end
            drawAllFields()

            for i, user in ipairs(users) do
                local rowY = modalY + 4 + i
                if y == rowY and x >= modalX + 58 and x <= modalX + 61 then
                    -- Удаляем никнейм из белого списка
                    buffer.drawText(modalX + 58, y, 0xff2121, "Del")
                    buffer.drawChanges()
                    os.sleep(0.2)
                    buffer.drawText(modalX + 58, y, 0xcc0000, "Del")
                    local delNick = users[i]
                    table.remove(users, i)
                    drawNicknameWidget()
                    buffer.drawChanges()
                    break
                end
            end
            -- ----------------------------------------------------------

            if x < modalX-1 or x > modalX + modalW or y < modalY or y > (modalY-1) + modalH then    
                buffer.paste(1, 1, old)
                buffer.drawChanges()
                if isStart == true then
                    start()
                end
                theme = NSTheme
                updateCheck = NSUpdateCheck
                debugLog = NSDebugLog
                users = NSusers
                saveCfg()
                break
            end

            if x >= sw1_x and x <= sw1_x + sw1_w - 1 and y == sw1_y then
                sw1_state = not sw1_state
                
                -- Анимация (простая)
                local targetPos = sw1_state and (sw1_w - 2) or 1
                local step = (targetPos > sw1_pipePos) and 1 or -1
                
                repeat
                    sw1_pipePos = sw1_pipePos + step
                    drawSwitch(sw1_x, sw1_y, sw1_w, sw1_pipePos, sw1_state, nil, 0x777777, nil, 0x444444)
                    buffer.drawChanges()
                    os.sleep(0.02)
                until sw1_pipePos == targetPos
                
            elseif x >= sw2_x and x <= sw2_x + sw2_w - 1 and y == sw2_y then
                sw2_state = not sw2_state
                
                -- Анимация (простая)
                local targetPos = sw2_state and (sw2_w - 2) or 1
                local step = (targetPos > sw2_pipePos) and 1 or -1
                
                repeat
                    sw2_pipePos = sw2_pipePos + step
                    drawSwitch(sw2_x, sw2_y, sw2_w, sw2_pipePos, sw2_state, nil, 0x777777, nil, 0x444444)
                    buffer.drawChanges()
                    os.sleep(0.02)
                until sw2_pipePos == targetPos
                
                -- Тут можно добавить действие при переключении
                -- example: check_updates = sw_state
            elseif x >= sw3_x and x <= sw3_x + sw3_w - 1 and y == sw3_y then
                sw3_state = not sw3_state
                -- Анимация (простая)
                local targetPos = sw3_state and (sw3_w - 2) or 1
                local step = (targetPos > sw3_pipePos) and 1 or -1
                
                repeat
                    sw3_pipePos = sw3_pipePos + step
                    drawSwitch(sw3_x, sw3_y, sw3_w, sw3_pipePos, sw3_state, nil, 0x777777, nil, 0x444444)
                    buffer.drawChanges()
                    os.sleep(0.02)
                until sw3_pipePos == targetPos
                
                -- Тут можно добавить действие при переключении
                -- example: debug_log = sw_state
            elseif y >= modalY + 19 and y <= modalY + 21 and x >= modalX + 55 and x <= modalX + 56+5 then
                -- Добавляем никнейм в белый список
                animatedButton(1, modalX + 56, modalY + 19, "ADD", nil, nil, 5, nil, nil, 0x21ff21, 0xffffff) -- 0x21ff21
                animatedButton(2, modalX + 56, modalY + 19, "ADD", nil, nil, 5, nil, nil, 0x21ff21, 0xffffff) -- 0x21ff21
                buffer.drawChanges()
                os.sleep(0.2)
                animatedButton(1, modalX + 56, modalY + 19, "ADD", nil, nil, 5, nil, nil, 0x37c72a, 0xffffff) -- 0x21ff21
                local placehold
                local placeclr
                local newNick = searchFields[1].text:match("^%s*(.-)%s*$") -- trim
                if newNick == "" then
                    -- buffer.drawText(modalX + 30, modalY + 20, 0xff0000, "Никнейм не может быть пустым!")
                    -- msgModal(modalX + 18, modalY + 24, 29, 3, 0xcccccc, "Никнейм не может быть пустым!", 0xff0000)
                    placehold = "Не может быть пустым!"
                    placeclr = 0xff0000
                elseif #newNick > 16 then
                    -- message("Никнейм не может быть длиннее 16 символов!", colors.msgwarn, 34)
                    placehold = "Нельзя > 16 символов!"
                    placeclr = 0xff0000
                elseif nicknameExists(newNick) then
                    -- buffer.drawText(modalX + 3, modalY + 22, 0xff0000, "Никнейм уже в белом списке!")
                    placehold = "Уже в белом списке!"
                    placeclr = 0xff0000
                elseif #newNick < 3 then
                    -- message("Никнейм не может быть короче 2 символов!", colors.msgwarn, 34)
                    placehold = "Не меньше 3 символов!"
                    placeclr = 0xff0000
                else
                    table.insert(users, newNick)
                end
                drawNicknameWidget(placehold, placeclr)
                
            elseif y >= modalY + modalH - 4 and y <= modalY + modalH - 2 and x >= modalX + 4 and x <= modalX + (5+18) then
                buffer.drawRectangle(modalX + 4, modalY + modalH - 4, 19, 3, 0xcccccc, 0, " ")
                animatedButton(1, modalX + 5, modalY + modalH - 4, "Сохранить и выйти", nil, nil, 18, nil, nil, 0xa91df9, 0xffffff)
                animatedButton(2, modalX + 5, modalY + modalH - 4, "Сохранить и выйти", nil, nil, 18, nil, nil, 0xa91df9, 0xffffff)
                buffer.drawChanges()
                os.sleep(0.2)
                animatedButton(1, modalX + 5, modalY + modalH - 4, "Сохранить и выйти", nil, nil, 18, nil, nil, 0x8100cc, 0xffffff)
                buffer.drawChanges()
                -- Сохраняем настройки
                theme = sw1_state
                updateCheck = sw2_state
                debugLog = sw3_state
                saveCfg()
                
                switchTheme()
                drawStatic()
                drawDynamic()
                userUpdate()
                message("Настройки сохранены!", nil, 34)
                if isStart == true then
                    start()
                end
                break
            end

            -- ----------------------------------------------------------

        elseif eventType == "key_down" then
            local _, _, char, code = table.unpack(eventData)
            for i, f in ipairs(searchFields) do
                if f.active then
                    if code == 14 then -- Backspace
                        if f.cursorPos > 1 then
                            f.text = f.text:sub(1, f.cursorPos - 2) .. f.text:sub(f.cursorPos)
                            f.cursorPos = f.cursorPos - 1
                        end
                    elseif code == 203 then -- стрелка влево
                        if f.cursorPos > 1 then
                            f.cursorPos = f.cursorPos - 1
                        end
                    elseif code == 205 then -- стрелка вправо
                        if f.cursorPos <= #f.text then
                            f.cursorPos = f.cursorPos + 1
                        end
                    elseif char >= 32 and char <= 126 then -- Печатаемые символы
                        local c = string.char(char) 
                        f.text = f.text:sub(1, f.cursorPos - 1) .. c .. f.text:sub(f.cursorPos) 
                        f.cursorPos = f.cursorPos + 1 
                    elseif code == 28 then -- Enter
                        f.active = false
                        f.cursorVisible = false
                    end
                end
            end
            drawAllFields()
        end
    end
end
-- -------------------------------{INFO MENU}--------------------------------------
local function drawInfoMenu()
    local isStart = false
    if work == true and any_reactor_on == true then
        isStart = true
        stop()
    end

    local modalX, modalY, modalW, modalH = 20, 5, 83, 36 -- Размеры модального окна, w - ширина, h - высота
    local old = buffer.copy(1, 1, 160, 50)
    buffer.drawRectangle(1, 1, 160, 50, 0x000000, 0, " ", 0.4)
    buffer.drawRectangle(modalX, modalY, modalW, modalH, 0xcccccc, 0, " ")
    buffer.drawRectangle(modalX-1, modalY+1, modalW+2, modalH-2, 0xcccccc, 0, " ")
    local cornerPos = {
        {modalX-1, modalY, 1}, {modalX+modalW, modalY, 2},
        {modalX+modalW, modalY+modalH-1, 3}, {modalX-1, modalY+modalH-1, 4}
    }
    for _, c in ipairs(cornerPos) do
        buffer.drawText(c[1], c[2], 0xcccccc, brailleChar(brail_status[c[3]]))
    end

    local infoScrollPos = 0
    local changelogScrollPos = 0
    local licenseScrollPos = 0
    local section = 1 -- 1 - info, 2 - changelog, 3 - license
    local scrollPos = 0
    local maxScroll = 0
    local function drawScrollText(x, y, w, h, text, pos)
        local function wrapLine(line, maxWidth)
            -- пустая строка = перенос
            if line == "" then
                return { "" }
            end

            local lines = {}
            local current = ""

            for word in line:gmatch("%S+") do
                if unicode.len(current) == 0 then
                    current = word
                elseif unicode.len(current) + 1 + unicode.len(word) <= maxWidth then
                    current = current .. " " .. word
                else
                    table.insert(lines, current)
                    current = word
                end
            end

            if unicode.len(current) > 0 then
                table.insert(lines, current)
            end

            return lines
        end

        -- разворачиваем весь текст
        local wrapped = {}
        for _, line in ipairs(text) do
            local lines = wrapLine(line, w)
            for _, l in ipairs(lines) do
                table.insert(wrapped, l)
            end
        end

        -- считаем предел скролла ЗДЕСЬ
        local totalLines = #wrapped
        local maxScroll = math.max(0, totalLines - h)

        -- защита от выхода за пределы
        pos = math.max(0, math.min(pos, maxScroll))

        -- отрисовка
        for i = 1, h do
            local idx = i + pos
            if wrapped[idx] ~= nil then
                buffer.drawText(x, y + i - 1, 0x000000, wrapped[idx])
            end
        end

        return maxScroll
    end

    local     infotext = {
        "Автор программы: Flixmo",
        "",
        "Лицензия: MIT License",
        "",
        "Описание программы:",
        "Reactor Control — программа мониторинга, контроля и управления критически важными системами реакторного комплекса для игроков сервера McSkill HiTech 1.12.2, разработанная на базе мода OpenComputers. Программа предназначена для централизованного управления реакторами и связанными с ними инфраструктурными системами, а также для автоматического предотвращения аварийных ситуаций без необходимости постоянного ручного контроля.",
        "",
        "Программа поддерживает работу с жидкостными и воздушными HT-реакторами, интеграцию с Applied Energistics 2 для мониторинга и анализа жидкостей, а также интеграцию с Flux Networks для контроля энергетической сети. Подключение осуществляется через адаптеры OpenComputers к соответствующим контроллерам. Основной упор сделан на стабильность, безопасность и корректную работу реакторных комплексов любого масштаба.",
        "",
        "Реализована автоматическая система безопасности для жидкостных реакторов. При снижении уровня хладагента в МЭ-сети ниже заданного порога либо при полной недоступности МЭ-сети реакторы автоматически отключаются и переводятся в аварийный режим, в котором ручной запуск блокируется. После восстановления нормальных условий реакторы автоматически возвращаются в штатный режим и запускаются. Воздушные реакторы при проблемах с жидкостью не затрагиваются. Контроль состояния сетей и жидкостей выполняется на постоянной основе.",
        "",
        "Графический интерфейс программы отображает детальную информацию по каждому реактору, включая температуру, текущую генерацию энергии, тип реактора, статус включения, уровень хладагента в буфере, индивидуальный отсчёт времени до распада топливных стержней и данные о потреблении жидкости. В общем статусе комплекса выводится количество установленных реакторов и текущее состояние системы.",
        "",
        "Программа поддерживает управление и получение информации через игровой чат с использованием Chat Box. Это позволяет запускать и останавливать реакторы, получать статус комплекса, изменять параметры безопасности и управлять списком пользователей без прямого взаимодействия с интерфейсом компьютера. Реализована система пользователей и прав доступа, а также гибкая конфигурация с пользовательскими настройками.",
        "",
        "Особое внимание уделено надёжности и стабильности работы. Программа устойчиво обрабатывает ошибки, корректно работает при потере связи с МЭ- и Flux-сетями, использует безопасные вызовы компонентов и оптимизированную отрисовку интерфейса. Архитектура кода переработана с упором на предотвращение зависаний и циклических перезагрузок, что делает программу пригодной для длительной непрерывной работы.",
        "",
        "Программа не проверяет корректность сборки самих реакторов. В случае неверной схемы реактора вся ответственность за возможные последствия полностью лежит на пользователе.",
        "",
        "Программа распространяется бесплатно и предоставляется «как есть». Возможны ошибки и баги, но они оперативно исправляются, в случае если вы нашли баг настоятельная просьба сообщить об этом автору.", 
        "Так-же автор не несёт ответственности за взрывы реакторов или иной ущерб, возникший в результате использования программы."
    }

    local changelogText = {}
    if changelog then
        for _, entry in ipairs(changelog) do
            -- Заголовок версии
            table.insert(changelogText, "Версия " .. entry.version .. ":")
            -- Добавляем все изменения этой версии
            for _, line in ipairs(entry.changes) do
                table.insert(changelogText, "- " .. line)
            end
            -- Пустая строка между версиями для читаемости
            table.insert(changelogText, "")
        end
    else
        changelogText = { "Ошибка загрузки changelog.lua!" }
    end

    local licenseText = {
        "MIT License", 
        "",
        "Copyright (c) 2025 Flixmo",
        "",
        "English Version",
        "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.",
        "",
        "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.",
        "",
        "Русская версия",
        "Настоящим предоставляется разрешение любому лицу, получающему копию данного программного обеспечения и связанных с ним файлов документации («Программное обеспечение»), безвозмездно использовать Программное обеспечение без ограничений, включая, помимо прочего, права использовать, копировать, изменять, объединять, публиковать, распространять, сублицензировать и/или продавать копии Программного обеспечения, а также разрешать лицам, которым предоставляется Программное обеспечение, делать это при соблюдении следующих условий: Вышеуказанное уведомление об авторских правах и настоящее уведомление о разрешении должны быть включены во все копии или существенные части Программного обеспечения.",
        "",
        "ПРОГРАММНОЕ ОБЕСПЕЧЕНИЕ ПРЕДОСТАВЛЯЕТСЯ «КАК ЕСТЬ», БЕЗ КАКИХ-ЛИБО ГАРАНТИЙ, ЯВНЫХ ИЛИ ПОДРАЗУМЕВАЕМЫХ, ВКЛЮЧАЯ, НО НЕ ОГРАНИЧИВАЯСЬ, ГАРАНТИЯМИ ТОВАРНОЙ ПРИГОДНОСТИ,  ПРИГОДНОСТИ ДЛЯ КОНКРЕТНОЙ ЦЕЛИ И ОТСУТСТВИЯ НАРУШЕНИЯ ПРАВ. НИ ПРИ КАКИХ ОБСТОЯТЕЛЬСТВАХ  АВТОРЫ ИЛИ ПРАВООБЛАДАТЕЛИ НЕ НЕСУТ ОТВЕТСТВЕННОСТИ ЗА ЛЮБЫЕ ПРЕТЕНЗИИ, УБЫТКИ ИЛИ  ИНЫЕ ОБЯЗАТЕЛЬСТВА, БУДЬ ТО ПО ДОГОВОРНЫМ, ДЕЛИКТНЫМ ИЛИ ИНЫМ ПРИЧИНАМ,  ВОЗНИКАЮЩИЕ ИЗ ПРОГРАММНОГО ОБЕСПЕЧЕНИЯ ИЛИ В СВЯЗИ С НИМИ, НИ С ИСПОЛЬЗОВАНИЕМ  ПРОГРАММНОГО ОБЕСПЕЧЕНИЯ ИЛИ ИНЫМИ ОПЕРАЦИЯМИ С ПРОГРАММНЫМ ОБЕСПЕЧЕНИЕМ."
    }

    buffer.drawText(modalX + 19, modalY + 1, 0x000000, "Меню информации приложения ReactorControl v" .. version .. "." .. build)
    buffer.drawText(modalX + 5, modalY + 3, 0x111111, "Общая информация")
    buffer.drawRectangle(modalX + 4, modalY + 4, 18, 1, 0xcccccc, 0x8100cc, "⠉")
    
    buffer.drawText(modalX + 32, modalY + 3, 0x111111, "Изменения в версиях")
    buffer.drawRectangle(modalX + 31, modalY + 4, 21, 1, 0xcccccc, 0x666666, "⠉")
    
    buffer.drawText(modalX + 65, modalY + 3, 0x111111, "MIT License")
    buffer.drawRectangle(modalX + 64, modalY + 4, 13, 1, 0xcccccc, 0x666666, "⠉")

    drawScrollText(modalX + 2, modalY + 5, modalW - 4, 29, infotext, 0)

    buffer.drawText(modalX + 4, modalH+4, 0x999999, "P.S. Нажмите в любом месте вне окна, чтобы выйти из меню, текст скороллится")
    buffer.drawChanges()

    while true do
        local eventData = {event.pull(0.05)}
        local eventType = eventData[1]

        if eventType == "touch" then
            local _, _, x, y, button, uuid = table.unpack(eventData)
            
            if x < modalX-1 or x > modalX + modalW or y < modalY or y > (modalY-1) + modalH then    
                buffer.paste(1, 1, old)
                buffer.drawChanges()
                if isStart == true then
                    start()
                end
                break
            end
            if x >= modalX + 5 and x <= modalX + 22 and y >= modalY + 3 and y <= modalY + 4 then
                -- Общая информация
                section = 1
                scrollPos = 0
                buffer.drawRectangle(modalX + 2, modalY + 5, modalW - 4, 29, 0xcccccc, 0, " ")
                buffer.drawRectangle(modalX + 4, modalY + 4, 18, 1, 0xcccccc, 0x8100cc, "⠉")
                buffer.drawRectangle(modalX + 31, modalY + 4, 21, 1, 0xcccccc, 0x666666, "⠉")
                buffer.drawRectangle(modalX + 64, modalY + 4, 13, 1, 0xcccccc, 0x666666, "⠉")
                drawScrollText(modalX + 2, modalY + 5, modalW - 4, 29, infotext, 0)
                buffer.drawChanges()
            elseif x >= modalX + 32 and x <= modalX + 52 and y >= modalY + 3 and y <= modalY + 4 then
                -- Изменения в версиях
                section = 2
                scrollPos = 0
                buffer.drawRectangle(modalX + 2, modalY + 5, modalW - 4, 29, 0xcccccc, 0, " ")
                buffer.drawRectangle(modalX + 4, modalY + 4, 18, 1, 0xcccccc, 0x666666, "⠉")
                buffer.drawRectangle(modalX + 31, modalY + 4, 21, 1, 0xcccccc, 0x8100cc, "⠉")
                buffer.drawRectangle(modalX + 64, modalY + 4, 13, 1, 0xcccccc, 0x666666, "⠉")
                drawScrollText(modalX + 2, modalY + 5, modalW - 4, 29, changelogText, 0)
                buffer.drawChanges()
            elseif x >= modalX + 65 and x <= modalX + 77 and y >= modalY + 3 and y <= modalY + 4 then
                -- MIT License
                section = 3
                scrollPos = 0
                buffer.drawRectangle(modalX + 2, modalY + 5, modalW - 4, 29, 0xcccccc, 0, " ")
                buffer.drawRectangle(modalX + 4, modalY + 4, 18, 1, 0xcccccc, 0x666666, "⠉")
                buffer.drawRectangle(modalX + 31, modalY + 4, 21, 1, 0xcccccc, 0x666666, "⠉")
                buffer.drawRectangle(modalX + 64, modalY + 4, 13, 1, 0xcccccc, 0x8100cc, "⠉")
                drawScrollText(modalX + 2, modalY + 5, modalW - 4, 29, licenseText, 0)
                buffer.drawChanges()
            end
        end

        if eventType == "scroll" then
            local _, _, x, y, direction = table.unpack(eventData)
            -- проверка что скролл внутри окна
            if x >= modalX and x <= modalX + modalW - 1 and y >= modalY and y <= modalY + modalH - 1 then
                if direction == -1 then
                    scrollPos = math.min(maxScroll, scrollPos + 1)
                elseif direction == 1 then
                    scrollPos = math.max(0, scrollPos - 1)
                end

                -- перерисовка
                buffer.drawRectangle(
                    modalX + 2,
                    modalY + 5,
                    modalW - 4,
                    29,
                    0xcccccc,
                    0,
                    " "
                )
                if section == 1 then
                    maxScroll = drawScrollText(modalX + 2, modalY + 5, modalW - 4, 29, infotext, scrollPos)
                elseif section == 2 then
                    maxScroll = drawScrollText(modalX + 2, modalY + 5, modalW - 4, 29, changelogText, scrollPos)
                elseif section == 3 then
                    maxScroll = drawScrollText(modalX + 2, modalY + 5, modalW - 4, 29, licenseText, scrollPos)
                end
                buffer.drawChanges()
            end
        end
    end
end

-- -----------------------------------------------------
local function handleChatCommand(nick, msg, args)
    -- Проверяем разрешения пользователя
    local hasPermission = false
    for _, user in ipairs(users) do
        if user == nick then
            hasPermission = true
            break
        end
    end
    
    if not hasPermission then
        if isChatBox then
            chatBox.say("§cУ вас нет прав для управления реакторами!")
        end
        return
    end
    
    -- Обрабатываем команды
    if msg == "@help" then
        if isChatBox then
            chatBox.say("§e=== Команды Reactor Control ===")
            chatBox.say("§a@help - список команд")
            chatBox.say("§a@info - информация о системе")
            chatBox.say("§a@useradd - добавить пользователя (пример: @useradd Ник)") -- Сделай
            chatBox.say("§a@userdel - удалить пользователя (пример: @userdel Ник)")
            chatBox.say("§a@status - статус системы")
            chatBox.say("§a@rods - стержни в реакторе (пример: @rods или @rods 1)")
            chatBox.say("§a@tpscan - проверка транспозеров (где видны инвентари/стержни)")
            chatBox.say("§a@api - показать API реактора/адаптера (пример: @api 1)")
            chatBox.say("§a@setporog - установка порога жидкости (пример: @setporog 500)")
            chatBox.say("§a@start - запуск всех реакторов (или @start 1 для запуска только 1-го)")
            chatBox.say("§a@stop - остановка всех реакторов (или @stop 1 для остановки только 1-го)")
            chatBox.say("§a@exit - выход из программы")
            chatBox.say("§a@restart - перезагрузка компьютера")
        end
        
    elseif msg:match("^@status") then
        if isChatBox then
            chatBox.say("§a=== Статус системы ===")
            chatBox.say("§aРеакторов: " .. reactors)

            local running = {} -- список номеров запущенных реакторов
            for i = 1, reactors do
                if reactor_work[i] == true then
                    table.insert(running, tostring(i))
                end
            end

            if #running == reactors then
                chatBox.say("§aЗапущены: Все")
            elseif #running == 0 then
                chatBox.say("§aЗапущены: Нет активных")
            else
                chatBox.say("§aЗапущены: " .. table.concat(running, ", "))
            end

            chatBox.say("§aПорог: " .. porog .. " Mb")
            chatBox.say("§aГенерация реакторов: " .. rf .. " RF/t")
            chatBox.say("§aОбщее потребление жидкости реакторами: " .. consumeSecond .. " mB/s")
            -- блок "стержни" удалён по запросу пользователя
            -- chatBox.say("§aСостояние реакторов:")
            -- for i = 1, reactors do
            --     if reactor_work[i] == true then
            --         chatBox.say("§aРеактор " .. i .. ": §2Запущен")
            --         chatBox.say("§aТемпература: §e" .. reactor_temp[i] .. " °C")
            --         chatBox.say("§aВыработка: §e" .. reactor_rf[i] .. " RF/t")
            --         chatBox.say("§aРаспад топлива через: §e" .. secondsToHMS(reactor_depletionTime[i] or 0))
            --         chatBox.say("§aТип реактора: §e" .. reactor_type[i])
            --         if reactor_type[i] == "Fluid" then
            --             chatBox.say("§aПотребление жидкости: §e" .. reactor_consume[i] .. " mB/s")
            --         end
            --     else
            --         chatBox.say("§aРеактор " .. i .. ": §cОстановлен")
            --     end
            -- end
        end

    elseif msg:match("^@rods") then
        if not isChatBox then
            return
        end

        local debug = args:find("debug", 1, true) ~= nil
        local num = tonumber(args:match("^(%d+)"))
        if num and (num < 1 or num > reactors) then
            chatBox.say("§cНеверный номер реактора!")
            return
        end

        local first = num or 1
        local last = num or reactors

        for i = first, last do
            local invProxy = nil
            if reactor_adapter_index and adapters_proxy then
                local aIdx = reactor_adapter_index[i]
                if aIdx and adapters_proxy[aIdx] then
                    invProxy = adapters_proxy[aIdx]
                elseif adapters_proxy[i] then
                    invProxy = adapters_proxy[i]
                end
            end

            local agg, sourceInfo = getFuelRodsSummary(invProxy, reactors_proxy[i])
            if not agg or next(agg) == nil then
                chatBox.say("§eРеактор " .. i .. ": §7нет данных о стержнях")
            else
                chatBox.say("§e=== Стержни реактора " .. i .. " ===")
                if sourceInfo then
                    chatBox.say("§7Источник: " .. sourceInfo)
                end
                local keys = {}
                for k in pairs(agg) do
                    table.insert(keys, tostring(k))
                end
                table.sort(keys)

                local shown = 0
                for _, k in ipairs(keys) do
                    local e = agg[k]
                    local c = tonumber(e.count) or 0
                    local s = tonumber(e.slots) or 0
                    local line
                    -- если count совпадает со slots (как в htc_reactors status API) — показываем как "ячеек"
                    if s > 0 and c == s then
                        line = "§a" .. k .. ": §e" .. tostring(s) .. " §7(ячеек)"
                    else
                        line = "§a" .. k .. ": §e" .. tostring(c)
                        if s > 0 then
                            line = line .. " §7(слотов: " .. tostring(s) .. ")"
                        end
                    end
                    if e.pN and e.pN > 0 then
                        local avg = (e.sumP / e.pN) * 100
                        local mn = (e.minP or 0) * 100
                        local mx = (e.maxP or 0) * 100
                        line = line .. string.format(" §7(ресурс %.0f%%, мин %.0f%%, макс %.0f%%)", avg, mn, mx)
                    end
                    chatBox.say(line)
                    shown = shown + 1
                    if shown >= 8 and #keys > 8 then
                        chatBox.say("§7... и ещё " .. tostring(#keys - 8) .. " тип(ов)")
                        break
                    end
                end
            end

            if debug then
                local rods = safeCallwg(reactors_proxy[i], "getAllFuelRodsStatus", nil)
                if type(rods) ~= "table" or #rods == 0 then
                    chatBox.say("§7debug: нет getAllFuelRodsStatus")
                else
                    chatBox.say("§7debug: getAllFuelRodsStatus записей=" .. tostring(#rods))
                    dumpRodRecordToChat(rods[1], "rod[1]")
                    if #rods >= 2 then
                        dumpRodRecordToChat(rods[2], "rod[2]")
                    end
                end

                -- debug для поиндексного API
                if reactors_proxy[i] and reactors_proxy[i].getSelectStatusRod then
                    chatBox.say("§7debug: getSelectStatusRod(1..3)")
                    for idx = 1, 3 do
                        local _, r = callMethodFlexible(reactors_proxy[i], "getSelectStatusRod", idx)
                        dumpRodRecordToChat(r, "sel[" .. tostring(idx) .. "]")
                    end

                    -- краткая сводка: сколько индексов вообще дают item
                    local filled = 0
                    local total = 0
                    for idx = 0, 64 do
                        local ok, r = callMethodFlexible(reactors_proxy[i], "getSelectStatusRod", idx)
                        if ok and type(r) == "table" then
                            total = total + 1
                            local kv = decodeKvArray(r) or {}
                            local itemId = tostring(kv.item or "")
                            if itemId ~= "" and itemId ~= "nil" then
                                filled = filled + 1
                            end
                        end
                    end
                    chatBox.say("§7debug: getSelectStatusRod tables=" .. tostring(total) .. ", filled(item)=" .. tostring(filled))
                else
                    chatBox.say("§7debug: нет метода getSelectStatusRod")
                end
            end
        end

    elseif msg:match("^@tpscan") then
        if isChatBox then
            chatBox.say("§7Сканирую транспозеры...")
        end
        local ok, err = pcall(scanTransposersToChat)
        if not ok and isChatBox then
            chatBox.say("§cОшибка tpscan: " .. tostring(err))
        end

    elseif msg:match("^@api") then
        if not isChatBox then
            return
        end
        local num = tonumber(args:match("^(%d+)")) or 1
        if num < 1 or num > reactors then
            chatBox.say("§cНеверный номер реактора!")
            return
        end

        local invProxy = nil
        if reactor_adapter_index and adapters_proxy then
            local aIdx = reactor_adapter_index[num]
            if aIdx and adapters_proxy[aIdx] then
                invProxy = adapters_proxy[aIdx]
            elseif adapters_proxy[num] then
                invProxy = adapters_proxy[num]
            end
        end

        chatBox.say("§e=== API reactor " .. tostring(num) .. " ===")
        local reactorProxy = reactors_proxy[num]
        local patterns = {"rod", "fuel", "slot", "stack", "invent", "getall", "size"}

        listFilteredMethodsToChat("htc_reactors", reactorProxy, patterns, 18)
        if invProxy then
            listFilteredMethodsToChat("adapter", invProxy, patterns, 18)
        else
            chatBox.say("§7adapter: §8не найден/не привязан")
        end

        -- Попробуем вызвать самые вероятные методы без аргументов
        tryCallInterestingMethodsToChat("htc_reactors", reactorProxy, {"rod", "fuel", "slot"}, 6)
        chatBox.say("§7Подсказка: метод §egetSelectStatusRod(index)§7 требует число. Пример индексов: 1..64.")

    elseif msg:match("^@start") then
        local num = tonumber(args:match("^(%d+)"))
        if isChatBox then
            if num then
                if num > 0 and num <= reactors then
                    chatBox.say("§2Запускаю реактор " .. num .. "...")
                    start(num)
                else
                    chatBox.say("§cНеверный номер реактора!")
                end
            else
                chatBox.say("§2Запускаю все реакторы...")
                starting = true
                start()
            end
        end

    elseif msg:match("^@stop") then
        local num = tonumber(args:match("^(%d+)"))
        if isChatBox then
            if num then
                if num > 0 and num <= reactors then
                    chatBox.say("§cОстанавливаю реактор " .. num .. "...")
                    stop(num)
                else
                    chatBox.say("§cНеверный номер реактора!")
                end
            else
                chatBox.say("§cОстанавливаю все реакторы...")
                starting = false
                stop()
            end
        end

    elseif msg:match("^@setporog") then
        local newPorog = tonumber(args:match("^(%d+)"))
        if newPorog then
            if newPorog <= 0 then
                chatBox.say("§cПорог жидкости не может быть отрицательным или нулевым!")
            else
                porog = newPorog
                if isChatBox then
                    chatBox.say("§2Порог жидкости установлен на " .. porog .. " Mb")
                end
            end
        else
            if isChatBox then
                chatBox.say("§aЧтобы изменить порог жидкости, используйте: @setporog <значение>")
                chatBox.say("§aПример: @setporog 500")
            end
        end
        
    elseif msg == "@info" then
        if isChatBox then
            chatBox.say("§bReactor Control v" .. version .. " Build " .. build)
            chatBox.say("§aАвтор: §eFlixmo")
            chatBox.say("§aИгроки с доступом: §5" .. table.concat(users, ", "))
            chatBox.say("§aСпасибо за использование программы!")
        end
    elseif msg == "@exit" then
        if isChatBox then
            chatBox.say("§cЗавершаю работу программы...")
            if work == true then
                work = false
                message("Отключаю реакторы!", colors.msginfo)
                stop()
                drawWidgets()
                drawRFinfo()
                os.sleep(0.3)
            end
            message("Завершаю работу программы...", colors.msgerror)
            buffer.drawChanges()
            os.sleep(0.2)
            buffer.drawChanges()
            os.sleep(0.5)
            buffer.clear(0x000000)
            buffer.drawChanges()
            shell.execute("clear")
            rawset(_G, "__NR_ON_INTERRUPT__", nil)
            exit = true
            os.exit()
        end
    elseif msg:match("^@useradd") then
        local newUser = args:match("^(%S+)")
        if newUser then
            -- Проверка, нет ли уже такого пользователя
            for _, u in ipairs(users) do
                if u == newUser then
                    chatBox.say("§cПользователь §5" .. newUser .. " §cуже есть в списке!")
                    return
                end
            end

            table.insert(users, newUser)
            chatBox.say("§2Пользователь §5" .. newUser .. " §2добавлен!")
            userUpdate()
        else
            chatBox.say("§aИспользование: @useradd <ник>")
        end
    elseif msg:match("^@userdel") then
        local delUser = args:match("^(%S+)")
        if delUser then
            local found = false
            for i, u in ipairs(users) do
                if u == delUser then
                    table.remove(users, i)
                    chatBox.say("§2Пользователь §5" .. delUser .. " §2удалён!")
                    found = true
                    userUpdate()
                    break
                end
            end
            if not found then
                chatBox.say("§cПользователь §5" .. delUser .. " §cне найден!")
            end
        else
            chatBox.say("§aИспользование: @userdel <ник>")
        end

    -- elseif msg:match("^@changelog") then
    --     local versionReq = args:match("^(%S+)")
    --     if not changelog then
    --         chatBox.say("§cОшибка загрузки changelog.lua!")
    --         return
    --     end

    --     if versionReq then
    --         local found = false
    --         for _, entry in ipairs(changelog) do
    --             if entry.version == versionReq then
    --                 chatBox.say("§eИзменения в версии " .. entry.version .. ":")
    --                 for _, line in ipairs(entry.changes) do
    --                     chatBox.say("§a- " .. line)
    --                 end
    --                 found = true
    --                 break
    --             end
    --         end
    --         if not found then
    --             chatBox.say("§cВерсия " .. versionReq .. " не найдена в ченджлоге!")
    --         end
    --     else
    --         chatBox.say("§eДоступные версии:")
    --         for _, entry in ipairs(changelog) do
    --             chatBox.say("§a" .. entry.version)
    --         end
    --         chatBox.say("§aИспользуйте: @changelog <версия>")
    --     end

    elseif msg == "@restart" then
        if isChatBox then
            chatBox.say("§cПерезагрузка системы...")
        end
        silentstop()
        computer.shutdown(true)
    end
end

local function stripFormatting(s)
    if not s then return "" end
    -- убираем Minecraft-подобные цветовые коды '§x'
    s = s:gsub("§.", "")
    return s
end

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$") or ""
end

local function chatMessageHandler()
    while not exit do
        local eventData = { event.pull(1, "chat_message") }
        if eventData[1] == "chat_message" then
            local _, _, nick, rawMsg = table.unpack(eventData)

            -- очистить сообщение, привести к нижнему регистру и обрезать пробелы
            local clean = trim(stripFormatting(tostring(rawMsg)):lower())

            -- вытащить первую "словную" часть (команду) и остаток (аргументы)
            local command = clean:match("^(%S+)")
            local args = ""
            if command then
                args = clean:match("^%S+%s*(.*)$") or ""
            end

            -- если команда есть в списке — передаём в обработчик
            if command and chatCommands[command] then
                -- изменил сигнатуру: передаю команду и аргументы отдельно
                handleChatCommand(nick, command, args)
            end
        end
        os.sleep(0)
    end
end

-- ----------------------------------------------------------------------------------------------------

local function handleTouch(x, y, uuid)
    if y >= config.clickArea1.y1 and
        y <= config.clickArea1.y2 and 
        x >= config.clickArea1.x1 and 
        x <= config.clickArea1.x2 then
        buffer.drawRectangle(12, 44, 26, 3, colors.bg3, 0, " ")
        animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfb3737)
        animatedButton(2, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfb3737)
        buffer.drawChanges()
        starting = false
        if reactors <= 0 then
            message("У вас не подключено ни одного реактора!", colors.msgwarn, 34)
            os.sleep(0.2)
            animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
            buffer.drawChanges()
            return
        end
        if work == false then
            drawStatus()
            if any_reactor_on == false then
                message("Реакторы уже отключенны!", colors.msgwarn)
                os.sleep(0.2)
                animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
                buffer.drawChanges()
            else
                stop()
                updateReactorData()
                drawWidgets()
                drawRFinfo()
                os.sleep(0.2)
                animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
                buffer.drawChanges()
            end
            return
        end
        work = false
        stop()
        updateReactorData()
        os.sleep(0.2)
        animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
        buffer.drawChanges()

        os.sleep(0.3)
        drawDynamic()
    elseif 
        y >= config.clickArea19.y1 and
        y <= config.clickArea19.y2 and 
        x >= config.clickArea19.x1 and 
        x <= config.clickArea19.x2 then
        buffer.drawRectangle(4, 44, 6, 3, colors.bg3, 0, " ")
        animatedButton(1, 5, 44, "🔧", nil, nil, 4, nil, nil, 0x8100cc, 0xffffff)
        animatedButton(2, 5, 44, "🔧", nil, nil, 4, nil, nil, 0x8100cc, 0xffffff)
        buffer.drawChanges()
        
        os.sleep(0.2)
        animatedButton(1, 5, 44, "🔧", nil, nil, 4, nil, nil, 0xa91df9, 0xffffff)
        buffer.drawChanges()
        
        drawSettingsMenu()
    elseif 
        y >= config.clickArea20.y1 and
        y <= config.clickArea20.y2 and 
        x >= config.clickArea20.x1 and 
        x <= config.clickArea20.x2 then
        buffer.drawRectangle(4, 47, 6, 3, colors.bg3, 0, " ")
        animatedButton(1, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0x8100cc, 0x05e2ff)
        animatedButton(2, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0x8100cc, 0x05e2ff)
        buffer.drawChanges()
        
        os.sleep(0.2)
        animatedButton(1, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0xa91df9, 0x05e2ff)
        buffer.drawChanges()
        
        drawInfoMenu()    
    elseif 
        y >= config.clickArea4.y1 and
        y <= config.clickArea4.y2 and 
        x >= config.clickArea4.x1 and 
        x <= config.clickArea4.x2 then
        buffer.drawRectangle(40, 44, 25, 3, colors.bg3, 0, " ")
        animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x61ff52)
        animatedButton(2, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x61ff52)
        buffer.drawChanges()
        starting = true
        if reactors <= 0 then
            message("У вас не подключено ни одного реактора!", colors.msgwarn, 34)
            os.sleep(0.2)
            animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
            buffer.drawChanges()
            return
        end
        if work == true then
            drawStatus()
            if any_reactor_off == true then
                start()
                os.sleep(0.2)
                animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
                buffer.drawChanges()
                drawWidgets()
                drawRFinfo()
            else
                message("Реакторы уже запущены!", colors.msgwarn)
                os.sleep(0.2)
                animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
                buffer.drawChanges()
                return
            end
            return
        end
        work = true
        start()
        updateReactorData()
        os.sleep(0.2)
        animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
        buffer.drawChanges()
        
        os.sleep(0.3)
        drawDynamic()
    elseif
        y >= config.clickArea2.y1 and
        y <= config.clickArea2.y2 and 
        x >= config.clickArea2.x1 and 
        x <= config.clickArea2.x2 then
        buffer.drawRectangle(12, 47, 26, 3, colors.bg3, 0, " ")
        animatedButton(1, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn2)
        animatedButton(2, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn2)
        stop()
        message("Перезагружаюсь!")
        buffer.drawChanges()
        os.sleep(0.2)
        animatedButton(1, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn)
        buffer.drawChanges()
        os.sleep(1)
        shell.execute("reboot")
    elseif
        y >= config.clickArea3.y1 and
        y <= config.clickArea3.y2 and 
        x >= config.clickArea3.x1 and 
        x <= config.clickArea3.x2 then
        buffer.drawRectangle(40, 47, 25, 3, colors.bg3, 0, " ")
        animatedButton(1, 41, 47, "Выход из программы.", nil, nil, 23, nil, nil, colors.whitebtn2)
        animatedButton(2, 41, 47, "Выход из программы.", nil, nil, 23, nil, nil, colors.whitebtn2)
        if work == true then
            work = false
            message("Отключаю реакторы!", colors.msginfo)
            stop()
            drawWidgets()
            drawRFinfo()
            os.sleep(0.3)
        end
        message("Завершаю работу программы...", colors.msgerror)
        buffer.drawChanges()
        os.sleep(0.2)
        animatedButton(1, 41, 47, "Выход из программы.", nil, nil, 23, nil, nil, colors.whitebtn)
        buffer.drawChanges()
        os.sleep(0.5)
        buffer.clear(0x000000)
        buffer.drawChanges()
        shell.execute("clear")
        rawset(_G, "__NR_ON_INTERRUPT__", nil)
        exit = true
        os.exit()
    elseif
        y >= config.clickArea5.y1 and
        y <= config.clickArea5.y2 and 
        x >= config.clickArea5.x1 and 
        x <= config.clickArea5.x2 then
        buffer.drawRectangle(67, 44, 20, 3, colors.bg3, 0, " ")
        animatedButton(1, 68, 44, "МЭ: выкл.", nil, nil, 18, nil, nil, 0x38afff)
        animatedButton(2, 68, 44, "МЭ: выкл.", nil, nil, 18, nil, nil, 0x38afff)
        buffer.drawChanges()
        os.sleep(0.2)
        animatedButton(1, 68, 44, "МЭ: выкл.", nil, nil, 18, nil, nil, nil)
        buffer.drawChanges()
    elseif
        y >= config.clickArea6.y1 and
        y <= config.clickArea6.y2 and 
        x >= config.clickArea6.x1 and 
        x <= config.clickArea6.x2 then
        buffer.drawRectangle(67, 47, 20, 3, colors.bg3, 0, " ")
        animatedButton(1, 68, 47, "Метрика: " .. status_metric, nil, nil, 18, nil, nil, colors.whitebtn2)
        animatedButton(2, 68, 47, "Метрика: " .. status_metric, nil, nil, 18, nil, nil, colors.whitebtn2)
        metric = metric + 1
        if metric == 0 then
            status_metric = "Auto"
        elseif metric == 1 then
            status_metric = "Rf, Mb"
            metricRf = "Rf"
            metricMb = "Mb"
            message("Метрика изменена на: Rf, Mb!", nil, 34)
        elseif metric == 2 then
            status_metric = "kRf, kMb"
            metricRf = "kRf"
            metricMb = "kMb"
            message("Метрика изменена на: kRf, kMb!", nil, 34)
        elseif metric == 3 then
            status_metric = "mRf, mMb"
            metricRf = "mRf"
            metricMb = "mMb"
            message("Метрика изменена на: mRf, mMb!", nil, 34)
        elseif metric == 4 then
            status_metric = "gRf, mMb"
            metricRf = "gRf"
            metricMb = "mMb"
            message("Метрика изменена на: gRf, mMb!", nil, 34)
        elseif metric > 4 then
            status_metric = "Auto"
            metricRf = "Rf"
            metricMb = "Mb"
            message("Метрика изменена на: Auto!", nil, 34)
            metric = 0
        end
        os.sleep(0.2)
        animatedButton(1, 68, 47, "Метрика: " .. status_metric, nil, nil, 18, nil, nil, colors.whitebtn)
        drawDynamic()
    end
    for i = 1, reactors do
        local clickArea = config["clickArea" .. (6 + i)]
        if y >= clickArea.y1 and y <= clickArea.y2 and x >= clickArea.x1 and x <= clickArea.x2 and reactor_aborted[i] == false or nil then
            local Rnum = i
            local xw, yw = widgetCoords[Rnum][1], widgetCoords[Rnum][2]

            buffer.drawRectangle(xw + 5, yw + 8, 12, 3, colors.bg, 0, " ")
            animatedButton(1, xw + 6, yw + 8, (reactor_work[Rnum] and "Отключить" or "Включить"), nil, nil, 10, nil, nil, (reactor_work[Rnum] and 0xfb3737 or 0x61ff52))
            animatedButton(2, xw + 6, yw + 8, (reactor_work[Rnum] and "Отключить" or "Включить"), nil, nil, 10, nil, nil, (reactor_work[Rnum] and 0xfb3737 or 0x61ff52))
            buffer.drawChanges()

            drawStatus(Rnum)

            if reactor_work[Rnum] then
                stop(Rnum)
                updateReactorData(Rnum)
            else
                start(Rnum)
                starting = true
                updateReactorData(Rnum)
            end
            
            if not any_reactor_on then
                work = false
                starting = false
            end

            os.sleep(0.2)
            animatedButton(1, xw + 6, yw + 8, (reactor_work[Rnum] and "Отключить" or "Включить"), nil, nil, 10, nil, nil, (reactor_work[Rnum] and 0xfd3232 or 0x2beb1a))
            drawWidgets()
            break
        end
        
    end
end

-- ----------------------------------------------------------------------------------------------------
local function mainLoop()
    -- Сбрасываем все динамические переменные, чтобы избежать конфликта данных.
    -- Это обеспечивает "чистый" старт при каждом запуске.
    reactors = 0
    any_reactor_on = false
    any_reactor_off = false

    -- Очищаем массивы вместо сброса каждого элемента.
    -- Это более надежно, так как гарантирует, что в массивах не останется старых данных.
    reactor_work = {}
    temperature = {}
    reactor_type = {}
    reactor_address = {}
    reactor_aborted = {}
    reactors_proxy = {}
    reactor_rf = {}
    reactor_getcoolant = {}
    reactor_maxcoolant = {}
    reactor_depletionTime = {}
    adapters_proxy = {}
    adapters_address = {}
    reactor_adapter_index = {}
    reactor_level = {}
    reactor_rods_filled = {}
    reactor_rods_total = {}
    reactor_rods_type = {}
    reactor_rods_cache_at = {}
    
    me_proxy = nil
    me_network = false
    flux_network = false
    flux_checked = false
    second = 0
    minute = 0
    hour = 0
    last_me_address = nil
    
    if porog < 0 then porog = 0 end
    
    switchTheme(theme)
    initReactors()
    initAdapters()
    local addr = initMe()
    initFlux()
    initChatBox()
    silentstop()
    
    for i = 1, (flux_network and 19 or 21) do
        consoleLines[i] = ""
    end 
    last_me_address = addr
    drawStatic()
    drawDynamic()
    message("------Reactor Control v" .. version .. "-------", 0x72f8ff)
    message("Автор приложения: Flixmo", 0x72f8ff)
    message("Версия приложения: " .. version .. ", Build " .. build, 0x72f8ff)
    message("Авто-обновление: " .. (updateCheck and "Включенно" or "Выключенно"), 0x72f8ff, 34)
    message("Реакторов найдено: " .. reactors, 0x72f8ff)
    message("МЭ-сеть: " .. (me_network and "Подключена" or "Не подключена"), 0x72f8ff)
    message("Flux-сеть: " .. (flux_network and "Подключена" or "Не подключена"), 0x72f8ff)
    message("ChatBox: " .. (isChatBox and "Подключен" or "Не подключен"), 0x72f8ff)
    message("---------------------------------", 0x72f8ff) --34
    message(" ")
    userUpdate()
    message("Инициализация реакторов...", colors.textclr)
    -- supportersText = loadSupportersFromURL("https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/supporters.txt")
    -- changelog = loadChangelog("https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/changelog.lua")
    updateReactorData()
    if reactors ~= 0 then
        message("Реакторы инициализированы!", colors.msginfo, 34)
    else
        message("Реакторы не найдены!", colors.msgerror)
        message("Проверьте подключение реакторов!", colors.msgerror, 34)
    end
    if starting == true then
        start()
    end

    if isChatBox then
        chatThread = require("thread").create(chatMessageHandler)
        message("Чат-бокс подключен! Список команд: @help", colors.msginfo)
        chatBox.say("§2Чат-бокс подключен! §aСписок команд: @help")
    end

    if work == true then
        if any_reactor_off == true then
            start()
            os.sleep(0.2)
            drawWidgets()
            drawRFinfo()
        else
            os.sleep(0.2)
            return
        end
        return
    end
    if offFluid == true then
        for i = 1, reactors do
            if reactor_type[i] == "Fluid" then
                if reactor_work[i] == true then
                    stop(i)
                end
                updateReactorData(i)
                reactor_aborted[i] = true
            end
        end
        drawWidgets()
    end
    -- checkVer()
    if isFirstStart == true then
        drawSettingsMenu()
        message("Первый запуск программы завершен!", colors.msginfo)
        isFirstStart = false
        saveCfg()
    end
    depletionTime = depletionTime or 0
    reactors = tonumber(reactors) or 0
    while true do
        if exit == true then
            return
        end

        local now = computer.uptime()

        if reactors > 0 and reactorsChanged() then
            os.sleep(1)
            initReactors()
            drawDynamic()
            updateReactorData()
            message("Список реакторов обновлён", colors.textclr)
        end

        if offFluid == true then
            for i = 1, reactors do
                if reactor_type[i] == "Fluid" then
                    if reactor_work[i] == true then
                        stop(i)
                        updateReactorData(i)
                        reactor_aborted[i] = true
                        drawWidgets()
                    end
                end
            end
        end

        if now - lastTime >= 1 then
            lastTime = now
            second = second + 1
            if work == true then
                if second % 5 == 0 then
                    for i = 1, reactors do
                        local proxy = reactors_proxy[i]
                        if proxy and proxy.getTemperature then
                            reactor_rf[i] = safeCall(proxy, "getEnergyGeneration", 0)
                            reactor_maxcoolant[i] = safeCall(proxy, "getMaxFluidCoolant", 0) or 1
                        else
                            reactor_rf[i] = 0
                            reactor_maxcoolant[i] = 1
                        end
                        
                    end
                    drawRFinfo()
                end

                if second % 2 == 0 then
                    for i = 1, reactors do
                        if reactor_type[i] == "Fluid" then
                            local proxy = reactors_proxy[i]
                            if proxy and proxy.getFluidCoolant then
                                temperature[i]  = safeCall(proxy, "getTemperature", 0)
                                reactor_getcoolant[i] = safeCall(proxy, "getFluidCoolant", 0) or 0
                            else
                                reactor_getcoolant[i] = 0
                                temperature[i] = 0
                            end
                        end
                        
                    end
                end
            -- else -- Убрал else возможно временно если будут баги
                if second % 13 == 0 then
                    for i = 1, reactors do
                        local proxy = reactors_proxy[i]
                        if proxy and proxy.hasWork then
                            reactor_work[i] = safeCall(proxy, "hasWork", false)
                            reactor_type[i] = safeCall(proxy, "isActiveCooling", false) and "Fluid" or "Air"
                        else
                            reactor_work[i] = false
                        end
                        
                    end
                end
            end

            for i = 1, reactors do
                if reactor_type[i] == "Fluid" then
                    local current_coolant = reactor_getcoolant[i]
                    local max_coolant = reactor_maxcoolant[i]
                    
                    -- 1. Проверка на аварийную остановку (ниже 60%)
                    if current_coolant <= (max_coolant * 0.68) then
                        if reactor_work[i] == true then
                            silentstop(i)
                            -- updateReactorData(i)
                            reactor_aborted[i] = true
                            reason = "Нет жидкости"
                            message("Реактор " .. i .. " ОСТАНОВЛЕН! Уровень буфера критически низок", colors.msgwarn)
                            message("Проверьте реакторную зону!", colors.msgwarn)
                            -- message("Запуск реактора #" .. i .. " возможен только вручную.", colors.msgwarn)
                        end
                    end

                    -- 2. Проверка на готовность к запуску (выше 80%)
                    -- Это позволит убрать флаг ошибки, когда бак достаточно заполнится
                    if reactor_aborted[i] and current_coolant >= (max_coolant * 0.8) and offFluid == false then
                        reactor_aborted[i] = false
                        message("Реактор " .. i .. " готов к работе (уровень восстановился).", colors.msginfo)
                    end
                end
            end

            if second % 5 == 0 then
                consumeSecond = getTotalFluidConsumption()
                drawStatus()
                drawFluxRFinfo()
                if flux_network == true and flux_checked == false then
                    clearRightWidgets()
                    drawDynamic()
                    flux_checked = true
                elseif flux_network == false and flux_checked == true then
                    clearRightWidgets()
                    drawDynamic()
                    flux_checked = false
                end
            end

            if any_reactor_on then
                if depletionTime <= 0 then
                    local newTime = getDepletionTime()
                    if newTime > 0 then
                        depletionTime = newTime
                    else
                        depletionTime = 0
                    end
                else
                    depletionTime = depletionTime - 1
                end
            else
                depletionTime = 0
            end
            if second >= 60 then
                minute = minute + 1
                -- if minute % 10 == 0 then
                --     supportersText = loadSupportersFromURL("https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/supporters.txt")
                --     changelog = loadChangelog("https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/changelog.lua")
                -- end
                if minute >= 60 then
                    -- checkVer()
                    hour = hour + 1
                    minute = 0
                end
                second = 0
            end
            drawTimeInfo()
            drawWidgets()
        end
        -- if supportersText then
        --     drawMarquee(124, 6, supportersText ..  "                            ", 0xF15F2C)
        -- end
        local eventData = {event.pull(0.05)}
        local eventType = eventData[1]
        if eventType == "touch" then
            local _, _, x, y, button, uuid = table.unpack(eventData)
            handleTouch(x, y)
        end
        os.sleep(0)
    end
end

-- ----------------------------------------------------------------------------------------------------
local lastCrashTime = 0
while not exit do
    local ok, err = xpcall(mainLoop, debug.traceback)
    if not ok then
        local now = computer.uptime() -- Заменил os.time() на computer.uptime()

        if tostring(err):lower():find("interrupted") or exit == true then
            return
        end
        
        if now - lastCrashTime < 5 then
            logError("FAILSAFE: Rapid crashing detected.")
            message("Rapid crashing detected.", 0xff0000, 34)
            os.sleep(5)
        end
        lastCrashTime = now

        logError("Global Error:")
        logError(err)
        message("Code: " .. tostring(err), 0xff0000, 34)
        message("Global Error!", 0xff0000, 34)
        message("Restarting in 3 seconds...", 0xffa500, 34)
    
        os.sleep(3)
    end
end
