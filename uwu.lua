local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- ======================== LOAD WINDUI ========================
local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()

-- ======================== CONFIG SYSTEM ========================
local ConfigManager = {}
ConfigManager.FilePath = "ServerHopperConfig"
ConfigManager.DefaultConfig = {
    webhookUrl = "",
    autoHopEnabled = false,
    maxPlayersThreshold = 10,
    searchInterval = 5,
    notifyOnHop = true,
    notifyOnServerFound = true,
    notifyErrors = true
}

function ConfigManager:Load()
    if writefile and readfile then
        local success, data = pcall(function()
            return HttpService:JSONDecode(readfile(self.FilePath))
        end)
        if success then
            return data
        end
    end
    return self.DefaultConfig
end

function ConfigManager:Save(config)
    if writefile then
        pcall(function()
            writefile(self.FilePath, HttpService:JSONEncode(config))
        end)
    end
end

getgenv().Config = ConfigManager:Load()

-- ======================== DISCORD WEBHOOK ========================
local DiscordNotifier = {}

function DiscordNotifier:Send(title, description, color)
    if not getgenv().Config.webhookUrl or getgenv().Config.webhookUrl == "" then
        return false
    end
    
    local payload = {
        embeds = {
            {
                title = title,
                description = description,
                color = color or 3447003,
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                footer = {
                    text = "Server Hopper"
                }
            }
        }
    }
    
    local success = pcall(function()
        return game:HttpGet(getgenv().Config.webhookUrl, true, HttpService:JSONEncode(payload))
    end)
    
    return success
end

-- ======================== SERVER HOPPER LOGIC ========================
local ServerHopper = {}
ServerHopper.searching = false
ServerHopper.connection = nil
ServerHopper.hopCount = 0

function ServerHopper:GetServersInGame()
    local PlaceId = game.PlaceId
    local servers = {}
    
    local success, response = pcall(function()
        return game:HttpGet("https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/0?sortOrder=Asc&limit=100")
    end)
    
    if success then
        local decoded = HttpService:JSONDecode(response)
        if decoded.data then
            for _, server in ipairs(decoded.data) do
                table.insert(servers, {
                    id = server.id,
                    players = server.playing,
                    maxPlayers = server.maxPlayers,
                })
            end
        end
    end
    
    return servers
end

function ServerHopper:FindBestServer()
    local servers = self:GetServersInGame()
    local bestServer = nil
    local lowestPlayers = math.huge
    
    for _, server in ipairs(servers) do
        if server.players < lowestPlayers and server.players < getgenv().Config.maxPlayersThreshold then
            if server.id ~= game.JobId then
                bestServer = server
                lowestPlayers = server.players
            end
        end
    end
    
    return bestServer
end

function ServerHopper:HopToServer(serverId)
    local success = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer)
    end)
    
    if success then
        self.hopCount = self.hopCount + 1
        
        if getgenv().Config.notifyOnHop then
            DiscordNotifier:Send(
                "🔄 Server Hopped",
                "Moved to new server\nTotal Hops: " .. self.hopCount,
                65280
            )
        end
    end
    
    return success
end

function ServerHopper:StartAutoHopping()
    if self.connection then
        self.connection:Disconnect()
    end
    
    self.connection = RunService.Heartbeat:Connect(function()
        if not getgenv().Config.autoHopEnabled then
            return
        end
        
        if self.searching then
            return
        end
        
        self.searching = true
        
        task.spawn(function()
            local bestServer = ServerHopper:FindBestServer()
            
            if bestServer then
                if getgenv().Config.notifyOnServerFound then
                    DiscordNotifier:Send(
                        "✅ Server Found",
                        "Found server with " .. bestServer.players .. " players",
                        3447003
                    )
                end
                
                ServerHopper:HopToServer(bestServer.id)
            end
            
            self.searching = false
        end)
    end)
end

function ServerHopper:StopAutoHopping()
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
end

