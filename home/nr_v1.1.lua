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
        file:write("-- Впишите никнеймы игроков которым будет разрешеннен доступ к ПК, обязательно ради вашей безопасности!\n")
        file:write("users = {} -- Пример: {\"Flixmo\", \"Nickname1\"} -- Именно что с кавычками и запятыми!\n")
        file:write("usersold = {} -- Не трогайте, может заблокировать ПК!\n\n")
        file:write("-- Тема интерфейса в системе по стандарту\n")
        file:write("theme = false -- (false темная, true светлая)\n\n")
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
local ismechecked = false
local flux_network = false
local flux_checked = false

local consoleLines = {}
local work = false
local starting = false

local reactor_work       = {}
local reactor_aborted    = {}
local temperature        = {}
local reactor_type       = {}
local reactor_address    = {}
local reactors_proxy     = {}
local reactor_rf         = {}
local reactor_depletionTime = {}
local reactor_ConsumptionPerSecond = {}
local last_me_address = nil
local me_network = false
local me_proxy = nil
local maxThreshold = 10^12
local reason = nil
local depletionTime = 0
local consumeSecond = 0
local MeSecond = 0

local isChatBox = component.isAvailable("chat_box") or false
local chatBox = isChatBox and component.chat_box or nil
local chatThread = nil
local chatCommands = {
    ["@help"] = true,
    ["@status"] = true,
    ["@start"] = true,
    ["@stop"] = true,
    ["@restart"] = true,
    ["@exit"] = true,
    ["@changelog"] = true,
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
    clickArea18 = {x1=widgetCoords[12][1]+5, y1=widgetCoords[12][2]+9, x2=widgetCoords[12][1]+11, y2=widgetCoords[12][2]+10} -- Реактор 12
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
        temperature[i] = 0
        reactor_aborted[i] = false
        reactor_depletionTime[i] = 0
    end
end

local function initMe()
    me_network = component.isAvailable("me_controller") or component.isAvailable("me_interface")
    if me_network == true then
        if component.isAvailable("me_controller") then
            local addr = component.list("me_controller")()
            me_proxy = component.proxy(addr)
            current_me_address = addr
        elseif component.isAvailable("me_interface") then
            local addr = component.list("me_interface")()
            me_proxy = component.proxy(addr)
            current_me_address = addr
        else
            me_proxy = nil
            current_me_address = nil
        end
    else
        -- МЭ не найдена
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
        local reactorTime = 0

        if type(rods) == "table" and #rods > 0 then
            local maxRod = 0
            for _, rod in ipairs(rods) do
                if type(rod) == "table" and rod[6] then
                    -- Добавлена проверка на число
                    local fuelLeft = tonumber(rod[6]) or 0
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
            buffer.drawRectangle(x + 1, y, 20, 11, colors.bg, 0, " ")
            buffer.drawRectangle(x, y + 1, 22, 9, colors.bg, 0, " ")

            buffer.drawText(x,  y,  colors.bg, brailleChar(brail_status[1]))
            buffer.drawText(x + 21, y,  colors.bg, brailleChar(brail_status[2]))
            buffer.drawText(x + 21, y + 10,  colors.bg, brailleChar(brail_status[3]))
            buffer.drawText(x,  y + 10,  colors.bg, brailleChar(brail_status[4]))

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

            buffer.drawText(x + 6,  y + 1,  colors.textclr, "Реактор #" .. i)
            buffer.drawText(x + 4,  y + 2,  colors.textclr, "Нагрев: " .. (temperature[i] or "-") .. "°C")
            buffer.drawText(x + 4,  y + 3,  colors.textclr, formatRFwidgets(reactor_rf[i]))
            buffer.drawText(x + 4,  y + 4,  colors.textclr, "Тип: " .. (reactor_type[i] or "-"))
            buffer.drawText(x + 4,  y + 5,  colors.textclr, "Запущен: " .. (reactor_work[i] and "Да" or "Нет"))
            buffer.drawText(x + 4,  y + 6,  colors.textclr, "Распад: " .. secondsToHMS(reactor_depletionTime[i] or 0))
            animatedButton(1, x + 6, y + 8, (reactor_work[i] and "Отключить" or "Включить"), nil, nil, 10, nil, nil, (reactor_work[i] and 0xfd3232 or 0x2beb1a))
        else
            local x, y = widgetCoords[i][1], widgetCoords[i][2]
            buffer.drawRectangle(x + 1, y, 20, 11, colors.msgwarn, 0, " ")
            buffer.drawRectangle(x, y + 1, 22, 9, colors.msgwarn, 0, " ")

            buffer.drawText(x,  y,  colors.msgwarn, brailleChar(brail_status[1]))
            buffer.drawText(x + 21, y,  colors.msgwarn, brailleChar(brail_status[2]))
            buffer.drawText(x + 21, y + 10,  colors.msgwarn, brailleChar(brail_status[3]))
            buffer.drawText(x,  y + 10,  colors.msgwarn, brailleChar(brail_status[4]))

            buffer.drawText(x + 6,  y + 1,  colors.msgerror, "Реактор #" .. i)
            buffer.drawText(x + 4,  y + 3,  colors.msgerror, "Нагрев: " .. (temperature[i] or "-") .. "°C")
            buffer.drawText(x + 4,  y + 4,  colors.msgerror, "Тип: " .. (reactor_type[i] or "-"))
            buffer.drawText(x + 4,  y + 5,  colors.msgerror, "Cтатус:")
            buffer.drawText(x + 4,  y + 6,  colors.msgerror, "Аварийно отключен!")
            buffer.drawText(x + 4,  y + 7,  colors.msgerror, "Причина:")
            buffer.drawText(x + 4,  y + 8,  colors.msgerror, (reason or "Неизвестная ошибка!"))
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

local function darkenColor(baseColor, t)
    return lerpColor(baseColor, 0x303030, 1 - t)
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

local scrollPos = 1
local maxWidth = 33

-- функция бегущей строки
local function drawMarquee(x, y, text, color)
    local textLength = unicode.len(text) -- считаем символы, а не байты

    if textLength > maxWidth then
        -- видимый кусок
        local visible = unicode.sub(text, scrollPos, scrollPos + maxWidth - 1)

        local visibleLen = unicode.len(visible)
        if visibleLen < maxWidth then
            local need = maxWidth - visibleLen
            visible = visible .. unicode.sub(text, 1, need)
        end

        buffer.drawText(x, y, color, visible)

        scrollPos = scrollPos + 1
        if scrollPos > textLength then
            scrollPos = 1
        end
    else
        buffer.drawText(x, y, color, text)
    end
    buffer.drawChanges()
end

if not fs.exists("tmp") then
    fs.makeDirectory("tmp")
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
    buffer.drawText(124, fl_y1, colors.textclr, "МЭ: Обн. ч/з..")
    buffer.drawText(141, fl_y1, colors.textclr, "Время работы:")
    buffer.drawText(139, fl_y1, colors.bg2, brailleChar(brail_cherta[1]))
    buffer.drawText(139, fl_y1+1, colors.bg2, brailleChar(brail_cherta[2]))
    buffer.drawText(139, fl_y1+2, colors.bg2, brailleChar(brail_cherta[1]))
    buffer.drawText(139, fl_y1+3, colors.bg2, brailleChar(brail_cherta[1]))
    drawDigit(125, fl_y1+2, brail_time, 0xaa4b2e)
    -- ---------------------------------------------------------------------------
    buffer.drawRectangle(127, fl_y1+2, 12, 2, colors.bg, 0, " ")
    
    drawNumberWithText(134, fl_y1+2, (me_network and (60 - MeSecond) or 0), 2, colors.textclr, "Sec", colors.textclr)
    
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
    animatedButton(1, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0xa91df9, 0x05e2ff)
    animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
    animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
    animatedButton(1, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, nil)
    animatedButton(1, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn)
    animatedButton(1, 41, 47, "Выход из программы.", nil, nil, 23, nil, nil, colors.whitebtn)
    animatedButton(1, 68, 47, "Метрика: " .. status_metric, nil, nil, 18, nil, nil, colors.whitebtn)

    buffer.drawText(123, 50, (theme and 0xc3c3c3 or 0x666666), "Reactor Control v" .. version .. "." .. build .. " by Flixmo")
    -- buffer.drawText(130, 50, (theme and 0xc3c3c3 or 0x666666), "by Flixmo") -- Контакты: VK: @p1kachu337, Discord: p1kachu337 TG: @sh1zurz
    
    buffer.drawChanges()
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
        reactor_type[i]     = "Air"
        reactor_rf[i]       = safeCall(proxy, "getEnergyGeneration", 0)
        reactor_work[i]     = safeCall(proxy, "hasWork", false)
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
        local proxy = reactors_proxy[i]
        safeCall(proxy, "activate")
        reactor_work[i] = true
        if num then
            message("Реактор #" .. i .. " запущен!", colors.msginfo, 34)
        end
    end
    if not num then
        message("Реакторы запущены!", colors.msginfo, 34)
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
        safeCall(proxy, "deactivate")
        reactor_work[i] = false
        drawStatus()
        if num then
            message("Реактор #" .. i .. " отключен!", colors.msginfo, 34)
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

local function updateMeProxy()
    if component.isAvailable("me_controller") then
        me_proxy = component.proxy(component.list("me_controller")())
    elseif component.isAvailable("me_interface") then
        me_proxy = component.proxy(component.list("me_interface")())
    else
        me_proxy = nil
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

local function meChanged()
    local current_me_address = nil

    if component.isAvailable("me_controller") then
        current_me_address = component.list("me_controller")()
    elseif component.isAvailable("me_interface") then
        current_me_address = component.list("me_interface")()
    end

    if last_me_address ~= current_me_address then
        last_me_address = current_me_address
        return true
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
                    ", work=" .. tostring(work) ..
                    ", any_reactor_on=" .. tostring(any_reactor_on) .. "\n")

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
        removeSearchField(2)
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
                local newNick = searchFields[2].text:match("^%s*(.-)%s*$") -- trim
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
                        end
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

    local infotext = {
        "Автор программы: Flixmo",
        "",
        "Контакты: vk.com/p1kachu337, Discord: p1kachu337, Telegram: @sh1zurz",
        "",
        "GitHub проекта: github.com/Flixmo/Reactor-Control-for-OpenComputers",
        "",
        "Поддержать проект можно, предварительно связавшись со мной для согласования способа поддержки (на карту, boosty, или иной подарок).",
        "",
        "Лицензия: MIT License",
        "",
        "Описание программы:",
        "Reactor Control — программа мониторинга, контроля и управления критически важными системами реакторного комплекса для игроков сервера McSkill HiTech 1.12.2, разработанная на базе мода OpenComputers. Программа предназначена для централизованного управления реакторами и связанными с ними инфраструктурными системами, а также для автоматического предотвращения аварийных ситуаций без необходимости постоянного ручного контроля.",
        "",
        "Программа поддерживает работу с воздушными HT-реакторами, интеграцию с Applied Energistics 2 для мониторинга и анализа, а также интеграцию с Flux Networks для контроля энергетической сети. Подключение осуществляется через адаптеры OpenComputers к соответствующим контроллерам. Основной упор сделан на стабильность, безопасность и корректную работу реакторных комплексов любого масштаба.",
        "",
        "Реализована автоматическая система безопасности для реакторов. Реакторы автоматически отключаются при критических проблемах и переводятся в аварийный режим, в котором ручной запуск блокируется. После восстановления нормальных условий реакторы автоматически возвращаются в штатный режим и запускаются. Контроль состояния сетей выполняется на постоянной основе.",
        "",
        "Графический интерфейс программы отображает детальную информацию по каждому реактору, включая температуру, текущую генерацию энергии, тип реактора, статус включения, индивидуальный отсчёт времени до распада топливных стержней. В общем статусе комплекса выводится количество установленных реакторов и текущее состояние системы.",
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

-- ----------------------------------------------------------------------------------------------------


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
            chatBox.say("§a@start - запуск всех реакторов (или @start 1 для запуска только 1-го)")
            chatBox.say("§a@stop - остановка всех реакторов (или @stop 1 для остановки только 1-го)")
            chatBox.say("§a@exit - выход из программы")
            chatBox.say("§a@restart - перезагрузка компьютера")
            chatBox.say("§a@changelog - показать изменения в обновлениях(пример: @changelog 1.1.1)") -- Скачивается массив из гитхаба в массиве ченджлог выглядит так {"1.0.0 - описание, переносы строк и тп, все учитывать и выводить в чат","1.0.1 - описание","1.1.0 - описание"}
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

            chatBox.say("§aГенерация реакторов: " .. rf .. " RF/t")
            -- chatBox.say("§aСостояние реакторов:")
            -- for i = 1, reactors do
            --     if reactor_work[i] == true then
            --         chatBox.say("§aРеактор " .. i .. ": §2Запущен")
            --         chatBox.say("§aТемпература: §e" .. reactor_temp[i] .. " °C")
            --         chatBox.say("§aВыработка: §e" .. reactor_rf[i] .. " RF/t")
            --         chatBox.say("§aРаспад топлива через: §e" .. secondsToHMS(reactor_depletionTime[i] or 0))
            --         chatBox.say("§aТип реактора: §e" .. reactor_type[i])
            --     else
            --         chatBox.say("§aРеактор " .. i .. ": §cОстановлен")
            --     end
            -- end
        end

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

    elseif msg == "@info" then
        if isChatBox then
            chatBox.say("§bReactor Control v" .. version .. " Build " .. build)
            chatBox.say("§aАвтор: §eFlixmo")
            chatBox.say("§aGitHub: §1https://github.com/Flixmo/Reactor-Control-for-OpenComputers")
            chatBox.say("§aПоддержать автора на §6Boosty: §1https://boosty.to/p1kachu337")
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

    elseif msg:match("^@changelog") then
        local versionReq = args:match("^(%S+)")
        if not changelog then
            chatBox.say("§cОшибка загрузки changelog.lua!")
            return
        end

        if versionReq then
            local found = false
            for _, entry in ipairs(changelog) do
                if entry.version == versionReq then
                    chatBox.say("§eИзменения в версии " .. entry.version .. ":")
                    for _, line in ipairs(entry.changes) do
                        chatBox.say("§a- " .. line)
                    end
                    found = true
                    break
                end
            end
            if not found then
                chatBox.say("§cВерсия " .. versionReq .. " не найдена в ченджлоге!")
            end
        else
            chatBox.say("§eДоступные версии:")
            for _, entry in ipairs(changelog) do
                chatBox.say("§a" .. entry.version)
            end
            chatBox.say("§aИспользуйте: @changelog <версия>")
        end

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
        animatedButton(1, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, 0x38afff)
        animatedButton(2, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, 0x38afff)
        buffer.drawChanges()
        os.sleep(0.2)
        animatedButton(1, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, nil)
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
    elseif
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
    reactor_depletionTime = {}
    
    me_proxy = nil
    me_network = false
    flux_network = false
    flux_checked = false
    second = 0
    minute = 0
    hour = 0
    last_me_address = nil

    switchTheme(theme)
    initReactors()
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
    message("Реакторов найдено: " .. reactors, 0x72f8ff)
    message("МЭ-сеть: " .. (me_network and "Подключена" or "Не подключена"), 0x72f8ff)
    message("Flux-сеть: " .. (flux_network and "Подключена" or "Не подключена"), 0x72f8ff)
    message("ChatBox: " .. (isChatBox and "Подключен" or "Не подключен"), 0x72f8ff)
    message("---------------------------------", 0x72f8ff) --34
    message(" ")
    userUpdate()
    message("Инициализация реакторов...", colors.textclr)
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

        if meChanged() then
            os.sleep(1)
            initMe()
            message("МЭ система обновленна", colors.textclr)
        end


        if now - lastTime >= 1 then
            lastTime = now
            second = second + 1
            if me_network then
                MeSecond = MeSecond + 1
            end
            if work == true then
                if second % 5 == 0 then
                    for i = 1, reactors do
                        local proxy = reactors_proxy[i]
                        if proxy and proxy.getTemperature then
                            reactor_rf[i] = safeCall(proxy, "getEnergyGeneration", 0)
                        else
                            reactor_rf[i] = 0
                        end
                        
                    end
                    drawRFinfo()
                end

            -- else -- Убрал else возможно временно если будут баги
                if second % 13 == 0 then
                    for i = 1, reactors do
                        local proxy = reactors_proxy[i]
                        if proxy and proxy.hasWork then
                            reactor_work[i] = safeCall(proxy, "hasWork", false)
                            reactor_type[i] = "Air"
                        else
                            reactor_work[i] = false
                        end
                        
                    end
                end
            end
            if second % 5 == 0 then
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
                if minute % 10 == 0 then
                end
                if minute >= 60 then
                    hour = hour + 1
                    minute = 0
                end
                second = 0
            end
            drawTimeInfo()
            drawWidgets()
        end
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
