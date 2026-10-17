local pg = game.Players.LocalPlayer.PlayerGui

local LOOKAHEAD = 0.15
local SMOOTH = 0.5
local STALE = 0.1
local MIN_SWITCH = 0.05

local mouseDown, owner = false, nil
local lastSwitch, lastResync = 0, 0

local function angleDiff(a, b)
	return (a - b + 180) % 360 - 180
end

local function setMouse(down, who)
	mouseDown = down
	owner = down and who or nil
	lastSwitch = os.clock()
	if down then
		mouse1press()
	else
		mouse1release()
	end
end

local function hold(who, down)
	local now = os.clock()
	if down then
		if mouseDown and owner ~= who then
			setMouse(false, who)
		elseif not mouseDown and now - lastSwitch >= MIN_SWITCH then
			setMouse(true, who)
		end
	elseif mouseDown and owner == who and now - lastSwitch >= MIN_SWITCH then
		setMouse(false, who)
	end
end

local function letGo()
	if mouseDown then
		setMouse(false)
	end
end

local function getRing()
	return pg:FindFirstChild("RingMinigame")
end

local function getTuning()
	return pg:FindFirstChild("TuningMinigame")
end

local function getMain()
	return pg:FindFirstChild("MainMinigame")
end

local ringClicked = false

task.spawn(function()
	while true do
		local ok, gui = pcall(getRing)

		if ok and gui then
			letGo()

			pcall(function()
				local white = memory_read("float", gui.Ring.Tick.Address + 0xd8)
				local green = memory_read("float", gui.Ring.BullseyeColor.Address + 0xd8)
				local diff = angleDiff(white, green)

				if math.abs(diff) < 5 and not ringClicked then
					ringClicked = true
					mouse1click()
				elseif math.abs(diff) > 20 then
					ringClicked = false
				end
			end)
		else
			ringClicked = false
		end

		task.wait()
	end
end)

local lastBallX, lastBallTime, ballSpeed = nil, nil, 0

local function resetTuning()
	lastBallX, lastBallTime, ballSpeed = nil, nil, 0
end

task.spawn(function()
	while true do
		local ok, gui = pcall(getTuning)

		if ok and gui then
			pcall(function()
				local track = gui.Cont.Track
				local ball = track.Needle.Ball
				local marker = track.Marker

				local ballX = ball.AbsolutePosition.X
				local markerX = marker.AbsolutePosition.X

				if math.abs(ballX) > 1e5 or math.abs(markerX) > 1e5 then
					resetTuning()
					hold("Tuning", false)
					return
				end

				local now = os.clock()

				if lastBallX == nil then
					lastBallX, lastBallTime = ballX, now
				elseif ballX ~= lastBallX then
					local dt = now - lastBallTime
					if dt > 0 then
						ballSpeed = ballSpeed * SMOOTH + ((ballX - lastBallX) / dt) * (1 - SMOOTH)
					end
					lastBallX, lastBallTime = ballX, now
				elseif now - lastBallTime > STALE then
					ballSpeed = 0
				end

				local predicted = ballX + ballSpeed * LOOKAHEAD - markerX
				hold("Tuning", predicted <= 0)
			end)
		else
			resetTuning()
			hold("Tuning", false)
		end

		task.wait()
	end
end)

local lastOffset, lastOffsetTime, offsetSpeed = nil, nil, 0

local function resetMain()
	lastOffset, lastOffsetTime, offsetSpeed = nil, nil, 0
end

task.spawn(function()
	while true do
		local ok, gui = pcall(getMain)

		if ok and gui then
			pcall(function()
				local item = gui.Track.Item
				local left = gui.Track.ProgressZone.LeftLine
				local right = gui.Track.ProgressZone.RightLine

				local middle = left.AbsolutePosition.X + (right.AbsolutePosition.X - left.AbsolutePosition.X) / 2
				local offset = item.AbsolutePosition.X + item.AbsoluteSize.X / 2 - middle
				local now = os.clock()

				if lastOffset == nil then
					lastOffset, lastOffsetTime = offset, now
				elseif offset ~= lastOffset then
					local dt = now - lastOffsetTime
					if dt > 0 then
						offsetSpeed = offsetSpeed * SMOOTH + ((offset - lastOffset) / dt) * (1 - SMOOTH)
					end
					lastOffset, lastOffsetTime = offset, now
				elseif now - lastOffsetTime > STALE then
					offsetSpeed = 0
				end

				local predicted = offset + offsetSpeed * LOOKAHEAD

				if predicted <= 0 and mouseDown and owner == "Main" and offset < -30 and offsetSpeed <= 5
					and now - lastSwitch > 0.35 and now - lastResync > 0.5 then
					lastResync = now
					mouse1release()
					task.wait(0.05)
					mouse1press()
					lastSwitch = os.clock()
				end

				hold("Main", predicted <= 0)
			end)
		else
			resetMain()
			hold("Main", false)
		end

		task.wait()
	end
end)

local lastIdleClick = 0

task.spawn(function()
	while true do
		local _, ring = pcall(getRing)
		local _, tuning = pcall(getTuning)
		local _, main = pcall(getMain)

		if not ring and not tuning and not main then
			letGo()

			if os.clock() - lastIdleClick >= 1 then
				lastIdleClick = os.clock()
				mouse1click()
			end
		end

		task.wait()
	end
end)