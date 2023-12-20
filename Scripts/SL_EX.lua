-- -----------------------------------------------------------------------
UpdatePathMap = function(player, hash)
	local song = GAMESTATE:GetCurrentSong()
	local song_dir = song:GetSongDir()
	if song_dir ~= nil and #song_dir ~= 0 then
		local pn = ToEnumShortString(player)
		local pathMap = SL[pn].EXData["pathMap"]
		if pathMap[song_dir] == nil or pathMap[song_dir] ~= hash then
			pathMap[song_dir] = hash
			WriteExFile(player)
		end
	end
end

-- -----------------------------------------------------------------------
-- The EX file is a JSON file that contains two mappings:
--
-- {
--    pathMap = {
--      '<song_dir>': '<song_hash>',
--    },
--    hashMap = {
--      '<song_hash': { .. metadata .. }
--    }
-- }
--
-- The pathMap maps a song directory corresponding to a chart to its song hash
-- The hashMap is a mapping from that hash to the relevant data stored for the event.
--
-- This lets us see our EX score replicated across charts in different packs with the same hash.
local exFilePath = "ex.json"

local TableContainsData = function(t)
	if t == nil then return false end

	for _, _ in pairs(t) do
			return true
	end
	return false
end

-- Takes the EXData loaded in memory and writes it to the local profile.
WriteExFile = function(player)
	local pn = ToEnumShortString(player)
	-- No data to write, return early.
	if (not TableContainsData(SL[pn].EXData["pathMap"]) and
			not TableContainsData(SL[pn].EXData["hashMap"])) then
		return
	end

	local profile_slot = {
		[PLAYER_1] = "ProfileSlot_Player1",
		[PLAYER_2] = "ProfileSlot_Player2"
	}
	
	local dir = PROFILEMAN:GetProfileDir(profile_slot[player])
	-- We require an explicit profile to be loaded.
	if not dir or #dir == 0 then return end

	local path = dir .. exFilePath
	local f = RageFileUtil:CreateRageFile()

	if f:Open(path, 2) then
		f:Write(JsonEncode(SL[pn].EXData))
		f:Close()
	end
	f:destroy()
end

-- EX score is a number like 92.67
local GetPointsForSong = function(maxPoints, exScore)
	local thresholdEx = 50.0
	local percentPoints = 40.0

	-- Helper function to take the logarithm with a specific base.
	local logn = function(x, y)
		return math.log(x) / math.log(y)
	end

	-- The first half (logarithmic portion) of the scoring curve.
	local first = logn(
		math.min(exScore, thresholdEx) + 1,
		math.pow(thresholdEx + 1, 1 / percentPoints)
	)

	-- The second half (exponential portion) of the scoring curve.
	local second = math.pow(
		100 - percentPoints + 1,
		math.max(0, exScore - thresholdEx) / (100 - thresholdEx)
	) - 1

	-- Helper function to round to a specific number of decimal places.
	-- We want 100% EX to actually grant 100% of the points.
	-- We don't want to  lose out on any single points if possible. E.g. If
	-- 100% EX returns a number like 0.9999999999999997 and the chart points is
	-- 6500, then 6500 * 0.9999999999999997 = 6499.99999999999805, where
	-- flooring would give us 6499 which is wrong.
	local roundPlaces = function(x, places)
		local factor = 10 ^ places
		return math.floor(x * factor + 0.5) / factor
	end

	local percent = roundPlaces((first + second) / 100.0, 6)
	return math.floor(maxPoints * percent)
end

-- Generally to be called only once when a profile is loaded.
-- This parses the EX data file and stores it in memory for the song wheel to reference.
ReadExFile = function(player)
	local profile_slot = {
		[PLAYER_1] = "ProfileSlot_Player1",
		[PLAYER_2] = "ProfileSlot_Player2"
	}
	
	local dir = PROFILEMAN:GetProfileDir(profile_slot[player])
	local pn = ToEnumShortString(player)
	-- We require an explicit profile to be loaded.
	if not dir or #dir == 0 then return end

	local path = dir .. exFilePath
	local exData = { 
		["pathMap"] = {},
		["hashMap"] = {},
	}
	if FILEMAN:DoesFileExist(path) then
		local f = RageFileUtil:CreateRageFile()
		local existing = ""
		if f:Open(path, 1) then
			existing = f:Read()
			f:Close()
		end
		f:destroy()
		exData = JsonDecode(existing)
	end
	
	SL[pn].EXData = exData
