local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ======================== LOAD WINDUI ========================
local WindUI
do
    local ok, result = pcall(function()
        return require("./src/Init")
    end)

    if ok then
        WindUI = result
    else
        if game:GetService("RunService"):IsStudio() then
            WindUI = require(game:GetService("ReplicatedStorage"):WaitForChild("WindUI"):WaitForChild("Init"))
        else
            WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
        end
    end
end

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
    
    local success, response = pcall(function()
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
                    fps = server.fps
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
                "Moved to new server with fewer players\nServer ID: `" .. serverId .. "`\nTotal Hops: " .. self.hopCount,
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
    
    self.connection = game:GetService("RunService").Heartbeat:Connect(function()
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
                        "Found server with **" .. bestServer.players .. "** players\n(Threshold: " .. getgenv().Config.maxPlayersThreshold .. ")",
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

-- ======================== CREATE WINDUI WINDOW ========================
local Window = WindUI:CreateWindow({
    Title = "🚀 Server Hopper | WindUI",
    Folder = "ServerHopper",
    Icon = "solar:rocket-bold",
    HideSearchBar = false,
    OpenButton = {
        Title = "Server Hopper",
        CornerRadius = UDim.new(1, 0),
        StrokeThickness = 2,
        Enabled = true,
        Draggable = true,
        Scale = 1,
        Color = ColorSequence.new(
            Color3.fromHex("#30FF6A"),
            Color3.fromHex("#00D4FF")
        ),
    },
})

-- Colors
local Green = Color3.fromHex("#10C550")
local Red = Color3.fromHex("#EF4F1D")
local Blue = Color3.fromHex("#257AF7")
local Yellow = Color3.fromHex("#ECA201")
local Purple = Color3.fromHex("#7775F2")

-- ======================== HOPPER TAB ========================
local HopperTab = Window:Tab({
    Title = "Hopper",
    Icon = "solar:rocket-bold",
    IconColor = Blue,
})

local HopperSection = HopperTab:Section({
    Title = "Auto Hopping Settings",
})

local autoHopToggle = HopperSection:Toggle({
    Title = "Enable Auto Hop",
    Icon = "solar:toggle-on-bold",
    Value = getgenv().Config.autoHopEnabled,
    Callback = function(value)
        getgenv().Config.autoHopEnabled = value
        ConfigManager:Save(getgenv().Config)
        
        if value then
            ServerHopper:StartAutoHopping()
            WindUI:Notify({
                Title = "Auto Hop Started",
                Content = "Searching for empty servers...",
                Icon = "rocket",
            })
        else
            ServerHopper:StopAutoHopping()
            WindUI:Notify({
                Title = "Auto Hop Stopped",
                Content = "Stopped searching for servers",
                Icon = "stop-circle",
            })
        end
    end,
})

HopperSection:Space()

HopperSection:Slider({
    Title = "Max Players Threshold",
    Icon = "users",
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

HopperSection:Space()

HopperSection:Slider({
    Title = "Search Interval (Seconds)",
    Icon = "clock",
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

local ActionSection = HopperTab:Section({
    Title = "Quick Actions",
})

ActionSection:Button({
    Title = "Hop Now",
    Icon = "rocket",
    Color = Blue,
    Justify = "Center",
    Callback = function()
        WindUI:Notify({
            Title = "Searching...",
            Content = "Looking for empty servers",
            Icon = "loader",
        })
        
        task.spawn(function()
            local bestServer = ServerHopper:FindBestServer()
            if bestServer then
                WindUI:Notify({
                    Title = "Server Found!",
                    Content = "Players: " .. bestServer.players .. "/" .. bestServer.maxPlayers,
                    Icon = "check",
                })
                ServerHopper:HopToServer(bestServer.id)
            else
                WindUI:Notify({
                    Title = "No Servers Found",
                    Content = "No suitable servers available",
                    Icon = "x",
                    Color = "Red",
                })
            end
        end)
    end,
})

ActionSection:Space()

ActionSection:Button({
    Title = "Reset Statistics",
    Icon = "refresh-cw",
    Color = Yellow,
    Justify = "Center",
    Callback = function()
        ServerHopper.hopCount = 0
        ServerHopper.lastHopTime = 0
        WindUI:Notify({
            Title = "Statistics Reset",
            Content = "All counters have been reset",
            Icon = "check",
        })
    end,
})

-- ======================== DISCORD TAB ========================
local DiscordTab = Window:Tab({
    Title = "Discord",
    Icon = "solar:chat-bold",
    IconColor = Purple,
})

local WebhookSection = DiscordTab:Section({
    Title = "Discord Webhook",
})

local webhookInput = WebhookSection:Input({
    Title = "Webhook URL",
    Icon = "link",
    Placeholder = "https://discord.com/api/webhooks/...",
    Default = getgenv().Config.webhookUrl,
    Callback = function(value)
        getgenv().Config.webhookUrl = value
        ConfigManager:Save(getgenv().Config)
    end,
})

WebhookSection:Space()

WebhookSection:Button({
    Title = "Test Webhook",
    Icon = "send",
    Color = Blue,
    Justify = "Center",
    Callback = function()
        if getgenv().Config.webhookUrl == "" then
            WindUI:Notify({
                Title = "Error",
                Content = "Please enter a webhook URL first",
                Icon = "x",
                Color = "Red",
            })
            return
        end
        
        WindUI:Notify({
            Title = "Testing...",
            Content = "Sending test notification",
            Icon = "loader",
        })
        
        task.spawn(function()
            local success = DiscordNotifier:Send(
                "✅ Test Notification",
                "Your webhook is configured correctly!",
                3447003
            )
            
            if success then
                WindUI:Notify({
                    Title = "Success!",
                    Content = "Webhook is working properly",
                    Icon = "check",
                })
            else
                WindUI:Notify({
                    Title = "Failed",
                    Content = "Webhook URL is invalid",
                    Icon = "x",
                    Color = "Red",
                })
            end
        end)
    end,
})

DiscordTab:Space()

local NotifySection = DiscordTab:Section({
    Title = "Notification Settings",
})

NotifySection:Toggle({
    Title = "Notify on Hop",
    Icon = "bell",
    Value = getgenv().Config.notifyOnHop,
    Callback = function(value)
        getgenv().Config.notifyOnHop = value
        ConfigManager:Save(getgenv().Config)
    end,
})

NotifySection:Space()

NotifySection:Toggle({
    Title = "Notify on Server Found",
    Icon = "target",
    Value = getgenv().Config.notifyOnServerFound,
    Callback = function(value)
        getgenv().Config.notifyOnServerFound = value
        ConfigManager:Save(getgenv().Config)
    end,
})

NotifySection:Space()

NotifySection:Toggle({
    Title = "Notify on Errors",
    Icon = "alert-circle",
    Value = getgenv().Config.notifyErrors,
    Callback = function(value)
        getgenv().Config.notifyErrors = value
        ConfigManager:Save(getgenv().Config)
    end,
})

-- ======================== STATISTICS TAB ========================
local StatsTab = Window:Tab({
    Title = "Statistics",
    Icon = "solar:chart-bold",
    IconColor = Green,
})

local StatsSection = StatsTab:Section({
    Title = "Server Information",
})

local playerCountLabel = StatsTab:Paragraph({
    Title = "Players In Server",
    Desc = "Loading...",
    TextSize = 16,
})

local pingLabel = StatsTab:Paragraph({
    Title = "Ping",
    Desc = "Loading...",
    TextSize = 16,
})

local serversCheckedLabel = StatsTab:Paragraph({
    Title = "Servers Checked",
    Desc = "0",
    TextSize = 16,
})

StatsTab:Space()

local HopsSection = StatsTab:Section({
    Title = "Hopping Statistics",
})

local hopCountLabel = HopsSection:Paragraph({
    Title = "Total Hops",
    Desc = tostring(ServerHopper.hopCount),
    TextSize = 16,
})

local jobIdLabel = HopsSection:Paragraph({
    Title = "Current Job ID",
    Desc = game.JobId,
    TextSize = 14,
})

-- Update stats in real-time
RunService.Heartbeat:Connect(function()
    local playerCount = #Players:GetPlayers()
    local ping = 0
    
    pcall(function()
        ping = math.floor(game:GetService("Stats").Network:FindFirstChild("ClientReplicator"):GetNetworkReceiveData()[3])
    end)
    
    playerCountLabel:Set({
        Title = "Players In Server",
        Desc = tostring(playerCount) .. " / 50",
        TextSize = 16,
    })
    
    pingLabel:Set({
        Title = "Ping",
        Desc = ping .. "ms",
        TextSize = 16,
    })
    
    serversCheckedLabel:Set({
        Title = "Servers Checked",
        Desc = tostring(ServerHopper.totalServersChecked),
        TextSize = 16,
    })
    
    hopCountLabel:Set({
        Title = "Total Hops",
        Desc = tostring(ServerHopper.hopCount),
        TextSize = 16,
    })
end)

-- ======================== SETTINGS TAB ========================
local SettingsTab = Window:Tab({
    Title = "Settings",
    Icon = "solar:settings-bold",
    IconColor = Yellow,
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
        WindUI:Notify({
            Title = "Saved",
            Content = "Configuration saved successfully",
            Icon = "check",
        })
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
        WindUI:Notify({
            Title = "Loaded",
            Content = "Configuration loaded successfully",
            Icon = "check",
        })
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
        WindUI:Notify({
            Title = "Reset",
            Content = "Configuration reset to defaults",
            Icon = "check",
        })
    end,
})

SettingsTab:Space()

local InfoSection = SettingsTab:Section({
    Title = "About",
})

InfoSection:Paragraph({
    Title = "Server Hopper v1.0",
    Desc = "Advanced server hopping with Discord notifications\n\nFeatures:\n• Auto hop to empty servers\n• Discord webhook integration\n• Real-time statistics\n• Configuration saving",
    TextSize = 14,
    Image = "solar:rocket-bold",
})

-- ======================== FINAL ========================
print("[✓] Server Hopper with WindUI loaded successfully!")
print("[ℹ] Configuration auto-saves")
print("[ℹ] Use the UI to configure hopping and Discord webhooks")

WindUI:Notify({
    Title = "Server Hopper Loaded",
    Content = "Ready to hop servers!",
    Icon = "rocket",
})