-- ======================== COLORES ========================
local Blue = Color3.fromHex("#257AF7")
local Green = Color3.fromHex("#10C550")
local Red = Color3.fromHex("#EF4F1D")
local Yellow = Color3.fromHex("#ECA201")
local Purple = Color3.fromHex("#7775F2")

-- ======================== CREAR WINDOW ========================
local Window = WindUI:CreateWindow({
    Title = "Server Hopper | WindUI",
    Folder = "ServerHopper",
    Icon = "solar:rocket-bold",
    HideSearchBar = false,
})

-- ======================== TAB 1: HOPPER ========================
local HopperTab = Window:Tab({
    Title = "Hopper",
    Icon = "solar:rocket-bold",
    IconColor = Blue,
    Border = true,
})

local HopperSection = HopperTab:Section({
    Title = "Auto Hopping",
})

HopperSection:Toggle({
    Flag = "AutoHopToggle",
    Title = "Enable Auto Hop",
    Desc = "Automatically hop to servers with fewer players",
    Value = getgenv().Config.autoHopEnabled,
    Callback = function(state)
        getgenv().Config.autoHopEnabled = state
        ConfigManager:Save(getgenv().Config)
        
        if state then
            ServerHopper:StartAutoHopping()
            print("[✓] Auto hopping started")
        else
            ServerHopper:StopAutoHopping()
            print("[✗] Auto hopping stopped")
        end
    end,
})

HopperSection:Space()

HopperSection:Slider({
    Flag = "MaxPlayersSlider",
    Title = "Max Players Threshold",
    Step = 1,
    IsTooltip = true,
    Value = {
        Min = 1,
        Max = 50,
        Default = getgenv().Config.maxPlayersThreshold,
    },
    Callback = function(value)
        getgenv().Config.maxPlayersThreshold = value
        ConfigManager:Save(getgenv().Config)
        print("[Config] Max players set to: " .. value)
    end,
})

HopperSection:Space()

HopperSection:Slider({
    Flag = "IntervalSlider",
    Title = "Search Interval (Seconds)",
    Step = 1,
    IsTooltip = true,
    Value = {
        Min = 1,
        Max = 30,
        Default = getgenv().Config.searchInterval,
    },
    Callback = function(value)
        getgenv().Config.searchInterval = value
        ConfigManager:Save(getgenv().Config)
        print("[Config] Search interval set to: " .. value)
    end,
})

HopperSection:Space()

HopperSection:Button({
    Title = "Hop Now",
    Icon = "rocket",
    Color = Blue,
    Justify = "Center",
    Callback = function()
        print("[Manual] Starting manual hop search...")
        task.spawn(function()
            local bestServer = ServerHopper:FindBestServer()
            if bestServer then
                print("[✓] Found server with " .. bestServer.players .. " players")
                ServerHopper:HopToServer(bestServer.id)
            else
                print("[✗] No suitable servers found")
            end
        end)
    end,
})

-- ======================== TAB 2: DISCORD ========================
local DiscordTab = Window:Tab({
    Title = "Discord",
    Icon = "solar:chat-bold",
    IconColor = Purple,
    Border = true,
})

local DiscordSection = DiscordTab:Section({
    Title = "Webhook Configuration",
})

DiscordSection:Input({
    Flag = "WebhookInput",
    Title = "Webhook URL",
    Placeholder = "https://discord.com/api/webhooks/...",
    Value = getgenv().Config.webhookUrl,
    Callback = function(value)
        getgenv().Config.webhookUrl = value
        ConfigManager:Save(getgenv().Config)
        print("[Config] Webhook URL updated")
    end,
})

DiscordSection:Space()

DiscordSection:Button({
    Title = "Test Webhook",
    Icon = "send",
    Color = Blue,
    Justify = "Center",
    Callback = function()
        if getgenv().Config.webhookUrl == "" then
            print("[✗] Please enter webhook URL first")
            return
        end
        
        print("[Testing] Sending test notification...")
        local success = DiscordNotifier:Send(
            "✅ Test Notification",
            "Your webhook is working correctly!",
            3447003
        )
        
        if success then
            print("[✓] Webhook test successful!")
        else
            print("[✗] Webhook test failed - check URL")
        end
    end,
})

