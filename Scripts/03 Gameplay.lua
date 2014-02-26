-- various functions for doing things by gametype.
-- some of this previously appeared in 03 SystemDirection.

-- GetComboThresholds()
ComboThresholdTable = {
	dance	=	{ Maintain = "TapNoteScore_W3", Continue = "TapNoteScore_W3" },
	pump	=	{ Maintain = "TapNoteScore_W4", Continue = "TapNoteScore_W4" },
	techno	=	{ Maintain = "TapNoteScore_W3", Continue = "TapNoteScore_W3" }
};

function GetComboThreshold()
	local CurrentGame = string.lower( GAMESTATE:GetCurrentGame():GetName() );
	return ComboThresholdTable[CurrentGame];
end;