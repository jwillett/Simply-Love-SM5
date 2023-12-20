local player = ...

if (SL.Global.GameMode == "Casual" or
		GAMESTATE:IsCourseMode() or
		GAMESTATE:GetCurrentGame():GetName() ~= "dance") then
	return
end

local t = Def.ActorFrame {
	OnCommand=function(self)
		UpdateExData(player)
	end
}

return t