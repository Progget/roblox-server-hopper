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
ServerHopper.lastHopTime = 0
ServerHopper.totalServersChecked = 0

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
    
    self.totalServersChecked = #servers
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
    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer)
    end)
    
    if success then
        self.hopCount = self.hopCount + 1
        self.lastHopTime = os.time()
        
        if getgenv().Config.notifyOnHop then
            DiscordNotifier:Send(
                "🔄 Server Hopped",
                "Moved to new server with " .. tostring(bestServer.players) .. " players\nTotal Hops: " .. self.hopCount,
                65280
            )
        end
    else
        if getgenv().Config.notifyErrors then
            DiscordNotifier:Send(
                "❌ Hop Failed",
                "Error: " .. tostring(err),
                16711680
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
                print("[ServerHopper] Found server with " .. bestServer.players .. " players")
                
                if getgenv().Config.notifyOnServerFound then
                    DiscordNotifier:Send(
                        "✅ Server Found",
                        "Found server with **" .. bestServer.players .. "** players",
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

-- ======================== COLORS ========================
local Blue = Color3.fromHex("#257AF7")
local Green = Color3.fromHex("#10C550")
local Red = Color3.fromHex("#EF4F1D")
local Yellow = Color3.fromHex("#ECA201")
local Purple = Color3.fromHex("#7775F2")
local Grey = Color3.fromHex("#83889E")

-- ======================== CREATE WINDOW ========================
local Window = WindUI:CreateWindow({
    Title = "Server Hopper | WindUI",
    Folder = "ServerHopper",
    Icon = "solar:rocket-bold",
    HideSearchBar = false,
    OpenButton = {
        Title = "Server Hopper",
        CornerRadius = UDim.new(1, 0),
        Enabled = true,
        Draggable = true,
        Scale = 1,
    },
})

-- ======================== CREAR SECTIONS CON TABS ========================
local HopperSection = Window:Section({
    Title = "Hopper",
})

local DiscordSection = Window:Section({
    Title = "Discord",
})

local StatsSection = Window:Section({
    Title = "Statistics",
})

local SettingsSection = Window:Section({
    Title = "Settings",
})

-- ======================== HOPPER TAB ========================
local HopperTab = HopperSection:Tab({
    Title = "Auto Hopping",
    Icon = "solar:rocket-bold",
    IconColor = Blue,
    Border = true,
})

HopperTab:Toggle({
    Title = "Enable Auto Hop",
    Icon = "solar:toggle-on-bold",
    Value = getgenv().Config.autoHopEnabled,
    Callback = function(value)
        getgenv().Config.autoHopEnabled = value
        ConfigManager:Save(getgenv().Config)
        
        if value then
            ServerHopper:StartAutoHopping()
            WindUI:Notify({
                Title = "✓ Auto Hop Started",
                Content = "Searching for empty servers",
            })
        else
            ServerHopper:StopAutoHopping()
            WindUI:Notify({
                Title = "✗ Auto Hop Stopped",
                Content = "Stopped searching",
            })
        end
    end,
})

HopperTab:Space()

HopperTab:Slider({
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
    end,
})

HopperTab:Space()

HopperTab:Slider({
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
    end,
})

HopperTab:Space()

HopperTab:Button({
    Title = "Hop Now",
    Icon = "rocket",
    Color = Blue,
    Justify = "Center",
    Callback = function()
        task.spawn(function()
            local bestServer = ServerHopper:FindBestServer()
            if bestServer then
                WindUI:Notify({
                    Title = "✓ Server Found",
                    Content = "Players: " .. bestServer.players,
                })
                ServerHopper:HopToServer(bestServer.id)
            else
                WindUI:Notify({
                    Title = "✗ No Servers",
                    Content = "No suitable servers found",
                    Color = "Red",
                })
            end
        end)
    end,
})

HopperTab:Space()

HopperTab:Button({
    Title = "Reset Statistics",
    Icon = "refresh-cw",
    Color = Yellow,
    Justify = "Center",
    Callback = function()
        ServerHopper.hopCount = 0
        WindowUI:Notify({
            Title = "✓ Reset",
            Content = "Statistics cleared",
        })
    end,
})

-- ======================== DISCORD TAB ========================
local DiscordTab = DiscordSection:Tab({
    Title = "Discord Webhook",
    Icon = "solar:chat-bold",
    IconColor = Purple,
    Border = true,
})

DiscordTab:Input({
    Title = "Webhook URL",
    Icon = "link",
    Placeholder = "https://discord.com/api/webhooks/...",
    Value = getgenv().Config.webhookUrl,
    Callback = function(value)
        getgenv().Config.webhookUrl = value
        ConfigManager:Save(getgenv().Config)
    end,
})

DiscordTab:Space()

DiscordTab:Button({
    Title = "Test Webhook",
    Icon = "send",
    Color = Blue,
    Justify = "Center",
    Callback = function()
        if getgenv().Config.webhookUrl == "" then
            WindUI:Notify({
                Title = "✗ Error",
                Content = "Enter webhook URL first",
                Color = "Red",
            })
            return
        end
        
        local success = DiscordNotifier:Send(
            "✅ Test Notification",
            "Your webhook is working!",
            3447003
        )
        
        if success then
            WindUI:Notify({
                Title = "✓ Success",
                Content = "Webhook is working",
            })
        else
            WindUI:Notify({
                Title = "✗ Failed",
                Content = "Webhook URL invalid",
                Color = "Red",
            })
        end
    end,
})

DiscordTab:Space()

DiscordTab:Toggle({
    Title = "Notify on Hop",
    Value = getgenv().Config.notifyOnHop,
    Callback = function(value)
        getgenv().Config.notifyOnHop = value
        ConfigManager:Save(getgenv().Config)
    end,
})

DiscordTab:Space()

DiscordTab:Toggle({
    Title = "Notify on Server Found",
    Value = getgenv().Config.notifyOnServerFound,
    Callback = function(value)
        getgenv().Config.notifyOnServerFound = value
        ConfigManager:Save(getgenv().Config)
    end,
})

DiscordTab:Space()

DiscordTab:Toggle({
    Title = "Notify on Errors",
    Value = getgenv().Config.notifyErrors,
    Callback = function(value)
        getgenv().Config.notifyErrors = value
        ConfigManager:Save(getgenv().Config)
    end,
})

-- ======================== STATS TAB ========================
local StatsTab = StatsSection:Tab({
    Title = "Server Stats",
    Icon = "solar:chart-bold",
    IconColor = Green,
    Border = true,
})

local playerLabel = StatsTab:Paragraph({
    Title = "Players in Server",
    Desc = tostring(#Players:GetPlayers()),
    TextSize = 16,
})

local pingLabel = StatsTab:Paragraph({
    Title = "Ping",
    Desc = "0ms",
    TextSize = 16,
})

local hopsLabel = StatsTab:Paragraph({
    Title = "Total Hops",
    Desc = tostring(ServerHopper.hopCount),
    TextSize = 16,
})

local jobIdLabel = StatsTab:Paragraph({
    Title = "Current Job ID",
    Desc = game.JobId,
    TextSize = 14,
})

-- Update stats
RunService.Heartbeat:Connect(function()
    local playerCount = #Players:GetPlayers()
    local ping = 0
    
    pcall(function()
        ping = math.floor(game:GetService("Stats").Network:FindFirstChild("ClientReplicator"):GetNetworkReceiveData()[3])
    end)
    
    playerLabel:Set({
        Title = "Players in Server",
        Desc = tostring(playerCount),
    })
    
    pingLabel:Set({
        Title = "Ping",
        Desc = ping .. "ms",
    })
    
    hopsLabel:Set({
        Title = "Total Hops",
        Desc = tostring(ServerHopper.hopCount),
    })
end)

-- ======================== SETTINGS TAB ========================
local SettingsTab = SettingsSection:Tab({
    Title = "Configuration",
    Icon = "solar:settings-bold",
    IconColor = Yellow,
    Border = true,
})

SettingsTab:Button({
    Title = "Save Config",
    Icon = "save",
    Color = Green,
    Justify = "Center",
    Callback = function()
        ConfigManager:Save(getgenv().Config)
        WindUI:Notify({
            Title = "✓ Saved",
            Content = "Configuration saved",
        })
    end,
})

SettingsTab:Space()

SettingsTab:Button({
    Title = "Load Config",
    Icon = "download",
    Color = Blue,
    Justify = "Center",
    Callback = function()
        getgenv().Config = ConfigManager:Load()
        WindUI:Notify({
            Title = "✓ Loaded",
            Content = "Configuration loaded",
        })
    end,
})

SettingsTab:Space()

SettingsTab:Button({
    Title = "Reset Config",
    Icon = "refresh-cw",
    Color = Red,
    Justify = "Center",
    Callback = function()
        getgenv().Config = ConfigManager.DefaultConfig
        ConfigManager:Save(getgenv().Config)
        WindUI:Notify({
            Title = "✓ Reset",
            Content = "Configuration reset",
        })
    end,
})

print("[✓] Server Hopper loaded!")
WindUI:Notify({
    Title = "Server Hopper v1.0",
    Content = "Ready to hop!",
})
