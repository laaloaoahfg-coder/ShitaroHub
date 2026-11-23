-- Exercise the real marker manager and lifecycle with a minimal GUI mock.
local oldEnum,oldVector2,oldUDim,oldUDim2,oldColor3=Enum,Vector2,UDim,UDim2,Color3
Enum={ApplyStrokeMode={Border="Border"}}
Vector2={new=function(x,y) return {X=x,Y=y} end}
UDim={new=function(a,b) return {a,b} end}
UDim2={fromOffset=function(x,y) return {x,y} end,fromScale=function(x,y) return {x,y} end}
Color3={fromRGB=function(r,g,b) return {r,g,b} end}
local obj={};obj.__index=obj
function obj:IsA(kind) return kind==self.ClassName or (kind=="BasePart" and self.ClassName=="Part") end
function obj:FindFirstChild(name) for _,v in ipairs(self.children) do if v.Name==name then return v end end end
function obj:GetChildren() return self.children end
function obj:Destroy()
    self.destroyed=true
    if self.Parent then for i=#self.Parent.children,1,-1 do if self.Parent.children[i]==self then table.remove(self.Parent.children,i) end end end
    self.Parent=nil
end
local function make(class,props,parent)
    local o=setmetatable({ClassName=class,children={},Parent=parent},obj)
    for k,v in pairs(props or {}) do o[k]=v end
    if parent then parent.children[#parent.children+1]=o end
    return o
end
local pg=make("PlayerGui",{Name="PlayerGui"})
local table1=make("Model",{Name="table"})
local pieces=make("Folder",{Name="Pieces"},table1)
local one=make("Part",{Name="Piece1_1",Position={X=1}},pieces)
local two=make("Part",{Name="Piece2_1",Position={X=2}},pieces)
make("Part",{Name="Piece1_13"},pieces);make("Part",{Name="Other"},pieces)
local manager=assert(loadfile("core/checkers_markers.lua"))()(make,pg)
local holder=assert(pg:FindFirstChild("ShitaroCheckersMarkers"))
local function forPiece(piece)
    for _,m in ipairs(holder:GetChildren()) do if m.Adornee==piece then return m end end
end
manager.update(table1,1)
assert(#holder:GetChildren()==2,"only valid pieces get markers")
local m1=assert(forPiece(one));local m2=assert(forPiece(two))
assert(not m1.Active and not m2.Active and m1.AlwaysOnTop,"markers must not consume input")
local ring=assert(m1:FindFirstChild("Ring"));local dot=assert(ring:FindFirstChild("Dot"))
local stroke=assert(ring:FindFirstChild("Outline"))
assert(ring.BackgroundTransparency==1 and not ring.Active and not dot.Active,"hollow inactive ring and dot")
assert(stroke.Color[2]>stroke.Color[1] and dot.BackgroundColor3[2]>dot.BackgroundColor3[1],"side one is green")
assert(m2:FindFirstChild("Ring"):FindFirstChild("Outline").Color[1]>m2:FindFirstChild("Ring"):FindFirstChild("Outline").Color[2],"opponent is red")
one.Position={X=900};manager.update(table1,1)
assert(forPiece(one)==m1 and m1.Adornee.Position.X==900,"same adornment follows moved piece")
two:Destroy();manager.update(table1,1)
assert(m2.destroyed and #holder:GetChildren()==1,"captured or removed piece loses marker")
local replacement=make("Part",{Name="Piece2_1",Position={X=3}},pieces)
manager.update(table1,1);assert(forPiece(replacement) and forPiece(replacement)~=m2,"replacement receives a new marker")
manager.update(table1,2)
assert(m1.destroyed and forPiece(one)~=m1,"changing seat recolors without stale markers")
assert(forPiece(one):FindFirstChild("Ring"):FindFirstChild("Outline").Color[1]>forPiece(one):FindFirstChild("Ring"):FindFirstChild("Outline").Color[2])
manager.update(nil,nil);assert(#holder:GetChildren()==0,"leaving the table removes the markers")
manager.update(table1,1);manager.destroy();assert(holder.destroyed and #pg:GetChildren()==0,"shutdown cleans all objects")
Enum,Vector2,UDim,UDim2,Color3=oldEnum,oldVector2,oldUDim,oldUDim2,oldColor3
io.write("PASS: checkers piece markers follow parts, map sides, ignore input and clean up\n")