DiscordSection:Space()

local NotifySection = DiscordTab:Section({
    Title = "Notifications",
})

NotifySection:Toggle({
    Flag = "NotifyHop",
    Title = "Notify on Hop",
    Value = getgenv().Config.notifyOnHop,
    Callback = function(state)
        getgenv().Config.notifyOnHop = state
        ConfigManager:Save(getgenv().Config)
    end,
})

NotifySection:Space()

NotifySection:Toggle({
    Flag = "NotifyFound",
    Title = "Notify on Server Found",
    Value = getgenv().Config.notifyOnServerFound,
    Callback = function(state)
        getgenv().Config.notifyOnServerFound = state
        ConfigManager:Save(getgenv().Config)
    end,
})

NotifySection:Space()

NotifySection:Toggle({
    Flag = "NotifyErrors",
    Title = "Notify on Errors",
    Value = getgenv().Config.notifyErrors,
    Callback = function(state)
        getgenv().Config.notifyErrors = state
        ConfigManager:Save(getgenv().Config)
    end,
})

-- ======================== TAB 3: STATISTICS ========================
local StatsTab = Window:Tab({
    Title = "Statistics",
    Icon = "solar:chart-bold",
    IconColor = Green,
    Border = true,
})

local ServerSection = StatsTab:Section({
    Title = "Server Info",
})

local playerParagraph = ServerSection:Paragraph({
    Title = "Players",
    Desc = tostring(#Players:GetPlayers()),
    TextSize = 14,
})

local pingParagraph = ServerSection:Paragraph({
    Title = "Ping",
    Desc = "0ms",
    TextSize = 14,
})

ServerSection:Space()

local HopSection = StatsTab:Section({
    Title = "Hopping Stats",
})

local hopsParagraph = HopSection:Paragraph({
    Title = "Total Hops",
    Desc = tostring(ServerHopper.hopCount),
    TextSize = 14,
})

local jobIdParagraph = HopSection:Paragraph({
    Title = "Current Job ID",
    Desc = game.JobId,
    TextSize = 12,
})

-- Actualizar stats
RunService.Heartbeat:Connect(function()
    local players = #Players:GetPlayers()
    local ping = 0
    
    pcall(function()
        ping = math.floor(game:GetService("Stats").Network:FindFirstChild("ClientReplicator"):GetNetworkReceiveData()[3])
    end)
    
    playerParagraph:Set({
        Title = "Players",
        Desc = tostring(players),
    })
    
    pingParagraph:Set({
        Title = "Ping",
        Desc = ping .. "ms",
    })
    
    hopsParagraph:Set({
        Title = "Total Hops",
        Desc = tostring(ServerHopper.hopCount),
    })
end)

-- ======================== TAB 4: SETTINGS ========================
local SettingsTab = Window:Tab({
    Title = "Settings",
    Icon = "solar:settings-bold",
    IconColor = Yellow,
    Border = true,
})

local ConfigSection = SettingsTab:Section({
    Title = "Configuration",
})

ConfigSection:Button({
    Title = "Save Config",
    Icon = "save",
    Color = Green,
    Justify = "Center",
    Callback = function()
        ConfigManager:Save(getgenv().Config)
        print("[✓] Configuration saved")
    end,
})

ConfigSection:Space()

ConfigSection:Button({
    Title = "Load Config",
    Icon = "download",
    Color = Blue,
    Justify = "Center",
    Callback = function()
        getgenv().Config = ConfigManager:Load()
        print("[✓] Configuration loaded")
    end,
})

ConfigSection:Space()

ConfigSection:Button({
    Title = "Reset Config",
    Icon = "refresh-cw",
    Color = Red,
    Justify = "Center",
    Callback = function()
        getgenv().Config = ConfigManager.DefaultConfig
        ConfigManager:Save(getgenv().Config)
        print("[✓] Configuration reset")
    end,
})

print("[✓] Server Hopper loaded successfully!")