end

-- Helper function used within UpdateExData() below.
-- Curates all the EX data to be written to the EX file for the played song.
local DataForSong = function(player, prevData)
	local pn = ToEnumShortString(player)

	local steps = GAMESTATE:GetCurrentSteps(player)
	local chartName = steps:GetChartName()

	local year = Year()
	local month = MonthOfYear()+1
	local day = DayOfMonth()

	local judgments = GetExJudgmentCounts(player)
	local ex = CalculateExScore(player)
	local clearType = GetClearType(judgments)
	local date = ("%04d-%02d-%02d"):format(year, month, day)
	
	return {
		["judgments"] = judgments,
		["ex"] = ex * 100,
		["date"] = date,
	}
end

-- Quick function that overwrites EX score entry if the score found is higher than what is found locally
UpdateBoogieExScore = function(player, hash, exscore)
	local pn = ToEnumShortString(player)
	local hashMap = SL[pn].EXData["hashMap"]
	if hashMap[hash] == nil then
		-- New score, just copy things over.
		hashMap[hash] = {
			["judgments"] = {},
			["ex"] = 0,
			["date"] = "",
		}
		
	end
	
	if exscore >= hashMap[hash]["ex"] then
		hashMap[hash]["ex"] = exscore
		
		WriteExFile(player)
	end
end

-- Should be called during ScreenEvaluation to update the EX data loaded.
-- Will also write the contents to the file.
UpdateExData = function(player)
	local pn = ToEnumShortString(player)
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
		
	-- Do the same validation as GrooveStats.
	-- This checks important things like timing windows, addition/removal of arrows, etc.
	local _, valid = ValidForGrooveStats(player)

	-- Require the music rate to be 1.00x.
	local so = GAMESTATE:GetSongOptionsObject("ModsLevel_Song")
	local rate = so:MusicRate()

	-- We also require mines to be on.
	local po = GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred")
	local minesEnabled = not po:NoMines()

	if (GAMESTATE:IsHumanPlayer(player) and
				valid and
				rate == 1.0 and
				minesEnabled and
				not stats:GetFailed()) then
		local hash = SL[pn].Streams.Hash
		local hashMap = SL[pn].EXData["hashMap"]

		local prevData = nil
		if hashMap ~= nil and hashMap[hash] ~= nil then
			prevData = hashMap[hash]
		end

		local data = DataForSong(player, prevData)

		-- Update the pathMap as needed.
		local song = GAMESTATE:GetCurrentSong()
		local song_dir = song:GetSongDir()
		if song_dir ~= nil and #song_dir ~= 0 then
			local pathMap = SL[pn].EXData["pathMap"]
			pathMap[song_dir] = hash
		end
		
		-- Then maybe update the hashMap.
		local updated = false
		if hashMap[hash] == nil then
			-- New score, just copy things over.
			hashMap[hash] = {
				["judgments"] = DeepCopy(data["judgments"]),
				["ex"] = data["ex"],
				["date"] = data["date"],
			}
			updated = true
		else
			if data["ex"] >= hashMap[hash]["ex"] then
				hashMap[hash]["ex"] = data["ex"]
				hashMap[hash]["points"] = data["points"]
				
				if data["ex"] > hashMap[hash]["ex"] then
					-- EX count is strictly better, copy the judgments over.
					hashMap[hash]["judgments"] = DeepCopy(data["judgments"])
					updated = true
				else
					-- EX count is tied.
					-- "Smart" update judgment counts by picking the one with the highest top judgment.
					local better = false
					local keys = { "W0", "W1", "W2", "W3", "W4", "W5", "Miss" }
					for key in ivalues(keys) do
						local prev = hashMap[hash]["judgments"][key]
						local cur = data["judgments"][key]
						-- If both windows are defined, take the greater one.
						-- If current is defined but previous is not, then current is better.
						if (cur ~= nil and prev ~= nil and cur > prev) or (cur ~= nil and prev == nil) then
							better = true
							break
						end
					end

					if better then
						hashMap[hash]["judgments"] = DeepCopy(data["judgments"])
						updated = true
					end
				end
			end	

			if updated then
				hashMap[hash]["date"] = data["date"]
			end
		end

		if updated then
			WriteExFile(player)
		end
		-- This probably doesn't need to be a global message
		if SCREENMAN:GetTopScreen():GetName() == "ScreenEvaluationStage" then MESSAGEMAN:Broadcast("ExDataReady",{player=player}) end
	end
end