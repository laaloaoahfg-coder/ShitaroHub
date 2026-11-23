-- Non-interactive, client-only markers attached to real pieces, not to cached
-- board squares. Adornee follows the actual instance while it animates.
return function(make,playerGui)
    local container=make("Folder",{Name="ShitaroCheckersMarkers"},playerGui)
    local entries={}
    local currentFolder,currentSide
    local ours=Color3.fromRGB(61,230,105)
    local theirs=Color3.fromRGB(255,70,70)
    local manager={}
    local function remove(part)
        local marker=entries[part]
        if marker then pcall(function() marker:Destroy() end);entries[part]=nil end
    end
    function manager.clear()
        for part in pairs(entries) do remove(part) end
        currentFolder=nil;currentSide=nil
    end
    local function add(part,side,localSide)
        local color=side==localSide and ours or theirs
        local billboard
        local ok=pcall(function()
            billboard=make("BillboardGui",{Name="CheckersPieceMarker",Adornee=part,
                Size=UDim2.fromOffset(30,30),AlwaysOnTop=true,LightInfluence=0,Active=false},container)
            local circle=make("Frame",{Name="Ring",AnchorPoint=Vector2.new(0.5,0.5),
                Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(26,26),
                BackgroundTransparency=1,BorderSizePixel=0,Active=false},billboard)
            make("UICorner",{CornerRadius=UDim.new(1,0)},circle)
            make("UIStroke",{Name="Outline",Color=color,Thickness=2,
                ApplyStrokeMode=Enum.ApplyStrokeMode.Border},circle)
            local dot=make("Frame",{Name="Dot",AnchorPoint=Vector2.new(0.5,0.5),
                Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(5,5),
                BackgroundColor3=color,BackgroundTransparency=0,BorderSizePixel=0,Active=false},circle)
            make("UICorner",{CornerRadius=UDim.new(1,0)},dot)
        end)
        if not ok then if billboard then pcall(function() billboard:Destroy() end) end;return false end
        entries[part]=billboard
        return true
    end
    function manager.update(tableRoot,side)
        local folder=tableRoot and tableRoot:FindFirstChild("Pieces")
        if (side~=1 and side~=2) or not folder then manager.clear();return end
        if folder~=currentFolder or side~=currentSide then
            manager.clear();currentFolder=folder;currentSide=side
        end
        local seen,ids={},{}
        local failed=false
        for _,part in ipairs(folder:GetChildren()) do
            local team,num=part.Name:match("^Piece([12])_(%d+)$")
            team,num=tonumber(team),tonumber(num)
            if team and num and num>=1 and num<=12 and part:IsA("BasePart") and not ids[part.Name] then
                ids[part.Name]=true;seen[part]=true
                if not entries[part] and not add(part,team,side) then failed=true end
            end
        end
        for part in pairs(entries) do if not seen[part] then remove(part) end end
        return not failed
    end
    function manager.destroy()
        manager.clear()
        pcall(function() container:Destroy() end)
    end
    return manager
end
