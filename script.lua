elseif isHoopz then
    local TweenService = game:GetService("TweenService")
    local HttpService  = game:GetService("HttpService")
    local DeviceEvent  = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("deviceEvent")

    local Settings = {
        Shooting = {
            AuralEnabled = false, AuralKeybind = Enum.KeyCode.X,
            AimMode = "Silent", CamlockStrength = 1,
            ShotYAxis = 0, ShotDelay = 0.32, EBLHop = false,
            HumanizeAim = false, HumanizeStrength = 1.2, MissChance = 0,
            RandomizeShotDelay = false, ShotDelayMin = 0.25, ShotDelayMax = 0.38,
        },
        Defending = {
            AutoGuard = false, AutoGuardButton = false, AutoGuardNearest = false,
            AutoGuardMode = "Balanced", AutoGuardRange = 33, GuardPrediction = 0.58,
            GuardKeybind = Enum.KeyCode.K,
        },
        Ball = {
            BallMags = false, BallMagRange = 15, BallMagVisualizer = false, MagnetKeybind = "M",
            BallReach = false, BallReachRange = 10, BallReachVisualizer = false, ReachKeybind = "N",
        },
        MagV2 = { Enabled = false, BallName = "Ball", Reach = 20, Keybind = Enum.KeyCode.U },
        TPWalk = { Enabled = false, Speed = 0.01, Keybind = Enum.KeyCode.P },
        HVH = {
            HipHeight = { Enabled = false, Value = 0, Default = 0 },
            Swim = { Enabled = false, Power = 1 },
            Speed = { Enabled = false, Mult = 1.35, Keybind = Enum.KeyCode.RightShift },
            InfiniteJump = { Enabled = false, Power = 1 },
        },
        Misc = { AntiModerator = false, DeviceSpoofer = false, Device = "PC", MobilePanel = true },
        Visuals = {
            ShotIndicator = false, IndicatorColor = "Purple", IndicatorStyle = "Above head",
            CustomName = false, CustomNameText = "",
            CustomRecord = false, CustomRecordText = "",
            CustomTitle = false, CustomTitleText = "",
            HideOwnNameplate = false,
        },
        Goal = { Enabled = false, SelectedEffect = "LightRay", CurrentEffect = "LightRay" },
        CourtSpoofer = { Enabled = false, SelectedCourt = "None", CurrentCourt = "None" },
        BallChanger = { Enabled = false, SelectedBall = "ForceField", CurrentBall = "ForceField" },
        TrailSpoofer = { Enabled = false, SelectedTrail = "None", CurrentTrail = "None" },
        BallAura = { Enabled = false, SelectedAura = "None", CurrentAura = "None" },
        BodyAura = { Enabled = false, Selected = "" },
        RankChanger = { Enabled = false, Selected = "" },
    }
    local s = Settings
    HVH.cfg = s.HVH

    local Cleanup = { conns = {}, fns = {} }
    local function Track(c) table.insert(Cleanup.conns, c); return c end
    local function OnCleanup(fn) table.insert(Cleanup.fns, fn) end

    local setAural, setGuard, setMagnet, setReach, setTPWalk, setMagV2
    local MobileRefresh = function() end
    local SyncToggles = function() end -- filled in once the menu exists

    local IndicatorColors = {
        Blue = Color3.fromRGB(60, 150, 255),
        Purple = Color3.fromRGB(150, 80, 220),
        Green = Color3.fromRGB(0, 255, 128),
        Red = Color3.fromRGB(255, 60, 60),
        Yellow = Color3.fromRGB(255, 220, 0),
    }

    local function hasball(char) return char and char:FindFirstChild("Basketball") ~= nil end

    local fieldGoals = {}
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst.Name == "FieldGoal" and inst:IsA("BasePart") then
            table.insert(fieldGoals, inst)
        end
    end

    local goals = {}
    local goalsDirty = true

    local function validgoal(o)
        if not o:IsA("BasePart") then return false end
        local n = string.lower(o.Name)
        if n ~= "goal" and n ~= "goalhome" and n ~= "goalaway" then return false end
        local p = o.Parent
        for _ = 1, 5 do
            if not p then break end
            local pn = string.lower(p.Name)
            if string.find(pn, "hitbox", 1, true) or string.find(pn, "fieldgoal", 1, true) then return true end
            p = p.Parent
        end
        return false
    end

    local function rebuildGoals()
        table.clear(goals)
        for _, o in workspace:GetDescendants() do
            if validgoal(o) then table.insert(goals, o) end
        end
        goalsDirty = false
    end
    rebuildGoals()

    Track(workspace.DescendantAdded:Connect(function(o)
        if validgoal(o) then
            table.insert(goals, o)
        elseif o:IsA("BasePart") and string.find(string.lower(o.Name), "goal", 1, true) then
            goalsDirty = true
        end
    end))

    local courtPlayerCache = {}
    local function rebuildCourtCache()
        table.clear(courtPlayerCache)
        for _, inst in next, workspace:GetChildren() do
            if inst.Name == "Courts" then
                for _, court in next, inst:GetChildren() do
                    local cp = court:FindFirstChild("_CourtPlayers")
                    if cp then table.insert(courtPlayerCache, cp) end
                end
            end
        end
    end
    rebuildCourtCache()

    Track(workspace.DescendantAdded:Connect(function(o)
        if o.Name == "_CourtPlayers" then
            table.insert(courtPlayerCache, o)
        end
    end))

    local function nearestgoal(root)
        if goalsDirty then rebuildGoals() end
        local rootPos = root.Position
        local best, bestDist = nil, math.huge
        for i = #goals, 1, -1 do
            local goal = goals[i]
            if not goal or not goal.Parent then table.remove(goals, i); continue end
            local delta = goal.Position - rootPos
            local flat = delta.X * delta.X + delta.Z * delta.Z
            if flat < bestDist then best, bestDist = goal, flat end
        end
        if best then return best, math.sqrt(bestDist) end
        return nil, math.huge
    end

    local function teamOf(nm)
        if nm:find("^Home") then return "Home" end
        if nm:find("^Away") then return "Away" end
        return nil
    end

    local function getTeammates()
        local tms = {}
        for _, cp in next, courtPlayerCache do
            if not cp.Parent then continue end
            local myTeam = nil
            for _, v in next, cp:GetChildren() do
                if v:IsA("ObjectValue") and v.Value == LocalPlayer then
                    myTeam = teamOf(v.Name)
                    break
                end
            end
            if not myTeam then continue end
            for _, tm in next, cp:GetChildren() do
                if tm:IsA("ObjectValue") and typeof(tm.Value) == "Instance"
                    and tm.Value:IsA("Player") and tm.Value ~= LocalPlayer
                    and teamOf(tm.Name) == myTeam then
                    table.insert(tms, tm.Value)
                end
            end
            break
        end
        return tms
    end

    local teammatesCache = { list = nil }
    local lastTeammateRefresh = 0

    local function isTeammatePlayer(player)
        local now = os.clock()
        if now - lastTeammateRefresh > 0.5 or not teammatesCache.list then
            teammatesCache.list = getTeammates()
            lastTeammateRefresh = now
        end
        for _, tm in ipairs(teammatesCache.list) do
            if tm == player then return true end
        end
        return false
    end

    local function getClosestDribbler()
        local char, _, root = getChar()
        if not root then return nil end
        local closestPlayer, closestDistance = nil, math.huge
        for _, part in workspace:GetPartBoundsInRadius(root.Position, s.Defending.AutoGuardRange) do
            if part:IsA("BasePart") and part.Name == "Ball" and part.Parent:IsA("Folder") then
                local holder = part.Parent.Parent
                local holderRoot = holder and holder:FindFirstChild("HumanoidRootPart")
                if holderRoot then
                    local distance = (holderRoot.Position - root.Position).Magnitude
                    if distance < closestDistance then
                        local holderPlayer = Players:GetPlayerFromCharacter(holder)
                        if holderPlayer and not isTeammatePlayer(holderPlayer) then
                            closestDistance = distance
                            closestPlayer = holderPlayer
                        end
                    end
                end
            end
        end
        return closestPlayer
    end

    local function getClosestPlayer()
        local char, _, root = getChar()
        if not root then return nil end
        local closestPlayer, closestDistance = nil, math.huge
        local rootPos = root.Position
        local range = s.Defending.AutoGuardRange
        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            local c = player.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (hrp.Position - rootPos).Magnitude
                if dist < range and dist < closestDistance and not isTeammatePlayer(player) then
                    closestDistance = dist
                    closestPlayer = player
                end
            end
        end
        return closestPlayer
    end

    local function getGuardMode()
        local lowered = tostring(s.Defending.AutoGuardMode or "Balanced"):lower()
        if lowered == "reactive" then return "legit" end
        if lowered == "aggressive" then return "blatant" end
        return "prediction"
    end

    local function getGuardPosition(target)
        if not target then return nil end
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Basketball") then return nil end
        local targetChar = target.Character
        if not targetChar then return nil end
        local targetBall = targetChar:FindFirstChild("Basketball") and targetChar.Basketball:FindFirstChild("Ball")
        if not targetBall then return nil end
        local targetHrp = targetChar:FindFirstChild("HumanoidRootPart")
        local targetHum = targetChar:FindFirstChild("Humanoid")
        local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local myHum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if not targetHrp or not targetHum or not myHrp or not myHum then return nil end
        local mode = getGuardMode()
        local ballPos = targetBall.Position
        local vel = targetHrp.AssemblyLinearVelocity
        local speed = targetHum.WalkSpeed
        local moveDir = targetHum.MoveDirection
        local myPos = myHrp.Position
        local mySpeed = myHum.WalkSpeed
        local distance = (ballPos - myPos).Magnitude
        local timeToReach = distance / (mySpeed + 10)
        local predictionScale = s.Defending.GuardPrediction or 0.58
        if mode == "legit" then
            predictionScale = predictionScale * 0.7
            timeToReach = distance / (mySpeed + 12)
        elseif mode == "blatant" then
            predictionScale = predictionScale * 1.75
            timeToReach = distance / (mySpeed + 18)
        end
        local predictedMove = moveDir * speed * predictionScale + Vector3.new(vel.X, 0, vel.Z) * 0.5
        local interceptPos = targetHrp.Position + predictedMove * timeToReach
        local offsetDir = (moveDir.Magnitude > 0 and moveDir.Unit or Vector3.new(0, 0, 1)) * ((mode == "blatant") and 4 or 2)
        return Vector3.new(interceptPos.X + offsetDir.X, ballPos.Y, interceptPos.Z + offsetDir.Z)
    end

    local function getNearestGuardPosition(target)
        if not target then return nil end
        local targetChar = target.Character
        local targetHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
        local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not targetHrp or not targetHum or not myHrp then return nil end
        local moveDir = targetHum.MoveDirection
        local vel = Vector3.new(targetHrp.AssemblyLinearVelocity.X, 0, targetHrp.AssemblyLinearVelocity.Z)
        local dist = (targetHrp.Position - myHrp.Position).Magnitude
        local timeToReach = dist / (targetHum.WalkSpeed + 10)
        local predictionScale = (getGuardMode() == "blatant") and (s.Defending.GuardPrediction * 1.5) or s.Defending.GuardPrediction
        local predicted = targetHrp.Position + (moveDir * targetHum.WalkSpeed * predictionScale + vel * 0.5) * timeToReach
        local facing = (moveDir.Magnitude > 0) and moveDir.Unit or (targetHrp.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
        local offset = facing * ((getGuardMode() == "blatant") and 4 or 2)
        return Vector3.new(predicted.X + offset.X, targetHrp.Position.Y, predicted.Z + offset.Z)
    end

    local guardConnection = nil

    local function enableAutoGuard()
        if guardConnection then guardConnection:Disconnect(); guardConnection = nil end
        local frameSkip = 0
        guardConnection = RunService.Stepped:Connect(function()
            if not s.Defending.AutoGuard then return end
            frameSkip += 1
            if frameSkip < 3 then return end
            frameSkip = 0
            local char, myHum = getChar()
            if not myHum or hasball(char) then return end
            local mode = getGuardMode()
            local closestDribbler = getClosestDribbler()
            if closestDribbler then
                local guardPos
                if mode == "legit" then
                    guardPos = getNearestGuardPosition(closestDribbler)
                elseif mode == "blatant" then
                    guardPos = getGuardPosition(closestDribbler)
                    if guardPos and closestDribbler.Character and closestDribbler.Character:FindFirstChild("HumanoidRootPart") then
                        local targetRoot = closestDribbler.Character.HumanoidRootPart
                        local myRoot = char:FindFirstChild("HumanoidRootPart")
                        if myRoot and (targetRoot.Position - myRoot.Position).Magnitude < 18 then
                            guardPos = targetRoot.Position + (targetRoot.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit * 3
                        end
                    end
                else
                    guardPos = getGuardPosition(closestDribbler)
                end
                if guardPos then myHum:MoveTo(guardPos) end
                return
            end
            if s.Defending.AutoGuardNearest then
                local nearest = getClosestPlayer()
                if nearest then
                    local guardPos
                    if mode == "legit" then
                        guardPos = getNearestGuardPosition(nearest)
                    elseif mode == "blatant" then
                        guardPos = getNearestGuardPosition(nearest)
                        if guardPos then
                            local myRoot = char:FindFirstChild("HumanoidRootPart")
                            if myRoot then
                                local targetRoot = nearest.Character and nearest.Character:FindFirstChild("HumanoidRootPart")
                                if targetRoot and (targetRoot.Position - myRoot.Position).Magnitude < 20 then
                                    guardPos = targetRoot.Position + targetRoot.CFrame.LookVector * 4
                                end
                            end
                        end
                    else
                        guardPos = getNearestGuardPosition(nearest)
                    end
                end
            end
        end)
    end
    Track(guardConnection)

    local function disableAutoGuard()
        if guardConnection then guardConnection:Disconnect(); guardConnection = nil end
    end

    local magnetHitbox, magnetConnection = nil, nil

    local function createMagnetHitbox(character)
        if magnetHitbox then magnetHitbox:Destroy(); magnetHitbox = nil end
        if character:FindFirstChild("RiftMagnet") then character.RiftMagnet:Destroy() end
        local head = character:FindFirstChild("Head")
        if not head then return end
        magnetHitbox = Instance.new("Part")
        magnetHitbox.Name = "RiftMagnet"
        magnetHitbox.Shape = Enum.PartType.Ball
        magnetHitbox.Size = Vector3.new(s.Ball.BallMagRange, s.Ball.BallMagRange, s.Ball.BallMagRange)
        magnetHitbox.Transparency = 1
        magnetHitbox.CanCollide = false
        magnetHitbox.CanQuery = false
        magnetHitbox.Massless = true
        magnetHitbox.Parent = character
        local weld = Instance.new("Weld")
        weld.Part0 = head
        weld.Part1 = magnetHitbox
        weld.Parent = magnetHitbox
        local magnetBox = Instance.new("SelectionSphere")
        magnetBox.Name = "RiftMagnetBox"
        magnetBox.Adornee = magnetHitbox
        magnetBox.Color3 = Color3.fromRGB(242, 140, 62)
        magnetBox.Transparency = s.Ball.BallMagVisualizer and 0.2 or 1
        magnetBox.SurfaceTransparency = 1
        magnetBox.Parent = magnetHitbox
        magnetHitbox.Touched:Connect(function(part)
            if not s.Ball.BallMags or hasball(LocalPlayer.Character) then return end
            if part.Name == "Ball" or (part.Parent and part.Parent.Name == "Basketball") then
                firetouchinterest(head, part, 0)
                task.wait()
                firetouchinterest(head, part, 1)
            end
        end)
    end

    local function enableMagnet()
        local char = LocalPlayer.Character
        if not char then return end
        createMagnetHitbox(char)
        if magnetConnection then magnetConnection:Disconnect(); magnetConnection = nil end
        magnetConnection = RunService.Heartbeat:Connect(function()
            if not s.Ball.BallMags then return end
            local character = LocalPlayer.Character
            if character and not character:FindFirstChild("RiftMagnet") then
                createMagnetHitbox(character)
            end
        end)
        Track(magnetConnection)
    end

    local function disableMagnet()
        if magnetConnection then magnetConnection:Disconnect(); magnetConnection = nil end
        if magnetHitbox then magnetHitbox:Destroy(); magnetHitbox = nil end
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("RiftMagnet") then
            LocalPlayer.Character.RiftMagnet:Destroy()
        end
    end

    local reachVisualizer, reachConnection = nil, nil

    local function removeReachVisualizer()
        if reachVisualizer then reachVisualizer:Destroy(); reachVisualizer = nil end
    end

    local function performReachSteal()
        if not s.Ball.BallReach then return end
        local char = LocalPlayer.Character
        if not char or char:FindFirstChild("Basketball") then return end
        local head = char:FindFirstChild("Head")
        if not head then return end
        local range = s.Ball.BallReachRange or 10
        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            local pChar = player.Character
            if pChar then
                local basketball = pChar:FindFirstChild("Basketball")
                if basketball then
                    local ballPart = basketball:FindFirstChild("Ball") or basketball:FindFirstChildOfClass("BasePart")
                    if ballPart and (head.Position - ballPart.Position).Magnitude <= range then
                        firetouchinterest(head, ballPart, 0)
                        task.wait()
                        firetouchinterest(head, ballPart, 1)
                        return
                    end
                end
            end
        end
    end

    local function updateReachVisualizer()
        if not s.Ball.BallReachVisualizer then removeReachVisualizer(); return end
        local closest, closestDist = nil, math.huge
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if myRoot then
            for _, p in ipairs(Players:GetPlayers()) do
                if p == LocalPlayer then continue end
                local c = p.Character
                local b = c and c:FindFirstChild("Basketball")
                local r = c and c:FindFirstChild("HumanoidRootPart")
                if b and r then
                    local d = (myRoot.Position - r.Position).Magnitude
                    if d < closestDist then closestDist = d; closest = p end
                end
            end
        end
        local ballPart = nil
        if closest and closest.Character then
            local oppBall = closest.Character:FindFirstChild("Basketball")
            if oppBall then ballPart = oppBall:FindFirstChild("Ball") end
        end
        if not ballPart then removeReachVisualizer(); return end
        local range = s.Ball.BallReachRange or 10
        if not reachVisualizer or not reachVisualizer.Parent then
            reachVisualizer = Instance.new("Part")
            reachVisualizer.Name = "ReachBallVisualizer"
            reachVisualizer.Shape = Enum.PartType.Ball
            reachVisualizer.Size = Vector3.new(range, range, range)
            reachVisualizer.Transparency = 1
            reachVisualizer.CanCollide = false
            reachVisualizer.CanTouch = false
            reachVisualizer.CanQuery = false
            reachVisualizer.CastShadow = false
            reachVisualizer.Massless = true
            reachVisualizer.Anchored = true
            reachVisualizer.Color = Color3.fromRGB(242, 140, 62)
            reachVisualizer.Parent = workspace
            local sphereBox = Instance.new("SelectionSphere")
            sphereBox.Name = "RiftReachSphere"
            sphereBox.Adornee = reachVisualizer
            sphereBox.Transparency = 0.75
            sphereBox.SurfaceTransparency = 1
            sphereBox.Color3 = Color3.fromRGB(242, 140, 62)
            sphereBox.Parent = reachVisualizer
        end
        reachVisualizer.Size = Vector3.new(range, range, range)
        reachVisualizer.CFrame = ballPart.CFrame
    end

    local function enableReach()
        local char = LocalPlayer.Character
        if not char then return end
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("RiftReach") then
            LocalPlayer.Character.RiftReach:Destroy()
        end
        if reachConnection then reachConnection:Disconnect(); reachConnection = nil end
        reachConnection = RunService.Heartbeat:Connect(function()
            if not s.Ball.BallReach and not s.Ball.BallReachVisualizer then return end
            if s.Ball.BallReach then performReachSteal() end
            if s.Ball.BallReachVisualizer then updateReachVisualizer() else removeReachVisualizer() end
        end)
        Track(reachConnection)
    end

    local function disableReach()
        if reachConnection then reachConnection:Disconnect(); reachConnection = nil end
        removeReachVisualizer()
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("RiftReach") then
            LocalPlayer.Character.RiftReach:Destroy()
        end
    end

    local tpWalkConnection = nil

    local function enableTPWalk()
        if tpWalkConnection then tpWalkConnection:Disconnect(); tpWalkConnection = nil end
        tpWalkConnection = RunService.Heartbeat:Connect(function()
            if not s.TPWalk.Enabled then return end
            local character = LocalPlayer.Character
            if not character then return end
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if rootPart and humanoid and humanoid.MoveDirection.Magnitude > 0 then
                rootPart.CFrame = rootPart.CFrame + humanoid.MoveDirection * s.TPWalk.Speed
            end
        end)
        Track(tpWalkConnection)
    end

    local function disableTPWalk()
        if tpWalkConnection then tpWalkConnection:Disconnect(); tpWalkConnection = nil end
    end

    local magV2Connection = nil

    local function magV2Tick()
        if not s.MagV2.Enabled then return end
        local character, _, touchPart = getChar()
        if not character or not touchPart then return end
        local ballName = s.MagV2.BallName
        local reach = tonumber(s.MagV2.Reach) or 20
        for _, object in pairs(workspace:GetDescendants()) do
            if object.Name == ballName and object:IsA("BasePart") then
                if object:FindFirstChildWhichIsA("TouchTransmitter") or object:FindFirstChild("TouchInterest") then
                    if (touchPart.Position - object.Position).Magnitude <= reach then
                        firetouchinterest(touchPart, object, 0)
                        task.wait()
                        firetouchinterest(touchPart, object, 1)
                    end
                end
            end
        end
    end

    local function enableMagV2()
        if magV2Connection then magV2Connection:Disconnect(); magV2Connection = nil end
        magV2Connection = RunService.Heartbeat:Connect(function() pcall(magV2Tick) end)
        Track(magV2Connection)
    end

    local function disableMagV2()
        if magV2Connection then magV2Connection:Disconnect(); magV2Connection = nil end
    end

    local Effects = {}
    local function loadEffects()
        pcall(function()
            local folder = ReplicatedStorage.ShopItems.Effect
            for _, eff in folder:GetChildren() do
                Effects[eff.Name:gsub("Effect_", "")] = eff
            end
        end)
    end
    loadEffects()

    local goalEventHook = nil

    local function applyGoalEffect()
        if not Effects[s.Goal.CurrentEffect] then return end
        pcall(function()
            local PlayerData = require(ReplicatedStorage.Util.PlayerData)
            PlayerData.storedData["Equipping"]["Effect"] = Effects[s.Goal.CurrentEffect].Name
            PlayerData.storedData["Inventory"][Effects[s.Goal.CurrentEffect].Name] = 1
        end)
        if goalEventHook then return end
        pcall(function()
            local connections = getconnections(ReplicatedStorage.Remotes.goalEvent.OnClientEvent)
            if connections and connections[1] then
                local old
                old = hookfunction(connections[1].Function, function(Player, Court, Goal, XYZ, GoalEffect, Unknown)
                    if Player == LocalPlayer and s.Goal.Enabled then
                        GoalEffect = Effects[s.Goal.CurrentEffect].Value
                    end
                    return old(Player, Court, Goal, XYZ, GoalEffect, Unknown)
                end)
                goalEventHook = old
            end
        end)
    end

    local function resetGoalEffect()
        pcall(function()
            local PlayerData = require(ReplicatedStorage.Util.PlayerData)
            PlayerData.storedData["Equipping"]["Effect"] = Effects["LightRay"].Name
            PlayerData.storedData["Inventory"][Effects["LightRay"].Name] = 1
        end)
    end

    local function SpoofDevice()
        if not s.Misc.DeviceSpoofer then return end
        local device = s.Misc.Device
        if device == "PC" then DeviceEvent:FireServer("Desktop")
        elseif device == "Mobile" then DeviceEvent:FireServer("Mobile")
        elseif device == "Gamepad" then DeviceEvent:FireServer("Gamepad") end
    end

    local Moderators = {
        "izzran", "wistfulmikk", "Bibliogical", "aepione", "kyraizo",
        "ar1sxm", "westline60s", "Iukejdjd", "Ninja215215"
    }
    local antiModTask = nil
    local Notify

    local function startAntiMod()
        if antiModTask then return end
        antiModTask = task.spawn(function()
            local detected = {}
            while s.Misc.AntiModerator do
                task.wait(1)
                for _, moderator in next, Players:GetPlayers() do
                    if table.find(Moderators, moderator.Name) and not detected[moderator.UserId] then
                        detected[moderator.UserId] = true
                        if Notify then
                            Notify({ title = "Moderator Detected", content = moderator.Name .. " is in the server.", duration = 5 })
                        end 
                    end
                end
            end
        end)
    end

    local function stopAntiMod()
        s.Misc.AntiModerator = false
        if antiModTask then task.cancel(antiModTask); antiModTask = nil end
    end

    local Balls, BallNames = {}, {}
    local Trails, TrailNames = {}, {}
    local Auras, AuraNames = {}, {}
    local Courts, CourtNames = {}, {}
    local OriginalReplicateBall, Replicator = nil, nil
    local OriginalReplicateTrail = nil
    local OriginalReplicateAura = nil
    local OriginalReplicateCourt = nil

    pcall(function()
        Replicator = require(ReplicatedStorage.Util.Replicator)
        OriginalReplicateBall = Replicator["ReplicateBall"]
        OriginalReplicateTrail = Replicator["ReplicateTrail"]
        OriginalReplicateAura = Replicator["ReplicateAura"]
        OriginalReplicateCourt = Replicator["ReplicateCourt"]

        for _, ballItem in ReplicatedStorage.ShopItems.Ball:GetChildren() do
            local name = ballItem.Name:gsub("Ball_", "")
            Balls[name] = ballItem.Name
            table.insert(BallNames, name)
        end
        table.sort(BallNames)

        local trailFolder = ReplicatedStorage.ShopItems:FindFirstChild("Trail")
        if trailFolder then
            for _, item in trailFolder:GetChildren() do
                local name = item.Name:gsub("Trail_", "")
                Trails[name] = item.Name
                table.insert(TrailNames, name)
            end
            table.sort(TrailNames)
        end

        local auraFolder = ReplicatedStorage.ShopItems:FindFirstChild("Aura")
        if auraFolder then
            for _, item in auraFolder:GetChildren() do
                local name = item.Name:gsub("Aura_", "")
                Auras[name] = item.Name
                table.insert(AuraNames, name)
            end
            table.sort(AuraNames)
        end

        -- Court skin list: try multiple known folder names
        local function addCourtFolder(folder)
            if not folder then return end
            for _, item in folder:GetChildren() do
                local name = item.Name:gsub("^CourtSkin_", ""):gsub("^Court_", ""):gsub("^Skin_", "")
                if not Courts[name] then
                    Courts[name] = item.Name
                    table.insert(CourtNames, name)
                end
            end
        end
        local shop = ReplicatedStorage:FindFirstChild("ShopItems")
        if shop then
            addCourtFolder(shop:FindFirstChild("CourtSkin"))
            addCourtFolder(shop:FindFirstChild("Courts"))
            addCourtFolder(shop:FindFirstChild("Court"))
        end
        -- Fallback: scan any folder named Court* under ReplicatedStorage
        if #CourtNames == 0 then
            for _, inst in ReplicatedStorage:GetDescendants() do
                if inst:IsA("Folder") and inst.Name:lower():find("court", 1, true) and inst.Parent then
                    addCourtFolder(inst)
                end
            end
        end
        table.sort(CourtNames)
        if #CourtNames > 0 and (s.CourtSpoofer.SelectedCourt == "None" or s.CourtSpoofer.CurrentCourt == "None") then
            s.CourtSpoofer.SelectedCourt = CourtNames[1]
            s.CourtSpoofer.CurrentCourt = CourtNames[1]
        end
    end)

    local function ownerOfParent(parent)
        local node = parent
        for _ = 1, 6 do
            if not node then break end
            if node:IsA("Model") then
                local plr = Players:GetPlayerFromCharacter(node)
                if plr then return plr end
            end
            node = node.Parent
        end
        return nil
    end

    local function applyBallChanger()
        if not Replicator or not OriginalReplicateBall then return end
        Replicator["ReplicateBall"] = function(Parent, Name)
            if ownerOfParent(Parent) == LocalPlayer then
                local spoofed = Balls[s.BallChanger.CurrentBall]
                if spoofed then Name = spoofed end
            end
            return OriginalReplicateBall(Parent, Name)
        end
    end

    local function resetBallChanger()
        if not Replicator or not OriginalReplicateBall then return end
        Replicator["ReplicateBall"] = OriginalReplicateBall
    end

    local function applyTrailSpoofer()
        if not Replicator or not OriginalReplicateTrail then return end
        Replicator["ReplicateTrail"] = function(Parent, Name)
            if ownerOfParent(Parent) == LocalPlayer then
                local spoofed = Trails[s.TrailSpoofer.CurrentTrail]
                if spoofed then Name = spoofed end
            end
            return OriginalReplicateTrail(Parent, Name)
        end
    end

    local function resetTrailSpoofer()
        if not Replicator or not OriginalReplicateTrail then return end
        Replicator["ReplicateTrail"] = OriginalReplicateTrail
    end

    local function applyBallAura()
        if not Replicator or not OriginalReplicateAura then return end
        Replicator["ReplicateAura"] = function(Parent, Name)
            if ownerOfParent(Parent) == LocalPlayer then
                local spoofed = Auras[s.BallAura.CurrentAura]
                if spoofed then Name = spoofed end
            end
            return OriginalReplicateAura(Parent, Name)
        end
    end

    local function resetBallAura()
        if not Replicator or not OriginalReplicateAura then return end
        Replicator["ReplicateAura"] = OriginalReplicateAura
    end

    -- ============================================================
    -- COURT SKIN SPOOFER (Replicator hook + PlayerData fallback)
    -- ============================================================
    local function applyCourtSpoofer()
        local target = Courts[s.CourtSpoofer.CurrentCourt]
        if not target then
            Notify({ title = "Court Spoofer", content = "Selected court not found.", duration = 3 })
            return
        end
        if Replicator and OriginalReplicateCourt then
            Replicator["ReplicateCourt"] = function(Parent, Name)
                if ownerOfParent(Parent) == LocalPlayer then
                    local spoofed = Courts[s.CourtSpoofer.CurrentCourt]
                    if spoofed then Name = spoofed end
                end
                return OriginalReplicateCourt(Parent, Name)
            end
        end
        pcall(function()
            local PlayerData = require(ReplicatedStorage.Util.PlayerData)
            PlayerData.storedData["Equipping"]["CourtSkin"] = target
            PlayerData.storedData["Inventory"][target] = 1
        end)
        Notify({ title = "Court Spoofer", content = "Applied: " .. s.CourtSpoofer.CurrentCourt, duration = 2.5 })
    end

    local function resetCourtSpoofer()
        if Replicator and OriginalReplicateCourt then
            Replicator["ReplicateCourt"] = OriginalReplicateCourt
        end
        pcall(function()
            local PlayerData = require(ReplicatedStorage.Util.PlayerData)
            PlayerData.storedData["Equipping"]["CourtSkin"] = nil
        end)
    end

    local indicator = Instance.new("BillboardGui")
    indicator.Name = "RangeIndicator"
    indicator.Size = UDim2.fromOffset(90, 90)
    indicator.AlwaysOnTop = true
    indicator.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)

    local indicatorRing = Instance.new("ImageLabel")
    indicatorRing.Name = "Ring"
    indicatorRing.Size = UDim2.fromScale(1, 1)
    indicatorRing.BackgroundTransparency = 1
    indicatorRing.Image = "rbxassetid://3570695787"
    indicatorRing.ImageColor3 = Color3.fromRGB(242, 140, 62)
    indicatorRing.ImageTransparency = 0.15
    indicatorRing.ScaleType = Enum.ScaleType.Fit
    indicatorRing.Parent = indicator

    local indicatorDot = Instance.new("Frame")
    indicatorDot.Name = "Dot"
    indicatorDot.Size = UDim2.fromOffset(6, 6)
    indicatorDot.AnchorPoint = Vector2.new(0.5, 0.5)
    indicatorDot.Position = UDim2.fromScale(0.5, 0.5)
    indicatorDot.BackgroundColor3 = Color3.fromRGB(242, 140, 62)
    indicatorDot.BorderSizePixel = 0
    indicatorDot.Parent = indicator
    local indicatorDotCorner = Instance.new("UICorner")
    indicatorDotCorner.CornerRadius = UDim.new(1, 0)
    indicatorDotCorner.Parent = indicatorDot

    local rangeConnection = nil

    -- "Whole body" style: highlights your entire character instead of the ring above your head
    local bodyHL = Instance.new("Highlight")
    bodyHL.Name = "RiftRangeHighlight"
    bodyHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    bodyHL.FillTransparency = 0.45
    bodyHL.OutlineTransparency = 0

    local function applyIndicatorColor()
        local col = IndicatorColors[s.Visuals.IndicatorColor] or Color3.fromRGB(242, 140, 62)
        indicatorRing.ImageColor3 = col
        indicatorDot.BackgroundColor3 = col
        bodyHL.FillColor = col
        bodyHL.OutlineColor = col
    end

    local function setShotIndicator(value)
        s.Visuals.ShotIndicator = value
        if rangeConnection then rangeConnection:Disconnect(); rangeConnection = nil end
        indicator.Parent = nil
        bodyHL.Parent = nil
        if not value then return end
        local throttle = 0
        rangeConnection = RunService.Heartbeat:Connect(function(dt)
            throttle += dt
            if throttle < 0.05 then return end
            throttle = 0
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root or not hasball(character) then indicator.Parent = nil; bodyHL.Parent = nil; return end
            local goal, distance = nearestgoal(root)
            if goal and distance >= 12 and distance <= 73 then
                applyIndicatorColor()
                if s.Visuals.IndicatorStyle == "Whole body" then
                    indicator.Parent = nil
                    if bodyHL.Parent ~= character then
                        bodyHL.Adornee = character
                        bodyHL.Parent = character
                    end
                else
                    bodyHL.Parent = nil
                    if indicator.Parent ~= character then
                        indicator.Adornee = character
                        indicator.Parent = character
                    end
                end
            else
                indicator.Parent = nil
                bodyHL.Parent = nil
            end
        end)
        Track(rangeConnection)
    end

    local AURAL_MIN_DIST = 12
    local AURAL_MAX_DIST = 73

    local shot_data = {
        [59]=83,[60]=81,[61]=82,[62]=79,[63]=78.8,[64]=75,[65]=74.8,[66]=71,
        [67]=70.8,[68]=66,[69]=62,[70]=59,[71]=51,[72]=51,[73]=51
    }

    local inner_arc_data = {
        [7]=123,[8]=122,[9]=121,[10]=120,[11]=119,[12]=118,[13]=117,[14]=116,[15]=115,[16]=114,
        [17]=113,[18]=112,[19]=111,[20]=110,[21]=109,[22]=108,[23]=107,[24]=106,[25]=105,
        [26]=105,
        [27]=106,[28]=106,[29]=107,[30]=107,[31]=106,[32]=105,[33]=105,[34]=104,[35]=103,
        [36]=103,
        [37]=102,[38]=102,[39]=101,[40]=101,[41]=100,[42]=99,[43]=99,[44]=98,[45]=97,[46]=96,
        [47]=95,[48]=95,[49]=94,[50]=93,[51]=91,[52]=90,[53]=88,[54]=87,[55]=85,[56]=84,[57]=82,
        [58]=81
    }

    local mobileArcs = {
        [30]=38,[31]=38,[32]=38,[33]=38,[34]=38,[35]=38,[36]=38,[37]=38,[38]=38,[39]=38,
        [40]=39,[41]=38,[42]=38,[43]=38,[44]=38,[45]=38,[46]=38,[47]=38,[48]=38,[49]=38,
        [50]=38,[51]=37,[52]=37,[53]=37,[54]=36,[55]=34,[56]=34,[57]=34,[58]=34,[59]=31,
        [60]=31,[61]=31,[62]=31,[63]=29,[64]=29,[65]=29,[66]=26,[67]=26,[68]=24,[69]=24,
        [70]=21,[71]=21,[72]=19,[73]=19
    }

    local function getArcOffset(dist)
        if isMobile then
            local d = math.floor(dist + 0.5)
            if d < 30 then d = 30 end
            if d > 73 then d = 73 end
            return mobileArcs[d] or 37
        end
        if inner_arc_data[dist] then return inner_arc_data[dist] end
        if shot_data[dist] then return shot_data[dist] end
        if dist < 7 then return 122 end
        if dist > 73 then return math.max(20, 50 - (dist - 73) * 1.5) end
        local lower, upper
        for d in pairs(inner_arc_data) do
            if d <= dist and (not lower or d > lower) then lower = d end
            if d >= dist and (not upper or d < upper) then upper = d end
        end
        for d in pairs(shot_data) do
            if d <= dist and (not lower or d > lower) then lower = d end
            if d >= dist and (not upper or d < upper) then upper = d end
        end
        if lower and upper and lower ~= upper then
            local lowerVal = inner_arc_data[lower] or shot_data[lower] or 0
            local upperVal = inner_arc_data[upper] or shot_data[upper] or 0
            return lowerVal + (upperVal - lowerVal) * ((dist - lower) / (upper - lower))
        elseif lower then
            return inner_arc_data[lower] or shot_data[lower] or 0
        elseif upper then
            return inner_arc_data[upper] or shot_data[upper] or 0
        end
        return 100
    end

    local Icon = nil
    local IconCenter = nil
    do
        pcall(function()
            local PowerUI = LocalPlayer.PlayerGui:WaitForChild("PowerUI")
            Icon = PowerUI:WaitForChild("CursorIcon")
            local CursorIcon2 = PowerUI:WaitForChild("CursorIcon2")
            task.delay(5, function()
                if Icon then
                    IconCenter = Vector2.new(Icon.AbsolutePosition.X + Icon.AbsoluteSize.X / 2, Icon.AbsolutePosition.Y + Icon.AbsoluteSize.Y / 2)
                    Icon:Destroy()
                end
                if CursorIcon2 then CursorIcon2.Visible = false end
            end)
        end)
    end

    local state = {
        target = nil, connections = {}, actorst = nil, actorname = nil,
        actors = {}, oldnewindex = nil, active = true, clicking = false
    }
    local function addconnection(c) table.insert(state.connections, c); return c end

    local function settarget(target)
        state.target = target
        if state.actorst then pcall(function() state.actorst.t = target end) end
    end

    local function doClick()
        if state.clicking then return end
        state.clicking = true
        getgenv().__rift_aiming = true
        if isMobile then
            if Icon then
                local pos = Vector2.new(Icon.AbsolutePosition.X + Icon.AbsoluteSize.X / 2, Icon.AbsolutePosition.Y + Icon.AbsoluteSize.Y / 2)
                VirtualInput:SendTouchEvent(1, 0, pos.X, pos.Y)
                VirtualInput:SendTouchEvent(1, 2, pos.X, pos.Y)
            elseif IconCenter then
                VirtualInput:SendTouchEvent(1, 0, IconCenter.X, IconCenter.Y)
                VirtualInput:SendTouchEvent(1, 2, IconCenter.X, IconCenter.Y)
            end
        else
            local vp = Camera.ViewportSize
            VirtualInput:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, true, game, 1)
            VirtualInput:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, false, game, 1)
        end
        task.delay(0.35, function()
            state.clicking = false
            getgenv().__rift_aiming = false
        end)
    end

    local function velocify(target, dist)
        local _, _, hrp = getChar()
        if not hrp then return target end
        local v = hrp.AssemblyLinearVelocity
        local prediction = (dist / 50) * 0.06
        return target + Vector3.new(v.X * prediction, 0, v.Z * prediction)
    end

    local auralTick = 0
    local function updateAuralTarget(dt)
        if not state.active or not s.Shooting.AuralEnabled then
            if state.target ~= nil then settarget(nil) end
            return
        end
        auralTick += dt
        if auralTick < 0.05 then return end
        auralTick = 0
        local char, hum = getChar()
        if not char or not hum or not hasball(char) then
            if state.target ~= nil then settarget(nil) end
            return
        end
        if hum.FloorMaterial ~= Enum.Material.Air and not hum.Jump then
            if state.target ~= nil then settarget(nil) end
            return
        end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then settarget(nil); return end
        local goal, distance = nearestgoal(root)
        if not goal or distance < AURAL_MIN_DIST or distance > AURAL_MAX_DIST then
            if state.target ~= nil then settarget(nil) end
            return
        end
        local offset = getArcOffset(distance) + s.Shooting.ShotYAxis
        if s.Shooting.HumanizeAim then
            local strength = s.Shooting.HumanizeStrength or 1.2
            local missChance = (s.Shooting.MissChance or 12) / 100
            if math.random() < missChance then
                if math.random() < 0.5 then
                    offset += strength * 3 + math.random() * strength * 2
                else
                    offset -= strength * 3 + math.random() * strength * 2
                end
            else
                offset += (math.random() * 2 - 1) * strength
            end
        end
        settarget(velocify(goal.Position + Vector3.new(0, offset, 0), distance))
    end

    local actorcode = [==[
local registry = game:GetService("SharedTableRegistry")
local players = game:GetService("Players")
local st = registry:GetSharedTable(__riftaimtable)
local camera = workspace.CurrentCamera
local function target() local v = st.t return typeof(v) == "Vector3" and v or nil end
local function aimcframe()
    local v = target()
    local char = players.LocalPlayer.Character
    local head = char and char:FindFirstChild("Head")
    if v and head then return CFrame.new(head.Position, v) end
end
pcall(function()
    local oldrender
    oldrender = hookfunction(camera.GetRenderCFrame, function(self, ...) return aimcframe() or oldrender(self, ...) end)
    local oldscreen
    oldscreen = hookfunction(camera.ScreenPointToRay, function(self, ...)
        local v = aimcframe()
        if v then return Ray.new(v.Position, v.LookVector) end
        return oldscreen(self, ...)
    end)
    local oldviewport
    oldviewport = hookfunction(camera.ViewportPointToRay, function(self, ...)
        local v = aimcframe()
        if v then return Ray.new(v.Position, v.LookVector) end
        return oldviewport(self, ...)
    end)
    local cameradata = registry:GetSharedTable("CameraData")
    local history = cameradata.CameraHistory
    local meta = getrawmetatable(cameradata)
    local oldnewindex
    oldnewindex = hookfunction(meta.__newindex, newcclosure(function(tab, key, value)
        local current = tab == cameradata and key == "CameraCFrame"
        local previous = history ~= nil and tab == history and type(key) == "number"
        local aimed = aimcframe()
        if aimed and (current or previous) then return oldnewindex(tab, key, aimed) end
        return oldnewindex(tab, key, value)
    end))
end)
]==]

    local function hookmain()
        pcall(function()
            state.actorname = "sa" .. tostring(math.floor(os.clock() * 100000)) .. tostring(math.random(10000, 99999))
            state.actorst = SharedTableRegistry:GetSharedTable(state.actorname)
            state.actorst.t = nil
            local cameradata = SharedTableRegistry:GetSharedTable("CameraData")
            local history = cameradata.CameraHistory
            local meta = getrawmetatable(cameradata)
            state.oldnewindex = hookfunction(meta.__newindex, newcclosure(function(tab, key, value)
                local current = tab == cameradata and key == "CameraCFrame"
                local previous = history ~= nil and tab == history and type(key) == "number"
                local tgt = state.target
                if tgt and (current or previous) and typeof(value) == "CFrame" then
                    local char = LocalPlayer.Character
                    local head = char and char:FindFirstChild("Head")
                    if head then
                        return state.oldnewindex(tab, key, CFrame.new(head.Position, tgt))
                    end
                end
                return state.oldnewindex(tab, key, value)
            end))
        end)
    end

    local function hookactors()
        if type(getactors) ~= "function" or type(run_on_actor) ~= "function" or not state.actorname then return end
        local ok, actors = pcall(getactors)
        if not ok or type(actors) ~= "table" then return end
        local code = "local __riftaimtable = " .. string.format("%q", state.actorname) .. " " .. actorcode
        for _, actor in actors do
            if not state.actors[actor] then
                if pcall(run_on_actor, actor, code) then
                    state.actors[actor] = true
                end
            end
        end
    end

    hookmain()
    hookactors()

    addconnection(Players.PlayerAdded:Connect(function() task.defer(hookactors) end))
    addconnection(RunService.Heartbeat:Connect(updateAuralTarget))

    -- Camlock mode: on top of the silent aim, pull the real camera onto the aim point
    -- (the arc point above the rim) for as long as a shot is being aimed.
    pcall(function() RunService:UnbindFromRenderStep("RiftHoopzCamlock") end)
    RunService:BindToRenderStep("RiftHoopzCamlock", Enum.RenderPriority.Last.Value, function()
        if s.Shooting.AimMode ~= "Camlock" or not s.Shooting.AuralEnabled or not state.target then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        local want = CFrame.lookAt(cam.CFrame.Position, state.target)
        local k = math.clamp(s.Shooting.CamlockStrength or 1, 0.05, 1)
        cam.CFrame = (k >= 1) and want or cam.CFrame:Lerp(want, k)
    end)
    OnCleanup(function() pcall(function() RunService:UnbindFromRenderStep("RiftHoopzCamlock") end) end)

    local function setupCharacterAural(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if not hum then return end
        local jumps = 0
        addconnection(hum.Jumping:Connect(function(active)
            if not active then return end
            if not s.Shooting.AuralEnabled or not hasball(char) then return end
            if s.Shooting.EBLHop then
                jumps += 1
                if jumps < 2 then return end
                jumps = 0
            end
            local root = char:FindFirstChild("HumanoidRootPart")
            if not root then return end
            local goal, distance = nearestgoal(root)
            local minDist = isMobile and 30 or AURAL_MIN_DIST
            if not goal or distance < minDist or distance > AURAL_MAX_DIST then return end
            local arc = getArcOffset(distance) + s.Shooting.ShotYAxis
            local targetPos = nil
            if s.Shooting.HumanizeAim then
                local strength = s.Shooting.HumanizeStrength or 1.2
                local missChance = (s.Shooting.MissChance or 12) / 100
                if math.random() < missChance then
                    local mode = math.random(1, 3)
                    if mode == 1 then
                        arc += strength * 3 + math.random() * strength * 2
                    elseif mode == 2 then
                        arc -= strength * 3 + math.random() * strength * 2
                    else
                        local side = (math.random() < 0.5) and -1 or 1
                        targetPos = goal.Position
                            + Vector3.new(0, getArcOffset(distance) + s.Shooting.ShotYAxis, 0)
                            + Camera.CFrame.RightVector * (side * (strength * 2 + math.random() * 2))
                    end
                else
                    arc += (math.random() * 2 - 1) * strength
                end
            end
            targetPos = targetPos or goal.Position + Vector3.new(0, arc, 0)
            settarget(targetPos)
            task.wait(0.05)
            LocalPlayer:SetAttribute("Power", 85)
            local shotdelay = s.Shooting.ShotDelay or 0.25
            if s.Shooting.RandomizeShotDelay then
                local mn = s.Shooting.ShotDelayMin or 0.15
                local mx = s.Shooting.ShotDelayMax or 0.35
                if mx < mn then mx = mn end
                shotdelay = mn + math.random() * (mx - mn)
            end
            task.wait(shotdelay)
            doClick()
            task.wait(0.1)
            updateAuralTarget(0.1)
        end))
    end

    if LocalPlayer.Character then setupCharacterAural(LocalPlayer.Character) end
    addconnection(LocalPlayer.CharacterAdded:Connect(setupCharacterAural))

    local textListeners = {}
    local originalNameTexts, originalRecordTexts, originalTitleTexts = {}, {}, {}

    local function formatStrokeText(orig, custom)
        if not custom or custom == "" then return orig end
        if orig and orig:match("^<stroke>") and orig:match("</stroke>$") then
            return "<stroke>" .. custom .. "</stroke>"
        end
        return custom
    end

    local function applyOwnNameplate()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local nameTag = hrp:FindFirstChild("NameTag")
        if not nameTag or not nameTag:IsA("BillboardGui") then return end
        for _, tagName in ipairs({"NameTag", "CreatorTag", "TeamSpot"}) do
            local tag = hrp:FindFirstChild(tagName)
            if tag and tag:IsA("BillboardGui") then
                tag.Enabled = not s.Visuals.HideOwnNameplate
            end
        end
        local mainFrame = nameTag:FindFirstChild("MainFrame")
        local gameFrame = nameTag:FindFirstChild("GameFrame")
        local subFrame = mainFrame and mainFrame:FindFirstChild("Frame")
        local nameLabels = {}
        if mainFrame and mainFrame:FindFirstChild("NameLabel") then table.insert(nameLabels, mainFrame.NameLabel) end
        if gameFrame and gameFrame:FindFirstChild("NameLabel") then table.insert(nameLabels, gameFrame.NameLabel) end
        for _, obj in ipairs(nameTag:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Name == "NameLabel" and not table.find(nameLabels, obj) then
                table.insert(nameLabels, obj)
            end
        end
        for _, obj in ipairs(nameLabels) do
            if not originalNameTexts[obj] then originalNameTexts[obj] = obj.Text end
            local target = (s.Visuals.CustomNameText ~= "") and s.Visuals.CustomNameText or originalNameTexts[obj]
            if obj.Text ~= target then obj.Text = target end
            if not textListeners[obj] then
                textListeners[obj] = obj:GetPropertyChangedSignal("Text"):Connect(function()
                    if s.Visuals.CustomNameText ~= "" and obj.Text ~= s.Visuals.CustomNameText then
                        obj.Text = s.Visuals.CustomNameText
                    end
                end)
            end
        end
        local recordLabels = {}
        if subFrame and subFrame:FindFirstChild("RecordLabel") then table.insert(recordLabels, subFrame.RecordLabel) end
        for _, obj in ipairs(nameTag:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Name == "RecordLabel" and not table.find(recordLabels, obj) then
                table.insert(recordLabels, obj)
            end
        end
        for _, obj in ipairs(recordLabels) do
            if not originalRecordTexts[obj] then originalRecordTexts[obj] = obj.Text end
            local target = formatStrokeText(originalRecordTexts[obj], s.Visuals.CustomRecordText)
            if obj.Text ~= target then obj.Text = target end
            if not textListeners[obj] then
                textListeners[obj] = obj:GetPropertyChangedSignal("Text"):Connect(function()
                    if s.Visuals.CustomRecordText ~= "" then
                        local expected = formatStrokeText(originalRecordTexts[obj], s.Visuals.CustomRecordText)
                        if obj.Text ~= expected then obj.Text = expected end
                    end
                end)
            end
        end
        local titleLabels = {}
        if subFrame and subFrame:FindFirstChild("AchievementName") then table.insert(titleLabels, subFrame.AchievementName) end
        for _, obj in ipairs(nameTag:GetDescendants()) do
            if obj:IsA("TextLabel") and (obj.Name == "AchievementName" or obj.Name == "TitleLabel") and not table.find(titleLabels, obj) then
                table.insert(titleLabels, obj)
            end
        end
        for _, obj in ipairs(titleLabels) do
            if not originalTitleTexts[obj] then originalTitleTexts[obj] = obj.Text end
            local target = formatStrokeText(originalTitleTexts[obj], s.Visuals.CustomTitleText)
            if obj.Text ~= target then obj.Text = target end
            if not textListeners[obj] then
                textListeners[obj] = obj:GetPropertyChangedSignal("Text"):Connect(function()
                    if s.Visuals.CustomTitleText ~= "" then
                        local expected = formatStrokeText(originalTitleTexts[obj], s.Visuals.CustomTitleText)
                        if obj.Text ~= expected then obj.Text = expected end
                    end
                end)
            end
        end
    end

    local ownNameplateConnection = nil

    local function setupOwnNameplateListener()
        if ownNameplateConnection then return end
        local function onChar(char)
            task.wait(0.2)
            applyOwnNameplate()
            local hrp = char:WaitForChild("HumanoidRootPart", 5)
            if hrp then
                hrp.ChildAdded:Connect(function(child)
                    if child:IsA("BillboardGui") then
                        task.wait(0.05)
                        applyOwnNameplate()
                    end
                end)
                local nameTag = hrp:WaitForChild("NameTag", 5)
                if nameTag then
                    nameTag.DescendantAdded:Connect(function()
                        task.wait(0.05)
                        applyOwnNameplate()
                    end)
                end
            end
        end
        if LocalPlayer.Character then task.spawn(onChar, LocalPlayer.Character) end
        ownNameplateConnection = LocalPlayer.CharacterAdded:Connect(onChar)
        Track(ownNameplateConnection)
    end
    setupOwnNameplateListener()

    -- ============================================================
    -- NAME SPOOF: the custom username also shows in chat and in the "scored" pop-up (local view only).
    -- It swaps your real name / display name for the custom one in on-screen text: your PlayerGui,
    -- the chat window, and billboard/surface text in the world. Wrapped in a function so its locals
    -- don't count against this branch's local-variable limit.
    -- ============================================================
    local NameSpoof = (function()
        local hooked    = setmetatable({}, { __mode = "k" })
        local originals = setmetatable({}, { __mode = "k" })
        local watched   = {}
        local started   = false

        local function realNames()
            local list = {}
            if LocalPlayer.Name ~= "" then table.insert(list, LocalPlayer.Name) end
            if LocalPlayer.DisplayName ~= "" and LocalPlayer.DisplayName ~= LocalPlayer.Name then
                table.insert(list, LocalPlayer.DisplayName)
            end
            return list
        end

        local function plainReplace(text, find, rep)
            local out, pos, changed = {}, 1, false
            while true do
                local i, j = string.find(text, find, pos, true)
                if not i then break end
                table.insert(out, string.sub(text, pos, i - 1))
                table.insert(out, rep)
                pos = j + 1
                changed = true
            end
            if not changed then return text, false end
            table.insert(out, string.sub(text, pos))
            return table.concat(out), true
        end

        local function process(obj)
            local custom = s.Visuals.CustomNameText
            if custom == "" or not obj.Parent then return end
            -- your own nameplate is handled by the nameplate code above
            local char = LocalPlayer.Character
            if char and obj:IsDescendantOf(char) then return end
            local text = obj.Text
            if text == "" then return end
            local new, changed = text, false
            for _, nm in ipairs(realNames()) do
                if not string.find(custom, nm, 1, true) then
                    local r, c = plainReplace(new, nm, custom)
                    if c then new, changed = r, true end
                end
            end
            if changed then
                if originals[obj] == nil then originals[obj] = text end
                obj.Text = new
            end
        end

        local function hook(obj)
            if hooked[obj] then return end
            if not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then return end
            hooked[obj] = obj:GetPropertyChangedSignal("Text"):Connect(function() process(obj) end)
            process(obj)
        end

        local function watch(root)
            if not root or watched[root] then return end
            watched[root] = true
            root.DescendantAdded:Connect(function(d) task.defer(hook, d) end)
            local n = 0
            for _, d in ipairs(root:GetDescendants()) do
                hook(d)
                n += 1
                if n % 1500 == 0 then task.wait() end
            end
        end

        local function start()
            if started then return end
            started = true
            task.spawn(function()
                local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
                watch(pg)
                pcall(function()
                    local chat = CoreGui:FindFirstChild("ExperienceChat")
                    if chat then watch(chat) end
                    CoreGui.ChildAdded:Connect(function(c)
                        if c.Name == "ExperienceChat" then watch(c) end
                    end)
                end)
                watch(workspace)
            end)
        end

        local function restore()
            for obj, orig in pairs(originals) do
                if obj.Parent and obj.Text ~= orig then pcall(function() obj.Text = orig end) end
            end
            table.clear(originals)
        end

        -- call whenever the custom username changes (or is cleared)
        local function refresh()
            restore()
            if s.Visuals.CustomNameText ~= "" then
                start()
                for obj in pairs(hooked) do process(obj) end
            end
        end

        return { refresh = refresh }
    end)()

    -- ============================================================
    -- BODY AURA CHANGER (cosmetic, client-side)
    -- ============================================================
    local baScan, baApply, baEnable, baDisable
    local BodyAuraList = {}
    do
        local BodyAura = {
            active = false,
            selected = nil,
            container = nil,
            charAddedConn = nil,
            list = {},
            lookup = {},
        }

        local function ba_hidePlastic(container)
            if not container then return end
            local hideList, hasReal = {}, false
            for _, child in pairs(container:GetDescendants()) do
                if child:IsA("BasePart") then
                    local plastic = child.Material == Enum.Material.Plastic
                    local placeholder = child.Name:lower() == "aura"
                    if plastic or placeholder then
                        table.insert(hideList, child)
                    elseif child.Transparency < 1 then
                        hasReal = true
                    end
                elseif child:IsA("ParticleEmitter") or child:IsA("Beam") or child:IsA("Trail") then
                    hasReal = true
                end
            end
            -- If everything is plastic, those parts ARE the aura, so keep them.
            if not hasReal then return end
            for _, part in ipairs(hideList) do
                part.Transparency = 1; part.CanCollide = false
            end
        end

        local function ba_cleanCharacter(char)
            if not char then return end
            local realHead = char:FindFirstChild("Head")
            for _, child in pairs(char:GetChildren()) do
                if child:IsA("Part") or child:IsA("MeshPart") then
                    if child.Name:lower():find("head") and child ~= realHead then
                        child.Transparency = 1; child.CanCollide = false
                    end
                    if child.Name:lower() == "aura" then
                        child.Transparency = 1; child.CanCollide = false
                    end
                end
            end
            local realHum = char:FindFirstChildOfClass("Humanoid")
            for _, child in pairs(char:GetChildren()) do
                if child:IsA("Humanoid") and child ~= realHum then child:Destroy() end
            end
        end

        local function ba_findRig(auraModel)
            for _, child in pairs(auraModel:GetChildren()) do
                if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then return child end
            end
            if auraModel:FindFirstChildOfClass("Humanoid") then return auraModel end
            local hum = auraModel:FindFirstChildWhichIsA("Humanoid", true)
            if hum and hum.Parent then return hum.Parent end
            return nil
        end

        local function ba_rigParts(rigModel)
            local parts = {}
            for _, name in pairs({"Head","LeftArm","RightArm","Torso","LeftLeg","RightLeg","HumanoidRootPart"}) do
                local part = rigModel:FindFirstChild(name)
                if part and part:IsA("BasePart") then parts[name] = part end
            end
            return parts
        end

        local function ba_charParts(char)
            local parts = {}
            for _, name in pairs({"Head","LeftArm","RightArm","Torso","UpperTorso","LeftLeg","RightLeg","HumanoidRootPart"}) do
                local part = char:FindFirstChild(name)
                if part and part:IsA("BasePart") then parts[name] = part end
            end
            return parts
        end

        local function ba_stripFace(part)
            if not part then return end
            for _, child in pairs(part:GetChildren()) do
                if child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceAppearance") then
                    child:Destroy()
                end
            end
            if part:FindFirstChild("face") then part.face:Destroy() end
        end

        local function ba_destroyContainer()
            BodyAura.container = nil
            local char = LocalPlayer.Character
            if char then
                local c = char:FindFirstChild("AuraVisuals")
                if c then c:Destroy() end
            end
        end

        local function ba_norm(name)
            return (name:lower():gsub("[%s_]", ""))
        end

        local function ba_isHeadish(name)
            local n = name:lower()
            return n:find("head") or n:find("hair") or n:find("hat")
        end

        -- Builds the aura on your character. Returns true, or false plus the reason.
        local function ba_build(auraModel)
            local char = LocalPlayer.Character
            if not char or not char.Parent then return false, "no character" end
            local native = char:FindFirstChild("bodyaura")
            if native and native:IsA("LocalScript") then native.Disabled = true end
            ba_destroyContainer()
            ba_cleanCharacter(char)

            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return false, "no HumanoidRootPart" end

            local rig = ba_findRig(auraModel)
            local source = rig or auraModel

            -- every visual part of the aura (skip parts nested inside another part)
            local items = {}
            local function collect(inst)
                if inst:IsA("BasePart") then
                    local p, nested = inst.Parent, false
                    while p and p ~= source do
                        if p:IsA("BasePart") then nested = true; break end
                        p = p.Parent
                    end
                    if not nested then table.insert(items, inst) end
                end
            end
            collect(source)
            for _, d in ipairs(source:GetDescendants()) do collect(d) end
            if #items == 0 then return false, "aura has no parts" end

            -- reference point of the aura model
            local rigRoot = rig and (rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart
                or rig:FindFirstChild("Torso") or rig:FindFirstChild("UpperTorso"))
            local pivot
            if rigRoot and rigRoot:IsA("BasePart") then
                pivot = rigRoot.CFrame
            else
                local sum = Vector3.zero
                for _, p in ipairs(items) do sum += p.Position end
                pivot = CFrame.new(sum / #items)
            end

            -- your character's parts, by normalised name ("Left Arm" == "LeftArm")
            local charByName = {}
            for _, p in ipairs(char:GetChildren()) do
                if p:IsA("BasePart") then charByName[ba_norm(p.Name)] = p end
            end
            local rigHead = rig and rig:FindFirstChild("Head")
            local charHead = char:FindFirstChild("Head")

            local container = Instance.new("Model")
            container.Name = "AuraVisuals"
            container.Parent = char
            BodyAura.container = container

            local built = 0
            for _, auraPart in ipairs(items) do
                local newPart = auraPart:Clone()
                -- drop anything that could fight your character
                for _, d in ipairs(newPart:GetDescendants()) do
                    if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Humanoid")
                        or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
                        d:Destroy()
                    end
                end
                newPart.Anchored = false
                newPart.CanCollide = false
                newPart.CanTouch = false
                newPart.CanQuery = false
                newPart.Massless = true
                newPart.Parent = container

                local isRoot = auraPart == rigRoot or auraPart.Name == "HumanoidRootPart"
                if isRoot then newPart.Transparency = 1 end
                if ba_isHeadish(auraPart.Name) then ba_stripFace(newPart) end

                local weld = Instance.new("Weld")
                weld.Part1 = newPart
                local direct = (auraPart.Parent == source) and charByName[ba_norm(auraPart.Name)]
                if direct then
                    -- same body part on both sides: sit exactly on it
                    weld.Part0 = direct
                    weld.C0 = CFrame.new()
                elseif ba_isHeadish(auraPart.Name) and charHead then
                    -- hair / hat style parts follow your head
                    weld.Part0 = charHead
                    local ref = rigHead and rigHead.CFrame or pivot
                    weld.C0 = ref:ToObjectSpace(auraPart.CFrame)
                else
                    -- everything else keeps its place relative to the aura's centre
                    weld.Part0 = hrp
                    weld.C0 = pivot:ToObjectSpace(auraPart.CFrame)
                end
                weld.Parent = newPart
                built += 1
            end

            ba_hidePlastic(container)
            if built == 0 then return false, "nothing built" end
            return true
        end

        local function ba_scanList()
            table.clear(BodyAura.list)
            table.clear(BodyAura.lookup)
            local ShopItems = ReplicatedStorage:FindFirstChild("ShopItems") or ReplicatedStorage:WaitForChild("ShopItems", 5)
            if not ShopItems then return end
            local folder = ShopItems:FindFirstChild("Aura") or ShopItems:WaitForChild("Aura", 5)
            if not folder then return end
            for _, child in pairs(folder:GetChildren()) do
                local name = child.Name:gsub("^Aura_", "")
                BodyAura.lookup[name] = child
                table.insert(BodyAura.list, name)
            end
            table.sort(BodyAura.list)
        end

        local function ba_applyByName(name)
            local model = BodyAura.lookup[name]
            if not model then return false, "aura not found" end
            BodyAura.selected = name
            if not BodyAura.active then return false, "disabled" end
            return ba_build(model)
        end

        local function ba_enable(name)
            ba_scanList()
            BodyAura.active = true
            if name and BodyAura.lookup[name] then
                BodyAura.selected = name
            elseif not BodyAura.selected and #BodyAura.list > 0 then
                BodyAura.selected = BodyAura.list[1]
            end
            local ok, why = true, nil
            if BodyAura.selected then ok, why = ba_applyByName(BodyAura.selected) end
            if not BodyAura.charAddedConn then
                BodyAura.charAddedConn = LocalPlayer.CharacterAdded:Connect(function(char)
                    char:WaitForChild("HumanoidRootPart", 5)
                    task.wait(1)
                    if BodyAura.active and BodyAura.selected then ba_applyByName(BodyAura.selected) end
                end)
            end
            return ok, why
        end

        local function ba_disable()
            BodyAura.active = false
            if BodyAura.charAddedConn then
                BodyAura.charAddedConn:Disconnect(); BodyAura.charAddedConn = nil
            end
            ba_destroyContainer()
        end

        baScan, baApply, baEnable, baDisable = ba_scanList, ba_applyByName, ba_enable, ba_disable
        BodyAuraList = BodyAura.list
    end
    baScan()

    -- ============================================================
    -- NAMETAG LOGO CHANGER (client-side only: edits your own CreatorTag icons)
    -- ============================================================
    local LogoNames = { "Booster", "Staff", "Tester", "Twitch", "VIP", "Youtuber" }
    local LogoOriginal, LogoWanted = {}, {}
    local applyLogo, resetLogos, logoDefault

    do
        local function getCreatorTag()
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            return hrp and hrp:FindFirstChild("CreatorTag")
        end

        local function setIcon(name, on)
            local tag = getCreatorTag()
            if not tag then return end
            for _, v in ipairs(tag:GetChildren()) do
                if v:IsA("ImageLabel") and v.Name == name then v.Visible = on end
            end
        end

        local function snapshot()
            local tag = getCreatorTag()
            if not tag then return end
            for _, n in ipairs(LogoNames) do
                if LogoOriginal[n] == nil then
                    local lbl = tag:FindFirstChild(n)
                    LogoOriginal[n] = (lbl and lbl:IsA("ImageLabel")) and lbl.Visible or false
                end
            end
        end
        snapshot()

        logoDefault = function(name) return LogoOriginal[name] == true end

        applyLogo = function(name, on)
            snapshot()
            LogoWanted[name] = on
            pcall(function() LocalPlayer:SetAttribute(name, on) end)
            setIcon(name, on)
        end

        resetLogos = function()
            for _, n in ipairs(LogoNames) do
                local orig = LogoOriginal[n] == true
                LogoWanted[n] = nil
                pcall(function() LocalPlayer:SetAttribute(n, orig) end)
                setIcon(n, orig)
            end
        end

        -- Re-apply chosen icons after respawn (the tag is rebuilt each life).
        Track(LocalPlayer.CharacterAdded:Connect(function(char)
            local hrp = char:WaitForChild("HumanoidRootPart", 5)
            local tag = hrp and hrp:WaitForChild("CreatorTag", 5)
            if not tag then return end
            task.wait(0.3)
            for n, on in pairs(LogoWanted) do setIcon(n, on) end
        end))
    end

    -- ============================================================
    -- NAMEPLATE ENGINE (Rank Changer), ported from the Arur Hub Hoopz source.
    -- Wrapped in a function so their ~40 locals don't count against this branch's local limit.
    -- ============================================================
    local NP = (function()
        -- ============================================================
        -- RANK ENGINE — applies to every player's nameplate
        -- ============================================================
        local RankEngine = {
            active = false,
            selected = nil,
            list = {},
            lookup = {},
            originalImages = {},
            originalGradients = {},
            charConns = {},
            tagConns = {},
            addedConn = nil,
        }

        local RANK_ORDER = {
            "Rookie", "Pro", "All-star", "Veteran", "Elite", "Superstar",
            "Phenom", "Legend", "Mamba", "HoF", "G.O.A.T", "Aura",
        }

        local function rank_canonical(name) return (name:gsub("%d+$", "")) end

        local function rank_scan()
            table.clear(RankEngine.list)
            table.clear(RankEngine.lookup)
            local Ranks = ReplicatedStorage:FindFirstChild("Ranks")
            if not Ranks then return end
            local icons  = Ranks:FindFirstChild("Icons")
            local colors = Ranks:FindFirstChild("Colors")
            if icons then
                for _, child in pairs(icons:GetChildren()) do
                    if child:IsA("ImageLabel") or child:IsA("ImageButton") then
                        local n = rank_canonical(child.Name)
                        RankEngine.lookup[n] = RankEngine.lookup[n] or {}
                        RankEngine.lookup[n].icon = child
                    end
                end
            end
            if colors then
                for _, child in pairs(colors:GetChildren()) do
                    if child:IsA("UIGradient") then
                        local n = rank_canonical(child.Name)
                        RankEngine.lookup[n] = RankEngine.lookup[n] or {}
                        RankEngine.lookup[n].gradient = child
                    end
                end
            end
            for n, data in pairs(RankEngine.lookup) do
                if data.icon or data.gradient then table.insert(RankEngine.list, n) end
            end
            table.sort(RankEngine.list, function(a, b)
                local ai = table.find(RANK_ORDER, a) or 999
                local bi = table.find(RANK_ORDER, b) or 999
                if ai ~= bi then return ai < bi end
                return a < b
            end)
        end

        local function rank_applyToImage(img, data)
            if not img or not data then return end
            if not RankEngine.originalImages[img] then
                RankEngine.originalImages[img] = img.Image
            end
            if data.icon and (data.icon:IsA("ImageLabel") or data.icon:IsA("ImageButton")) then
                img.Image = data.icon.Image
            end
            img.Visible = true
        end

        local function rank_applyToLabel(label, data)
            if not label or not data or not data.gradient then return end
            local g = label:FindFirstChildOfClass("UIGradient")
            if not g then g = Instance.new("UIGradient"); g.Parent = label end
            if not RankEngine.originalGradients[label] then
                RankEngine.originalGradients[label] = {
                    color = g.Color, transp = g.Transparency, rot = g.Rotation, off = g.Offset,
                }
            end
            g.Color = data.gradient.Color
            g.Transparency = data.gradient.Transparency
            g.Rotation = data.gradient.Rotation
            g.Offset = data.gradient.Offset
            label.TextColor3 = Color3.new(1, 1, 1)
        end

        local function rank_applyToCharacter(char)
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local tag = hrp:FindFirstChild("NameTag")
            if not tag then return end
            local data = RankEngine.selected and RankEngine.lookup[RankEngine.selected]
            if not data then return end
            local main = tag:FindFirstChild("MainFrame")
            local game = tag:FindFirstChild("GameFrame")
            if main then
                rank_applyToImage(main:FindFirstChild("RankIcon"), data)
                rank_applyToLabel(main:FindFirstChild("NameLabel"), data)
            end
            if game then
                rank_applyToImage(game:FindFirstChild("RankLabel"), data)
                rank_applyToLabel(game:FindFirstChild("NameLabel"), data)
            end
        end

        local function rank_applyAll()
            if not RankEngine.active or not RankEngine.selected then return end
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr.Character then rank_applyToCharacter(plr.Character) end
            end
        end

        local function rank_hookPlayer(plr)
            if RankEngine.charConns[plr] then return end
            local function installChar(char)
                task.wait(0.5)
                rank_applyToCharacter(char)
                local hrp = char:WaitForChild("HumanoidRootPart", 5)
                if not hrp then return end
                local existing = RankEngine.tagConns[hrp]
                if existing then existing:Disconnect() end
                RankEngine.tagConns[hrp] = hrp.ChildAdded:Connect(function(child)
                    if child:IsA("BillboardGui") and child.Name == "NameTag" then
                        task.wait(0.05)
                        rank_applyToCharacter(char)
                    end
                end)
                local tag = hrp:WaitForChild("NameTag", 5)
                if tag then
                    local old = RankEngine.tagConns[tag]
                    if old then old:Disconnect() end
                    RankEngine.tagConns[tag] = tag.DescendantAdded:Connect(function()
                        task.wait(0.02)
                        if RankEngine.active then rank_applyToCharacter(char) end
                    end)
                end
            end
            RankEngine.charConns[plr] = plr.CharacterAdded:Connect(installChar)
            if plr.Character then task.spawn(installChar, plr.Character) end
        end

        local function rank_restoreAll()
            for img, orig in pairs(RankEngine.originalImages) do
                if img and img.Parent then pcall(function() img.Image = orig end) end
            end
            table.clear(RankEngine.originalImages)
            for label, orig in pairs(RankEngine.originalGradients) do
                if label and label.Parent then
                    local g = label:FindFirstChildOfClass("UIGradient")
                    if g then
                        pcall(function()
                            g.Color = orig.color
                            g.Transparency = orig.transp
                            g.Rotation = orig.rot
                            g.Offset = orig.off
                        end)
                    end
                end
            end
            table.clear(RankEngine.originalGradients)
        end

        local function rank_enable()
            rank_scan()
            RankEngine.active = true
            if (not RankEngine.selected or RankEngine.selected == "") and #RankEngine.list > 0 then
                RankEngine.selected = RankEngine.list[#RankEngine.list]
            end
            for _, plr in ipairs(Players:GetPlayers()) do rank_hookPlayer(plr) end
            if not RankEngine.addedConn then
                RankEngine.addedConn = Players.PlayerAdded:Connect(rank_hookPlayer)
            end
            rank_applyAll()
        end

        local function rank_disable()
            RankEngine.active = false
            if RankEngine.addedConn then RankEngine.addedConn:Disconnect(); RankEngine.addedConn = nil end
            for _, c in pairs(RankEngine.charConns) do pcall(function() c:Disconnect() end) end
            table.clear(RankEngine.charConns)
            for _, c in pairs(RankEngine.tagConns) do pcall(function() c:Disconnect() end) end
            table.clear(RankEngine.tagConns)
            rank_restoreAll()
        end

        return {
            rank_scan = rank_scan, rank_enable = rank_enable, rank_disable = rank_disable,
            rank_applyAll = rank_applyAll, RankEngine = RankEngine,
        }
    end)()

    local Window = RiftUI:CreateWindow({Name = "Arur Hub", LoadingSubtitle = "Hoopz", Theme = "Default", ToggleUIKeybind = "RightControl", ConfigurationSaving = {Enabled = true, FolderName = "RiftWtf", FileName = "RiftWtf"}})

    Notify = function(props) Window:Notify(props) end

    local CombatTab = Window:CreateTab({ Name = "Main", Icon = "home" })
    local BallTab = Window:CreateTab({ Name = "Ball", Icon = "circle" })
    local HVHTab = Window:CreateTab({ Name = "HVH", Icon = "activity" })
    local VisualsTab = Window:CreateTab({ Name = "Visuals", Icon = "eye" })
    local PrivacyTab = Window:CreateTab({ Name = "Privacy", Icon = "user" })
    local UtilityTab = Window:CreateTab({ Name = "Extras", Icon = "list" })

    CombatTab:CreateSection("Silent Aim")
    CombatTab:CreateToggle({
        Name = "Enable Silent Aim",
        Flag = "rift_aural",
        CurrentValue = s.Shooting.AuralEnabled,
        Callback = function(v) setAural(v) end,
    })
    CombatTab:CreateSlider({
        Name = "Shot delay",
        Range = { 0.15, 0.42 }, Increment = 0.01,
        CurrentValue = s.Shooting.ShotDelay, Flag = "rift_delay",
        Callback = function(v) s.Shooting.ShotDelay = v end,
    })


    CombatTab:CreateSection("Aim Options")
    CombatTab:CreateKeybind({
        Name = "Aimbot keybind",
        Flag = "rift_aural_key",
        CurrentValue = s.Shooting.AuralKeybind,
        Callback = function(key)
            if typeof(key) == "EnumItem" then s.Shooting.AuralKeybind = key end
        end,
    })
    CombatTab:CreateDropdown({
        Name = "Aim mode",
        Desc = "Silent: aims the shot without moving your screen. Camlock: also locks your screen on the rim while you shoot.",
        Options = { "Silent", "Camlock" }, CurrentValue = s.Shooting.AimMode, Flag = "rift_aimmode",
        Callback = function(v)
            if type(v) == "table" then v = v[1] end
            if v == "Silent" or v == "Camlock" then s.Shooting.AimMode = v end
        end,
    })
    CombatTab:CreateSlider({
        Name = "Camlock strength", Desc = "100% = hard lock, lower = smoother pull (Camlock mode only)",
        Range = { 10, 100 }, Increment = 5, Suffix = "%",
        CurrentValue = 100, Flag = "rift_camstr",
        Callback = function(v) s.Shooting.CamlockStrength = (tonumber(v) or 100) / 100 end,
    })
    CombatTab:CreateToggle({
        Name = "Randomize shot delay", Flag = "rift_randdelay",
        CurrentValue = s.Shooting.RandomizeShotDelay,
        Callback = function(v) s.Shooting.RandomizeShotDelay = v end,
    })
    CombatTab:CreateSlider({
        Name = "Min delay", Range = { 0, 1 }, Increment = 0.05, Suffix = "s",
        CurrentValue = s.Shooting.ShotDelayMin, Flag = "rift_mindelay",
        Callback = function(v) s.Shooting.ShotDelayMin = v end,
    })
    CombatTab:CreateSlider({
        Name = "Max delay", Range = { 0, 1 }, Increment = 0.05, Suffix = "s",
        CurrentValue = s.Shooting.ShotDelayMax, Flag = "rift_maxdelay",
        Callback = function(v) s.Shooting.ShotDelayMax = v end,
    })
    CombatTab:CreateToggle({
        Name = "EBL Hop", Desc = "Require second jump before firing.",
        Flag = "rift_ebl", CurrentValue = s.Shooting.EBLHop,
        Callback = function(v) s.Shooting.EBLHop = v end,
    })
    CombatTab:CreateToggle({
        Name = "Humanize aim", Flag = "rift_human",
        CurrentValue = s.Shooting.HumanizeAim,
        Callback = function(v) s.Shooting.HumanizeAim = v end,
    })
    CombatTab:CreateSlider({
        Name = "Humanize strength", Range = { 0.2, 5 }, Increment = 0.1,
        CurrentValue = s.Shooting.HumanizeStrength, Flag = "rift_hstr",
        Callback = function(v) s.Shooting.HumanizeStrength = v end,
    })
    CombatTab:CreateSlider({
        Name = "Miss chance", Range = { 0, 80 }, Increment = 1, Suffix = "%",
        CurrentValue = s.Shooting.MissChance, Flag = "rift_miss",
        Callback = function(v) s.Shooting.MissChance = v end,
    })
    CombatTab:CreateSection("Auto Guard")
    CombatTab:CreateToggle({
        Name = "Auto guard", Flag = "rift_guard", CurrentValue = s.Defending.AutoGuard,
        Callback = function(v) setGuard(v) end,
    })
    CombatTab:CreateKeybind({
        Name = "Auto guard keybind", Flag = "rift_guard_key",
        CurrentValue = s.Defending.GuardKeybind,
        Callback = function(key)
            if typeof(key) == "EnumItem" then s.Defending.GuardKeybind = key end
        end,
    })
    CombatTab:CreateDropdown({
        Name = "Guard mode", Options = { "Reactive", "Balanced", "Aggressive" },
        CurrentValue = s.Defending.AutoGuardMode, Flag = "rift_guard_mode",
        Callback = function(v) s.Defending.AutoGuardMode = v end,
    })
    CombatTab:CreateToggle({
        Name = "Guard nearest if no dribbler", Flag = "rift_guard_near",
        CurrentValue = s.Defending.AutoGuardNearest,
        Callback = function(v) s.Defending.AutoGuardNearest = v end,
    })
    CombatTab:CreateSlider({
        Name = "Guard range", Range = { 10, 60 }, Increment = 1,
        CurrentValue = s.Defending.AutoGuardRange, Flag = "rift_guard_range",
        Callback = function(v) s.Defending.AutoGuardRange = v end,
    })
    CombatTab:CreateSlider({
        Name = "Prediction strength", Range = { 0.1, 1 }, Increment = 0.05,
        CurrentValue = s.Defending.GuardPrediction, Flag = "rift_guard_pred",
        Callback = function(v) s.Defending.GuardPrediction = v end,
    })

    BallTab:CreateSection("Ball Magnet")
    BallTab:CreateToggle({
        Name = "Ball magnet", Flag = "rift_mag", CurrentValue = s.Ball.BallMags,
        Callback = function(v) setMagnet(v) end,
    })
    BallTab:CreateKeybind({
        Name = "Magnet keybind", Flag = "rift_mag_key", CurrentValue = Enum.KeyCode.M,
        Callback = function(key)
            if typeof(key) == "EnumItem" then s.Ball.MagnetKeybind = key.Name end
        end,
    })
    BallTab:CreateSlider({
        Name = "Magnet size", Range = { 1, 50 }, Increment = 1,
        CurrentValue = s.Ball.BallMagRange, Flag = "rift_mag_size",
        Callback = function(v)
            s.Ball.BallMagRange = v
            if magnetHitbox then magnetHitbox.Size = Vector3.new(v, v, v) end
        end,
    })
    BallTab:CreateToggle({
        Name = "Show magnet visualizer", Flag = "rift_mag_vis",
        CurrentValue = s.Ball.BallMagVisualizer,
        Callback = function(v)
            s.Ball.BallMagVisualizer = v
            if magnetHitbox then
                local box = magnetHitbox:FindFirstChild("RiftMagnetBox")
                if box then box.Transparency = v and 0.2 or 1 end
            end
        end,
    })

    BallTab:CreateSection("Mag V2")
    BallTab:CreateToggle({
        Name = "Mag V2",
        Desc = "Standalone touch-magnet. Uses its own ball name & reach.",
        Flag = "rift_magv2", CurrentValue = s.MagV2.Enabled,
        Callback = function(v) setMagV2(v) end,
    })
    BallTab:CreateKeybind({
        Name = "Mag V2 keybind", Desc = "Default U. Toggle Mag V2 on/off.",
        Flag = "rift_magv2_key", CurrentValue = s.MagV2.Keybind,
        Callback = function(key)
            if typeof(key) == "EnumItem" then s.MagV2.Keybind = key end
        end,
    })
    BallTab:CreateInput({
        Name = "Mag V2 ball name", Placeholder = "Ball",
        CurrentValue = s.MagV2.BallName, Flag = "rift_magv2_name",
        Callback = function(text)
            if text ~= "" then s.MagV2.BallName = text end
        end,
    })
    BallTab:CreateSlider({
        Name = "Mag V2 reach", Range = { 1, 100 }, Increment = 1,
        CurrentValue = s.MagV2.Reach, Flag = "rift_magv2_reach",
        Callback = function(v) s.MagV2.Reach = v end,
    })

    BallTab:CreateSection("Ball Reach")
    BallTab:CreateToggle({
        Name = "Ball reach", Flag = "rift_reach", CurrentValue = s.Ball.BallReach,
        Callback = function(v) setReach(v) end,
    })
    BallTab:CreateKeybind({
        Name = "Reach keybind", Flag = "rift_reach_key", CurrentValue = Enum.KeyCode.N,
        Callback = function(key)
            if typeof(key) == "EnumItem" then s.Ball.ReachKeybind = key.Name end
        end,
    })
    BallTab:CreateSlider({
        Name = "Reach size", Range = { 1, 30 }, Increment = 1,
        CurrentValue = s.Ball.BallReachRange, Flag = "rift_reach_size",
        Callback = function(v) s.Ball.BallReachRange = v end,
    })
    BallTab:CreateToggle({
        Name = "Show reach visualizer", Flag = "rift_reach_vis",
        CurrentValue = s.Ball.BallReachVisualizer,
        Callback = function(v)
            s.Ball.BallReachVisualizer = v
            if v then
                enableReach()
            else
                removeReachVisualizer()
                if not s.Ball.BallReach then disableReach() end
            end
        end,
    })

    BallTab:CreateSection("TPWalk")
    BallTab:CreateToggle({
        Name = "tpwalk",
        Desc = "Teleport-walk; nudges your root part each frame for a smooth glide.",
        Flag = "rift_tpwalk", CurrentValue = s.TPWalk.Enabled,
        Callback = function(v) setTPWalk(v) end,
    })
    BallTab:CreateKeybind({
        Name = "tpwalk keybind", Flag = "rift_tpwalk_key",
        CurrentValue = s.TPWalk.Keybind,
        Callback = function(key)
            if typeof(key) == "EnumItem" then s.TPWalk.Keybind = key end
        end,
    })
    BallTab:CreateSlider({
        Name = "tpwalk speed", Desc = "Step distance per frame (0.001 – 0.06).",
        Range = { 0.001, 0.06 }, Increment = 0.001,
        CurrentValue = s.TPWalk.Speed, Flag = "rift_tpwalk_speed",
        Callback = function(v) s.TPWalk.Speed = v end,
    })

    buildHVHTab(HVHTab, s.HVH, true) -- Hoopz anti-cheat kicks for HipHeight changes, so it is left out here

    VisualsTab:CreateSection("Aimbot Range Indicator")
    VisualsTab:CreateToggle({
        Name = "Aimbot range indicator", Flag = "rift_ind",
        CurrentValue = s.Visuals.ShotIndicator,
        Callback = setShotIndicator,
    })
    VisualsTab:CreateDropdown({
        Name = "Indicator style",
        Options = { "Above head", "Whole body" },
        CurrentValue = s.Visuals.IndicatorStyle, Flag = "rift_ind_style",
        Callback = function(v) s.Visuals.IndicatorStyle = v end,
    })
    VisualsTab:CreateDropdown({
        Name = "Indicator color",
        Options = { "Blue", "Purple", "Green", "Red", "Yellow" },
        CurrentValue = s.Visuals.IndicatorColor, Flag = "rift_ind_col",
        Callback = function(v) s.Visuals.IndicatorColor = v; applyIndicatorColor() end,
    })

    VisualsTab:CreateSection("Goal Effect")
    local function getEffectNames()
        local names = {}
        for k in pairs(Effects) do table.insert(names, k) end
        table.sort(names)
        return names
    end
    VisualsTab:CreateDropdown({
        Name = "Select effect", Options = getEffectNames(),
        CurrentValue = s.Goal.SelectedEffect, Flag = "rift_goal_sel",
        Callback = function(v)
            s.Goal.SelectedEffect = v
            s.Goal.CurrentEffect = v
            if s.Goal.Enabled then pcall(applyGoalEffect) end
        end,
    })
    VisualsTab:CreateToggle({
        Name = "Enable goal effect changer", Flag = "rift_goal",
        CurrentValue = s.Goal.Enabled,
        Callback = function(v)
            s.Goal.Enabled = v
            if v then pcall(applyGoalEffect) else pcall(resetGoalEffect) end
        end,
    })
    VisualsTab:CreateButton({
        Name = "Reset goal effect",
        Callback = function()
            s.Goal.Enabled = false
            s.Goal.SelectedEffect = "LightRay"
            s.Goal.CurrentEffect = "LightRay"
            pcall(resetGoalEffect)
        end,
    })

    VisualsTab:CreateSection("Body Aura")
    VisualsTab:CreateDropdown({
        Name = "Aura", Options = #BodyAuraList > 0 and BodyAuraList or { "None" },
        CurrentValue = s.BodyAura.Selected ~= "" and s.BodyAura.Selected or nil, Flag = "rift_bodyaura_sel",
        Callback = function(v)
            s.BodyAura.Selected = v
            if s.BodyAura.Enabled then
                local ok, why = baApply(v)
                if not ok then Notify({ title = "Body Aura", content = "Could not apply " .. tostring(v) .. ": " .. tostring(why), duration = 4 }) end
            end
        end,
    })
    VisualsTab:CreateToggle({
        Name = "Enable body aura", Flag = "rift_bodyaura", CurrentValue = s.BodyAura.Enabled,
        Callback = function(v)
            s.BodyAura.Enabled = v
            if v then
                local ok, why = baEnable(s.BodyAura.Selected ~= "" and s.BodyAura.Selected or nil)
                if not ok then Notify({ title = "Body Aura", content = "Could not apply: " .. tostring(why), duration = 4 }) end
            else
                baDisable()
            end
        end,
    })
    VisualsTab:CreateButton({
        Name = "Reset body aura",
        Callback = function()
            s.BodyAura.Enabled = false
            s.BodyAura.Selected = ""
            baDisable()
        end,
    })

    VisualsTab:CreateSection("Rank Changer")
    NP.rank_scan()
    VisualsTab:CreateDropdown({
        Name = "Rank",
        Options = #NP.RankEngine.list > 0 and NP.RankEngine.list or { "Rookie", "Pro", "All-star", "Veteran", "Elite", "Superstar", "Phenom", "Legend", "Mamba", "HoF", "G.O.A.T", "Aura" },
        CurrentValue = s.RankChanger.Selected ~= "" and s.RankChanger.Selected or nil, Flag = "rift_rank_sel",
        Callback = function(v)
            s.RankChanger.Selected = v
            if s.RankChanger.Enabled then NP.RankEngine.selected = v; NP.rank_applyAll() end
        end,
    })
    VisualsTab:CreateToggle({
        Name = "Enable rank changer", Desc = "Swaps rank icon + gradient on EVERY player's nameplate (local view).",
        Flag = "rift_rank", CurrentValue = s.RankChanger.Enabled,
        Callback = function(v)
            s.RankChanger.Enabled = v
            if v then
                NP.RankEngine.selected = s.RankChanger.Selected ~= "" and s.RankChanger.Selected or nil
                NP.rank_enable()
            else
                NP.rank_disable()
            end
        end,
    })
    VisualsTab:CreateButton({
        Name = "Reset rank",
        Callback = function() s.RankChanger.Enabled = false; s.RankChanger.Selected = ""; NP.rank_disable() end,
    })

    VisualsTab:CreateSection("Court Spoofer")
    VisualsTab:CreateDropdown({
        Name = "Select court", Options = #CourtNames > 0 and CourtNames or { "None" },
        CurrentValue = s.CourtSpoofer.SelectedCourt, Flag = "rift_court_sel",
        Callback = function(v)
            s.CourtSpoofer.SelectedCourt = v
            s.CourtSpoofer.CurrentCourt = v
            if s.CourtSpoofer.Enabled then pcall(applyCourtSpoofer) end
        end,
    })
    VisualsTab:CreateToggle({
        Name = "Enable court spoofer", Flag = "rift_court",
        CurrentValue = s.CourtSpoofer.Enabled,
        Callback = function(v)
            s.CourtSpoofer.Enabled = v
            if v then pcall(applyCourtSpoofer) else pcall(resetCourtSpoofer) end
        end,
    })
    VisualsTab:CreateButton({
        Name = "Reset court",
        Callback = function()
            s.CourtSpoofer.Enabled = false
            s.CourtSpoofer.SelectedCourt = "None"
            s.CourtSpoofer.CurrentCourt = "None"
            pcall(resetCourtSpoofer)
        end,
    })

    VisualsTab:CreateSection("Nameplate & Title")
    VisualsTab:CreateToggle({
        Name = "Hide my nameplate & tags", Flag = "rift_np_hide",
        CurrentValue = s.Visuals.HideOwnNameplate,
        Callback = function(v) s.Visuals.HideOwnNameplate = v; applyOwnNameplate() end,
    })
    VisualsTab:CreateInput({
        Name = "Custom username", Placeholder = "e.g. Fatal",
        Desc = "Shows on your nameplate, in chat, and when you score (only you see it)",
        CurrentValue = s.Visuals.CustomNameText, Flag = "rift_np_name",
        Callback = function(text)
            s.Visuals.CustomNameText = text
            s.Visuals.CustomName = (text ~= "")
            applyOwnNameplate()
            NameSpoof.refresh()
        end,
    })
    VisualsTab:CreateInput({
        Name = "Custom record", Placeholder = "e.g. 99-0",
        CurrentValue = s.Visuals.CustomRecordText, Flag = "rift_np_rec",
        Callback = function(text)
            s.Visuals.CustomRecordText = text
            s.Visuals.CustomRecord = (text ~= "")
            applyOwnNameplate()
        end,
    })
    VisualsTab:CreateInput({
        Name = "Custom title", Placeholder = "e.g. Fatal Elite",
        CurrentValue = s.Visuals.CustomTitleText, Flag = "rift_np_title",
        Callback = function(text)
            s.Visuals.CustomTitleText = text
            s.Visuals.CustomTitle = (text ~= "")
            applyOwnNameplate()
        end,
    })

    PrivacyTab:CreateSection("Device Spoofer")
    PrivacyTab:CreateToggle({
        Name = "Device spoofer", Flag = "rift_dev", CurrentValue = s.Misc.DeviceSpoofer,
        Callback = function(v) s.Misc.DeviceSpoofer = v; SpoofDevice() end,
    })
    PrivacyTab:CreateDropdown({
        Name = "Device", Options = { "PC", "Mobile", "Gamepad" },
        CurrentValue = s.Misc.Device, Flag = "rift_dev_sel",
        Callback = function(v) s.Misc.Device = v; SpoofDevice() end,
    })

    PrivacyTab:CreateSection("Logo Changer")
    for _, n in ipairs(LogoNames) do
        PrivacyTab:CreateToggle({
            Name = n .. " logo", Desc = "Shows the " .. n .. " icon on your own nametag (only you see it).",
            Flag = "rift_logo_" .. n:lower(), CurrentValue = logoDefault(n),
            Callback = function(v) applyLogo(n, v) end,
        })
    end
    PrivacyTab:CreateButton({
        Name = "Reset logos",
        Callback = function() resetLogos() end,
    })

    PrivacyTab:CreateSection("Ball Changer")
    PrivacyTab:CreateDropdown({
        Name = "Select ball", Options = #BallNames > 0 and BallNames or { "None" },
        CurrentValue = s.BallChanger.SelectedBall, Flag = "rift_ball_sel",
        Callback = function(v)
            s.BallChanger.SelectedBall = v
            s.BallChanger.CurrentBall = v
            if s.BallChanger.Enabled then pcall(applyBallChanger) end
        end,
    })
    PrivacyTab:CreateToggle({
        Name = "Enable ball changer", Flag = "rift_ball",
        CurrentValue = s.BallChanger.Enabled,
        Callback = function(v)
            s.BallChanger.Enabled = v
            if v then pcall(applyBallChanger) else pcall(resetBallChanger) end
        end,
    })
    PrivacyTab:CreateButton({
        Name = "Reset ball",
        Callback = function()
            s.BallChanger.Enabled = false
            s.BallChanger.SelectedBall = "ForceField"
            s.BallChanger.CurrentBall = "ForceField"
            pcall(resetBallChanger)
        end,
    })

    PrivacyTab:CreateSection("Trail Spoofer")
    PrivacyTab:CreateDropdown({
        Name = "Select trail", Options = #TrailNames > 0 and TrailNames or { "None" },
        CurrentValue = s.TrailSpoofer.SelectedTrail, Flag = "rift_trail_sel",
        Callback = function(v)
            s.TrailSpoofer.SelectedTrail = v
            s.TrailSpoofer.CurrentTrail = v
            if s.TrailSpoofer.Enabled then pcall(applyTrailSpoofer) end
        end,
    })
    PrivacyTab:CreateToggle({
        Name = "Enable trail spoofer", Flag = "rift_trail",
        CurrentValue = s.TrailSpoofer.Enabled,
        Callback = function(v)
            s.TrailSpoofer.Enabled = v
            if v then pcall(applyTrailSpoofer) else pcall(resetTrailSpoofer) end
        end,
    })
    PrivacyTab:CreateButton({
        Name = "Reset trail",
        Callback = function()
            s.TrailSpoofer.Enabled = false
            s.TrailSpoofer.SelectedTrail = "None"
            s.TrailSpoofer.CurrentTrail = "None"
            pcall(resetTrailSpoofer)
        end,
    })

    PrivacyTab:CreateSection("Ball Aura Spoofer")
    PrivacyTab:CreateDropdown({
        Name = "Select aura", Options = #AuraNames > 0 and AuraNames or { "None" },
        CurrentValue = s.BallAura.SelectedAura, Flag = "rift_aura_sel",
        Callback = function(v)
            s.BallAura.SelectedAura = v
            s.BallAura.CurrentAura = v
            if s.BallAura.Enabled then pcall(applyBallAura) end
        end,
    })
    PrivacyTab:CreateToggle({
        Name = "Enable ball aura spoofer", Flag = "rift_aura",
        CurrentValue = s.BallAura.Enabled,
        Callback = function(v)
            s.BallAura.Enabled = v
            if v then pcall(applyBallAura) else pcall(resetBallAura) end
        end,
    })
    PrivacyTab:CreateButton({
        Name = "Reset ball aura",
        Callback = function()
            s.BallAura.Enabled = false
            s.BallAura.SelectedAura = "None"
            s.BallAura.CurrentAura = "None"
            pcall(resetBallAura)
        end,
    })

    UtilityTab:CreateSection("Anti Moderator")
    UtilityTab:CreateToggle({
        Name = "Anti moderator", Desc = "Notifies when a moderator is in the server.",
        Flag = "rift_mod", CurrentValue = s.Misc.AntiModerator,
        Callback = function(v)
            s.Misc.AntiModerator = v
            if v then startAntiMod() else stopAntiMod() end
        end,
    })

    UtilityTab:CreateSection("Config Saver")
    local ConfigName = "default"
    UtilityTab:CreateInput({
        Name = "Config name", Placeholder = "default",
        CurrentValue = "default", Flag = "rift_cfg_name",
        Callback = function(v) ConfigName = (v ~= "") and v or "default" end,
    })
    UtilityTab:CreateButton({
        Name = "Save config",
        Callback = function()
            local ok = pcall(function() Window:SaveConfig(ConfigName) end)
            Notify({ title = "Config", content = ok and ("Saved: " .. ConfigName) or "Save failed.", duration = 3 })
        end,
    })
    UtilityTab:CreateButton({
        Name = "Load config",
        Callback = function()
            local ok = pcall(function() Window:LoadConfig(ConfigName) end)
            Notify({ title = "Config", content = ok and ("Loaded: " .. ConfigName) or "Load failed.", duration = 3 })
        end,
    })

    setAural = function(on)
        s.Shooting.AuralEnabled = (on == nil) and (not s.Shooting.AuralEnabled) or on
        MobileRefresh(); SyncToggles()
    end
    setGuard = function(on)
        s.Defending.AutoGuard = (on == nil) and (not s.Defending.AutoGuard) or on
        if s.Defending.AutoGuard then enableAutoGuard() else disableAutoGuard() end
        MobileRefresh(); SyncToggles()
    end
    setMagnet = function(on)
        s.Ball.BallMags = (on == nil) and (not s.Ball.BallMags) or on
        if s.Ball.BallMags then enableMagnet() else disableMagnet() end
        MobileRefresh(); SyncToggles()
    end
    setReach = function(on)
        s.Ball.BallReach = (on == nil) and (not s.Ball.BallReach) or on
        if s.Ball.BallReach then enableReach() else disableReach() end
        MobileRefresh(); SyncToggles()
    end
    setTPWalk = function(on)
        s.TPWalk.Enabled = (on == nil) and (not s.TPWalk.Enabled) or on
        if s.TPWalk.Enabled then enableTPWalk() else disableTPWalk() end
        MobileRefresh(); SyncToggles()
    end
    setMagV2 = function(on)
        s.MagV2.Enabled = (on == nil) and (not s.MagV2.Enabled) or on
        if s.MagV2.Enabled then enableMagV2() else disableMagV2() end
        MobileRefresh(); SyncToggles()
    end

    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        local magKey = s.Ball.MagnetKeybind
        if magKey and input.KeyCode == Enum.KeyCode[magKey] then setMagnet() end
    end)
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        local bind = s.Shooting.AuralKeybind
        local targetKey = (type(bind) == "string") and Enum.KeyCode[bind] or bind
        if input.KeyCode == targetKey then setAural() end
    end)
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        local bind = s.Defending.GuardKeybind
        local targetKey = (type(bind) == "string") and Enum.KeyCode[bind] or bind
        if input.KeyCode == targetKey then setGuard() end
    end)
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        local bind = s.HVH.Speed.Keybind
        local targetKey = (type(bind) == "string") and Enum.KeyCode[bind] or bind
        if input.KeyCode == targetKey then
            s.HVH.Speed.Enabled = not s.HVH.Speed.Enabled
            syncToggle(Window, "hvh_ws", s.HVH.Speed.Enabled)
        end
    end)
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == s.TPWalk.Keybind then setTPWalk() end
    end)
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == s.MagV2.Keybind then setMagV2() end
    end)

    -- keybind presses flip the real feature; this moves the menu toggles to match
    SyncToggles = function()
        syncToggle(Window, "rift_aural", s.Shooting.AuralEnabled)
        syncToggle(Window, "rift_guard", s.Defending.AutoGuard)
        syncToggle(Window, "rift_mag", s.Ball.BallMags)
        syncToggle(Window, "rift_magv2", s.MagV2.Enabled)
        syncToggle(Window, "rift_reach", s.Ball.BallReach)
        syncToggle(Window, "rift_tpwalk", s.TPWalk.Enabled)
    end

    if isMobile then (function() -- own scope keeps the Hoopz branch under the 200-local limit
        local ScreenGui = Instance.new("ScreenGui")
        ScreenGui.Name = "RiftWtfMobile"
        ScreenGui.ResetOnSpawn = false
        ScreenGui.IgnoreGuiInset = true
        ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        ScreenGui.DisplayOrder = 200
        pcall(function()
            if gethui then ScreenGui.Parent = gethui()
            else ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
        end)

        local Panel = Instance.new("Frame")
        Panel.Name = "Panel"
        Panel.Size = UDim2.fromOffset(52, 320)
        Panel.Position = UDim2.new(1, -64, 0.5, -160)
        Panel.BackgroundTransparency = 1
        Panel.Parent = ScreenGui

        local Layout = Instance.new("UIListLayout")
        Layout.Padding = UDim.new(0, 5)
        Layout.SortOrder = Enum.SortOrder.LayoutOrder
        Layout.Parent = Panel

        local function makeButton(label, order, onClick, isOn)
            local Button = Instance.new("TextButton")
            Button.Name = label
            Button.Size = UDim2.fromOffset(52, 40)
            Button.BackgroundColor3 = isOn and Color3.fromRGB(64, 140, 255) or Color3.fromRGB(17, 21, 33)
            Button.BackgroundTransparency = 0.05
            Button.Text = label
            Button.TextColor3 = isOn and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(236, 240, 250)
            Button.TextSize = 12
            Button.Font = Enum.Font.GothamBold
            Button.AutoButtonColor = false
            Button.LayoutOrder = order
            Button.Parent = Panel
            local Corner = Instance.new("UICorner")
            Corner.CornerRadius = UDim.new(1, 0)
            Corner.Parent = Button
            local Stroke = Instance.new("UIStroke")
            Stroke.Color = isOn and Color3.fromRGB(128, 190, 255) or Color3.fromRGB(29, 37, 58)
            Stroke.Thickness = 1.2
            Stroke.Transparency = 0.15
            Stroke.Parent = Button
            Button.MouseButton1Click:Connect(onClick)
            return Button, Stroke
        end

        local Aim, AimS = makeButton("Aim", 1, function() setAural() end, s.Shooting.AuralEnabled)
        local Guard, GuardS = makeButton("Guard", 2, function() setGuard() end, s.Defending.AutoGuard)
        local Mag, MagS = makeButton("Mag", 3, function() setMagnet() end, s.Ball.BallMags)
        local MagV2, MagV2S = makeButton("MagV2", 4, function() setMagV2() end, s.MagV2.Enabled)
        local Reach, ReachS = makeButton("Reach", 5, function() setReach() end, s.Ball.BallReach)
        local TPW, TPWS = makeButton("TPWalk", 6, function() setTPWalk() end, s.TPWalk.Enabled)

        local function paint(btn, stroke, on)
            btn.BackgroundColor3 = on and Color3.fromRGB(64, 140, 255) or Color3.fromRGB(17, 21, 33)
            btn.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(236, 240, 250)
            stroke.Color = on and Color3.fromRGB(128, 190, 255) or Color3.fromRGB(29, 37, 58)
        end

        MobileRefresh = function()
            paint(Aim, AimS, s.Shooting.AuralEnabled)
            paint(Guard, GuardS, s.Defending.AutoGuard)
            paint(Mag, MagS, s.Ball.BallMags)
            paint(MagV2, MagV2S, s.MagV2.Enabled)
            paint(Reach, ReachS, s.Ball.BallReach)
            paint(TPW, TPWS, s.TPWalk.Enabled)
        end

        local dragging = false
        local dragStart, startPos
        Panel.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch
                or input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos = Panel.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.Touch
                or input.UserInputType == Enum.UserInputType.MouseMovement) then
                local delta = input.Position - dragStart
                Panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)

        OnCleanup(function()
            pcall(function() ScreenGui:Destroy() end)
        end)
    end)() end

    hvhStart()

    OnCleanup(function()
        pcall(disableAutoGuard)
        pcall(disableMagnet)
        pcall(disableMagV2)
        pcall(disableReach)
        pcall(disableTPWalk)
        pcall(hvhResetAll)
        pcall(hvhStop)
        pcall(resetBallChanger)
        pcall(resetTrailSpoofer)
        pcall(resetBallAura)
        pcall(resetGoalEffect)
        pcall(resetCourtSpoofer)
        pcall(stopAntiMod)
        pcall(baDisable)
        pcall(resetLogos)
        pcall(function() setShotIndicator(false) end)
        for _, c in Cleanup.conns do pcall(function() c:Disconnect() end) end
    end
