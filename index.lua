-- Blackjack 3DS 0.2 ---------------------

white = Color.new(255,255,255)
black = Color.new(0,0,0)
background = Color.new(7,99,36)
buttonFill = Color.new(9,86,32)
buttonText = Color.new(200,200,200)
buttonFillPressed = Color.new(47,117,66)

Screen.waitVblankStart()
Screen.refresh()
Screen.debugPrint(5,5,'Loading...', white, TOP_SCREEN)
Screen.flip()

h,m,s = System.getTime()
seed = s + m * 60 + h * 3600
math.randomseed (seed)

oldPad = Controls.read()
oldX, oldY = Controls.readTouch()

cardSprites = Screen.loadImage(System.currentDirectory().."/images/cardsprites.png")
cardSpritesDim = Screen.loadImage(System.currentDirectory().."/images/cardspritesdim.png")
cardBack = Screen.loadImage(System.currentDirectory().."/images/cardbackblue.png")

aButton = Screen.loadImage(System.currentDirectory().."/images/a.png")
bButton = Screen.loadImage(System.currentDirectory().."/images/b.png")
xButton = Screen.loadImage(System.currentDirectory().."/images/x.png")
yButton = Screen.loadImage(System.currentDirectory().."/images/y.png")
lButton = Screen.loadImage(System.currentDirectory().."/images/l.png")
rButton = Screen.loadImage(System.currentDirectory().."/images/r.png")
startButton = Screen.loadImage(System.currentDirectory().."/images/start.png")
title = Screen.loadImage(System.currentDirectory().."/images/title.png")

if System.doesFileExist(System.currentDirectory().."/sound/bgm.ogg") then
	bgm = Sound.openOgg(System.currentDirectory().."/sound/bgm.ogg", false)
else
	bgm = nil
end
dealCardSFX = Sound.openWav(System.currentDirectory().."/sound/dealcard.wav", false)
flipCardSFX = Sound.openWav(System.currentDirectory().."/sound/flipcard.wav", false)

suiteYIndices = { s=0, c=98, h=196, d=294 }
suiteXIndices = { ['A']=0, [2]=73, [3]=(73*2), [4]=(73*3), [5]=(73*4), [6]=(73*5), [7]=(73*6), [8]=(73*7), [9]=(73*8), [10]=(73*9), ['J']=(73*10), ['Q']=(73*11), ['K']=(73*12) }

cards = {2,3,4,5,6,7,8,9,10,'J','Q','K','A'}
suites = {'c','d','s','h'}

playerMoney = 1000

dealerHand = nil
playerHands = {}
playerHandIndex = 1
playerBet = 100
playerHasInsurance = false
roundResults = {}

betIncrement = 10
minBet = 10
maxBet = 1000

currentState = 'menu'
nextState = 'menu'

dealerAnimationCounter = 0

fullLengthCardSpacing = 75
singleHandCollapseCardSpacing = 35
splitHandCardSpacing = 15

bgmEnabled = true
sfxEnabled = true
offerInsurance = true
dealerHitsSoft17 = false

bgmStarted = false


--- Basic Functions --------------------------------------------------------------------------

local function shuffleTable(t)
  local rand = math.random 
  local iterations = #t
  local j
  
  for i = iterations, 2, -1 do
      j = rand(i)
      t[i], t[j] = t[j], t[i]
  end
end

function getTableSize (t)
	local size = 0
	for key,value in pairs(t) do
		size = size + 1
	end
	return size
end

function splitActive ()
	return (getTableSize(playerHands) == 2)
end

function getFreshDeck ()
	local deck = {}
	for i=1,4,1 do
		for key,value in ipairs(cards) do 
			table.insert(deck, {value, suites[i]})
		end
	end
	shuffleTable(deck)
	return deck
end

function getHandValue (hand)
	local sum = 0
	local numAces = 0
	local soft = false
	for key, value in ipairs(hand) do
		value = value[1]
		if (value == 'J') or (value == 'Q') or (value == 'K') then
			sum = sum + 10
		elseif (value == 'A') then
			sum = sum + 1
			numAces = numAces + 1
		else 
			sum = sum + value
		end
	end

	if (numAces > 0) and (sum < 12) then
		sum = sum + 10 -- convert an ace from 1 to 11
		soft = true
	end

	return sum, soft
end

function renderHand (startX, startY, cards, spacing, spriteSheet)
	spriteSheet = spriteSheet or cardSprites
	for key,value in ipairs(cards) do
		Screen.drawPartialImage(startX + (key-1)*spacing, startY, suiteXIndices[value[1]], suiteYIndices[value[2]], 72, 97, spriteSheet, TOP_SCREEN)
	end
end

function dealerHandRenderer(startX, startY, hideCard)
	local hideCard = hideCard or false
	if (dealerHand.getSize() > 5) then
		renderHand(startX, startY, dealerHand.getCards(), singleHandCollapseCardSpacing)
	elseif (hideCard == true) then
		Screen.drawPartialImage(startX, startY, suiteXIndices[dealerHand.getCards()[1][1]], suiteYIndices[dealerHand.getCards()[1][2]], 72, 97, cardSprites, TOP_SCREEN)
		Screen.drawImage(startX + fullLengthCardSpacing, startY, cardBack, TOP_SCREEN )
	else
		renderHand(startX, startY, dealerHand.getCards(), fullLengthCardSpacing)
	end
end

function playerHandRenderer(startX, startY, hand, spriteSheet)
	if splitActive() then -- split active
		renderHand(startX, startY, hand.getCards(), splitHandCardSpacing, spriteSheet)
	else
		if (hand.getSize() > 5) then
			renderHand(startX, startY, hand.getCards(), singleHandCollapseCardSpacing)
		else
			renderHand(startX, startY, hand.getCards(), fullLengthCardSpacing)
		end
	end
end

function addCardToHand (hand)
	local index = math.random(1, getTableSize(deck))
	table.insert(hand, deck[index])
	return hand
end

function buttonPressed (key)
	return ((Controls.check(pad,key)) and not (Controls.check(oldPad,key)))
end

function renderDealerPlayerLine ()
	Screen.drawLine(0, 399, 119, 119, white, TOP_SCREEN)
	Screen.drawLine(0, 399, 120, 120, white, TOP_SCREEN)
end

function renderSplitLine ()
	Screen.drawLine(199, 199, 119, 239, white, TOP_SCREEN)
	Screen.drawLine(200, 200, 119, 239, white, TOP_SCREEN)
end

function dealerCanReceiveCard ()
	if not(playerHands[1].getResult() == 'Surrendered') then
		if splitActive() then
			if (playerHands[1].handStatus() == 'valid') and (playerHands[2].handStatus() == 'valid') then
				local value = dealerHand.getValue()
				if value < 17 then
					return true
				elseif dealerHitsSoft17 and dealerHand.soft17() then
					return true
				end
			end
		else
			if (playerHands[1].handStatus() == 'valid') then
				local value = dealerHand.getValue()
				if value < 17 then
					return true
				elseif dealerHitsSoft17 and dealerHand.soft17() then
					return true
				end
			end
		end
	end
	return false
end

function moneyWagered ()
	local wagered = 0
	for key,value in pairs(playerHands) do
		wagered = wagered + value.getBet()
	end
	if (playerHasInsurance == true) and not(dealerHand.handStatus() == 'blackjack') then
		wagered = wagered + math.floor(playerBet / 2.0)
	end
	return wagered
end

function withinCoords (x, y, x1, x2, y1, y2)
	if (y >= y1) and (y <= y2) then
		if (x >= x1) and (x <= x2) then
			return true
		end
	end
	return false
end

function menuTrigger (x, y, x1, x2, y1, y2, returnString) 
	if withinCoords(x, y, x1, x2, y1, y2) and not _G[returnString..'Trigger'] then
		_G[returnString..'Trigger'] = true
	elseif x == 0 and y == 0 and _G[returnString..'Trigger'] then
		_G[returnString..'Trigger'] = false
		return returnString
	elseif not withinCoords(x, y, x1, x2, y1, y2) then
		_G[returnString..'Trigger'] = false
	end
	return false
end

function instantMenuTrigger (x, y, x1, x2, y1, y2, returnString) 
	if withinCoords(x, y, x1, x2, y1, y2) then
		return returnString
	end
	return false
end

function buttonColor (x, y, x1, x2, y1, y2)
	if withinCoords(x, y, x1, x2, y1, y2) then
		return buttonFillPressed
	else
		return buttonFill
	end
end

function playSFX (effect)
	if sfxEnabled then
		Sound.play(_G[effect..'SFX'],NO_LOOP,0x0A)
	end
end

function booleanToNumber (boolean)
	if boolean then
		return 1
	else
		return 0
	end
end

function numberToBoolean (number)
	if tonumber(number) > 0 then
		return true
	else
		return false
	end
end

function loadFiles ()
	if System.doesFileExist(System.currentDirectory().."/settings.file") then
		local fileStream = io.open(System.currentDirectory().."/settings.file",FREAD)
		io.close(fileStream)
		fileStream = 0
		fileStream = io.open(System.currentDirectory().."/settings.file",FREAD)
		local fileDealerHitsSoft17 = io.read(fileStream, 17, 1)
		local fileOfferInsurance = io.read(fileStream, 34, 1)
		local fileBgmEnabled = io.read(fileStream, 47, 1)
		local fileSfxEnabled = io.read(fileStream, 60, 1)
		io.close(fileStream)
		dealerHitsSoft17 = numberToBoolean(fileDealerHitsSoft17)
		offerInsurance = numberToBoolean(fileOfferInsurance)
		bgmEnabled = numberToBoolean(fileBgmEnabled)
		sfxEnabled = numberToBoolean(fileSfxEnabled)
	else
		writeSettingsFile()
	end

	if System.doesFileExist(System.currentDirectory().."/money.file") then
		local fileStream = io.open(System.currentDirectory().."/money.file",FREAD)
		-- local fileSize = io.size(fileStream)
		-- if fileSize > 10 then
		-- 	error("money.file size error: "..fileSize.." EXIT AND RESTART")
		-- end
		local fileMoney = io.read(fileStream,0,10)
		io.close(fileStream)
		if tonumber(fileMoney, 10) == nil then -- money file is corrupt or some shit
			error("money file corrupt: "..fileMoney.." EXIT AND RESTART")
		else
			playerMoney = tonumber(fileMoney, 10)
		end
	else
		writeMoneyFile()
	end
end

function writeMoneyFile ()
	local fileStream = nil
	if System.doesFileExist(System.currentDirectory().."/money,file") then
		fileStream = io.open(System.currentDirectory().."/money.file",FWRITE)
	else
		fileStream = io.open(System.currentDirectory().."/money.file",FCREATE)
	end
	local size = string.len(tostring(playerMoney))
	io.write(fileStream, 0, '0000000000', 10) 
	io.write(fileStream, 10-size, tostring(playerMoney), size) 
	io.close(fileStream)
end

function writeSettingsFile ()
	local fileStream = nil
	if System.doesFileExist(System.currentDirectory().."/settings.file") then
		fileStream = io.open(System.currentDirectory().."/settings.file",FWRITE)
	else
		fileStream = io.open(System.currentDirectory().."/settings.file",FCREATE)
	end
	local dealerHitsSoft17String = 'dealerHitsSoft17:'..booleanToNumber(dealerHitsSoft17)
	local offerInsuranceString = ' offerInsurance:'..booleanToNumber(offerInsurance)
	local bgmEnabledString = ' bgmEnabled:'..booleanToNumber(bgmEnabled)
	local sfxEnabledString = ' sfxEnabled:'..booleanToNumber(sfxEnabled)
	local stringLength = string.len(dealerHitsSoft17String..offerInsuranceString..bgmEnabledString..sfxEnabledString)
	io.write(fileStream,0,dealerHitsSoft17String..offerInsuranceString..bgmEnabledString..sfxEnabledString, stringLength)
	io.close(fileStream)
end




------------------------------------------------------------------------------------

function newHand (initialCards, bet)
	local self = { cards = initialCards, bet = bet, doubled = false, result = nil }
	local getBet = function ()
						return math.floor(self.bet)
					end
	local doubleDown = function ()
						if (self.doubled == false) then
							self.bet = self.bet * 2.0
							self.doubled = true
							addCardToHand(self.cards)
						end
					end
	local getDoubledDown = function ()
						return self.doubled
					end
	local getCards = function ()
						return self.cards
					end
	local getValue = function ()
						return getHandValue(self.cards)
					end
	local dealCard = function ()
						return addCardToHand(self.cards)
					end
	local getSize = function ()
						return getTableSize(self.cards)
					end
	local canSplit = function ()
						if (getSize() == 2) then
							local firstCardValue = getHandValue({ self.cards[1] })
							local secondCardValue = getHandValue({ self.cards[2] })
							if (firstCardValue == secondCardValue) then
								return true
							end
						end	
						return false
					end
	local handStatus = function ()
	                        local value = getValue()
							if (value > 21) then
								return 'bust'
							elseif (getSize() == 2) and (value == 21) then
								return 'blackjack'
							else
								return 'valid'
							end
						end
	local setResult = function (r)
						self.result = r
					end
	local getResult = function ()
						return self.result
					end
	local soft17 = function ()
						local value = 0
						local soft = false
						value, soft = getValue()
						if value == 17 and soft then
							return true
						end
						return false
					end

	return {
		getCards = getCards,
		getValue = getValue,
		dealCard = dealCard,
		getSize = getSize,
		canSplit = canSplit,
		handStatus = handStatus,
		getBet = getBet,
		doubleDown = doubleDown,
		getDoubledDown = getDoubledDown,
		setResult = setResult,
		getResult = getResult,
		soft17 = soft17
	}
end

---------------------------------------------------------------------------

function drawAndCheckMenu ()
	if currentState == 'menu' then
		Screen.fillRect(5,314, 25, 85, buttonColor(xTouch, yTouch, 5, 314, 25, 85), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 25, 85, black, BOTTOM_SCREEN )
		Screen.drawImage(8,28, aButton, BOTTOM_SCREEN)
		Screen.debugPrint(118,50, "New Hand", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 25, 85, 'newHand') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,314, 90, 150, buttonColor(xTouch, yTouch, 5, 314, 90, 150), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 90, 150, black, BOTTOM_SCREEN )
		Screen.drawImage(8,93, xButton, BOTTOM_SCREEN)
		Screen.debugPrint(128,115, "Options", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 90, 150, 'options') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,314, 155, 215, buttonColor(xTouch, yTouch, 5, 314, 155, 215), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(8,158, startButton, BOTTOM_SCREEN)
		Screen.debugPrint(142,180, "Exit", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 155, 215, 'exit') or trigger
		if trigger then return trigger end

	elseif currentState == 'options' then
		Screen.fillRect(5,314, 25, 150, buttonFill, BOTTOM_SCREEN )

		--- Deck ----
		if not dealerHitsSoft17 then
			Screen.fillRect(10,160, 30, 50, buttonFillPressed, BOTTOM_SCREEN )
			Screen.debugPrint(15,35, "Stands Soft 17", white, BOTTOM_SCREEN)
		else
			Screen.debugPrint(15,35, "Stands Soft 17", buttonText, BOTTOM_SCREEN)
		end
		Screen.fillEmptyRect(10,160, 30, 50, black, BOTTOM_SCREEN )
		-- local trigger = instantMenuTrigger(xTouch, yTouch, 10, 160, 30, 50, 'singleDeck') or trigger
		-- if trigger then return trigger end

		if dealerHitsSoft17 then
			Screen.fillRect(160,309, 30, 50, buttonFillPressed, BOTTOM_SCREEN )
			Screen.debugPrint(165,35, "Hits Soft 17", white, BOTTOM_SCREEN)
		else
			Screen.debugPrint(165,35, "Hits Soft 17", buttonText, BOTTOM_SCREEN)
		end
		Screen.fillEmptyRect(160,309, 30, 50, black, BOTTOM_SCREEN )
		-- local trigger = instantMenuTrigger(xTouch, yTouch, 160, 309, 30, 50, 'infinteDeck') or trigger
		-- if trigger then return trigger end


		--- Insurance ---
		if offerInsurance then
			Screen.fillRect(10,160, 55, 75, buttonFillPressed, BOTTOM_SCREEN )
			Screen.debugPrint(15,60, "Insurance", white, BOTTOM_SCREEN)
		else
			Screen.debugPrint(15,60, "Insurance", buttonText, BOTTOM_SCREEN)
		end
		Screen.fillEmptyRect(10,160, 55, 75, black, BOTTOM_SCREEN )
		-- local trigger = instantMenuTrigger(xTouch, yTouch, 10, 160, 55, 75, 'insurance') or trigger
		-- if trigger then return trigger end

		if not offerInsurance then
			Screen.fillRect(160,309, 55, 75, buttonFillPressed, BOTTOM_SCREEN )
			Screen.debugPrint(165,60, "No Insurance", white, BOTTOM_SCREEN)
		else
			Screen.debugPrint(165,60, "No Insurance", buttonText, BOTTOM_SCREEN)
		end
		Screen.fillEmptyRect(160,309, 55, 75, black, BOTTOM_SCREEN )
		-- local trigger = instantMenuTrigger(xTouch, yTouch, 160, 309, 55, 75, 'noInsurance') or trigger
		-- if trigger then return trigger end


		--- BGM ----
		if bgmEnabled then
			Screen.fillRect(10,160, 80, 100, buttonFillPressed, BOTTOM_SCREEN )
			Screen.debugPrint(15,85, "BGM On", white, BOTTOM_SCREEN)
		else
			Screen.debugPrint(15,85, "BGM On", buttonText, BOTTOM_SCREEN)
		end
		Screen.fillEmptyRect(10,160, 80, 100, black, BOTTOM_SCREEN )
		-- local trigger = instantMenuTrigger(xTouch, yTouch, 10, 160, 80, 100, 'bgmOn') or trigger
		-- if trigger then return trigger end

		if not bgmEnabled then
			Screen.fillRect(160, 309, 80, 100, buttonFillPressed, BOTTOM_SCREEN )
			Screen.debugPrint(165,85, "BGM Off", white, BOTTOM_SCREEN)
		else
			Screen.debugPrint(165,85, "BGM Off", buttonText, BOTTOM_SCREEN)
		end
		Screen.fillEmptyRect(160, 309, 80, 100, black, BOTTOM_SCREEN )
		-- local trigger = instantMenuTrigger(xTouch, yTouch, 160, 309, 80, 100, 'bgmOff') or trigger
		-- if trigger then return trigger end


		--- SFX -----
		if sfxEnabled then
			Screen.fillRect(10,160, 105, 125, buttonFillPressed, BOTTOM_SCREEN )
			Screen.debugPrint(15,110, "SFX On", white, BOTTOM_SCREEN)
		else
			Screen.debugPrint(15,110, "SFX On", buttonText, BOTTOM_SCREEN)
		end
		Screen.fillEmptyRect(10,160, 105, 125, black, BOTTOM_SCREEN )
		-- local trigger = instantMenuTrigger(xTouch, yTouch, 10, 160, 105, 125, 'sfxOn') or trigger
		-- if trigger then return trigger end

		if not sfxEnabled then
			Screen.fillRect(160,309, 105, 125, buttonFillPressed, BOTTOM_SCREEN )
			Screen.debugPrint(165,110, "SFX Off", white, BOTTOM_SCREEN)
		else
			Screen.debugPrint(165,110, "SFX Off", buttonText, BOTTOM_SCREEN)
		end
		Screen.fillEmptyRect(160,309, 105, 125, black, BOTTOM_SCREEN )
		-- local trigger = instantMenuTrigger(xTouch, yTouch, 160, 309, 105, 125, 'sfxOff') or trigger
		-- if trigger then return trigger end

		--- Deck Style ----
		Screen.debugPrint(10,133, "Deck Style: Next Release :)", buttonText, BOTTOM_SCREEN)


		Screen.fillRect(5,314, 155, 215, buttonColor(xTouch, yTouch, 5, 314, 155, 215), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(8,158, bButton, BOTTOM_SCREEN)
		Screen.debugPrint(142,180, "Back", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 155, 215, 'backToMenu') or trigger
		if trigger then return trigger end

		local trigger = instantMenuTrigger(xTouch, yTouch, 10, 160, 30, 50, 'dealerStandsSoft17') or trigger
		local trigger = instantMenuTrigger(xTouch, yTouch, 160, 309, 30, 50, 'dealerHitsSoft17') or trigger
		local trigger = instantMenuTrigger(xTouch, yTouch, 10, 160, 55, 75, 'insurance') or trigger
		local trigger = instantMenuTrigger(xTouch, yTouch, 160, 309, 55, 75, 'noInsurance') or trigger
		local trigger = instantMenuTrigger(xTouch, yTouch, 10, 160, 80, 100, 'bgmOn') or trigger
		local trigger = instantMenuTrigger(xTouch, yTouch, 160, 309, 80, 100, 'bgmOff') or trigger
		local trigger = instantMenuTrigger(xTouch, yTouch, 10, 160, 105, 125, 'sfxOn') or trigger
		local trigger = instantMenuTrigger(xTouch, yTouch, 160, 309, 105, 125, 'sfxOff') or trigger
		if trigger then return trigger end

	elseif currentState == 'playerBet' then
		Screen.fillRect(5,210, 25, 85, buttonColor(xTouch, yTouch, 5, 210, 25, 85), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,210, 25, 85, black, BOTTOM_SCREEN )
		Screen.drawImage(8,28, aButton, BOTTOM_SCREEN)
		Screen.debugPrint(65,50, "Bet $"..playerBet, buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 210, 25, 85, 'bet') or trigger
		if trigger then return trigger end

		Screen.fillRect(214,314, 25, 55, buttonColor(xTouch, yTouch, 214, 314, 25, 55), BOTTOM_SCREEN )
		Screen.fillEmptyRect(214,314, 25, 55, black, BOTTOM_SCREEN )
		Screen.drawImage(217,28, rButton, BOTTOM_SCREEN)
		Screen.debugPrint(258,35, "+", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 214, 314, 25, 55, 'plus') or trigger
		if trigger then return trigger end

		Screen.fillRect(214,314, 55, 85, buttonColor(xTouch, yTouch, 214, 314, 55, 85), BOTTOM_SCREEN )
		Screen.fillEmptyRect(214,314, 55, 85, black, BOTTOM_SCREEN )
		Screen.drawImage(217,58, lButton, BOTTOM_SCREEN)
		Screen.debugPrint(258,65, "-", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 214, 314, 55, 85, 'minus') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,105, 90, 150, buttonColor(xTouch, yTouch, 5, 105, 90, 150), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,105, 90, 150, black, BOTTOM_SCREEN )
		Screen.debugPrint(35,115, "$50", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 105, 90, 150, 'bet50') or trigger
		if trigger then return trigger end

		Screen.fillRect(109,210, 90, 150, buttonColor(xTouch, yTouch, 109, 210, 90, 150), BOTTOM_SCREEN )
		Screen.fillEmptyRect(109,210, 90, 150, black, BOTTOM_SCREEN )
		Screen.debugPrint(135,115, "$100", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 109, 210, 90, 150, 'bet100') or trigger
		if trigger then return trigger end

		Screen.fillRect(214,314, 90, 150, buttonColor(xTouch, yTouch, 214, 314, 90, 150), BOTTOM_SCREEN )
		Screen.fillEmptyRect(214,314, 90, 150, black, BOTTOM_SCREEN )
		Screen.debugPrint(238,115, "$500", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 214, 314, 90, 150, 'bet500') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,314, 155, 215, buttonColor(xTouch, yTouch, 5, 314, 155, 215), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(8,158, bButton, BOTTOM_SCREEN)
		Screen.debugPrint(139,180, "Back", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 155, 215, 'backToMenu') or trigger
		if trigger then return trigger end

	elseif currentState == 'offerInsurance' then
		Screen.fillRect(5,314, 25, 85, buttonColor(xTouch, yTouch, 5, 314, 25, 85), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 25, 85, black, BOTTOM_SCREEN )
		Screen.drawImage(8,28, bButton, BOTTOM_SCREEN)
		Screen.debugPrint(80,50, "Decline Insurance", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 25, 85, 'skipInsurance') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,314, 90, 150, buttonColor(xTouch, yTouch, 5, 314, 90, 150), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 90, 150, black, BOTTOM_SCREEN )
		Screen.drawImage(8,93, xButton, BOTTOM_SCREEN)
		Screen.debugPrint(70,115, "Buy Insurance ($"..math.floor(playerBet / 2.0)..")", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 90, 150, 'buyInsurance') or trigger
		if trigger then return trigger end

	elseif currentState == 'playerTurn' then
		Screen.fillRect(5,314, 25, 85, buttonColor(xTouch, yTouch, 5, 314, 25, 85), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 25, 85, black, BOTTOM_SCREEN )
		Screen.drawImage(8,28, aButton, BOTTOM_SCREEN)
		Screen.debugPrint(147,50, "Hit", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 25, 85, 'hit') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,314, 90, 150, buttonColor(xTouch, yTouch, 5, 314, 90, 150), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 90, 150, black, BOTTOM_SCREEN )
		Screen.drawImage(8,93, bButton, BOTTOM_SCREEN)
		Screen.debugPrint(135,115, "Stand", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 90, 150, 'stand') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,105, 155, 215, buttonColor(xTouch, yTouch, 5, 105, 155, 215), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,105, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(8,158, xButton, BOTTOM_SCREEN)
		Screen.debugPrint(27,180, "Double", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 105, 155, 215, 'double') or trigger
		if trigger then return trigger end

		Screen.fillRect(109,210, 155, 215, buttonColor(xTouch, yTouch, 109, 210, 155, 215), BOTTOM_SCREEN )
		Screen.fillEmptyRect(109,210, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(112,158, yButton, BOTTOM_SCREEN)
		Screen.debugPrint(114,180, "Surrender", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 109, 210, 155, 215, 'surrender') or trigger
		if trigger then return trigger end

		Screen.fillRect(214,314, 155, 215, buttonColor(xTouch, yTouch, 214, 314, 155, 215), BOTTOM_SCREEN )
		Screen.fillEmptyRect(214,314, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(217,158, rButton, BOTTOM_SCREEN)
		Screen.debugPrint(243,180, "Split", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 214, 314, 155, 215, 'split') or trigger
		if trigger then return trigger end

	elseif currentState == 'gameOver' then
		Screen.fillRect(5,314, 155, 215, buttonColor(xTouch, yTouch, 5, 314, 155, 215), BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(8,158, xButton, BOTTOM_SCREEN)
		Screen.debugPrint(100,180, "New Game", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 155, 215, 'restart') or trigger
		if trigger then return trigger end

	end
	-- Screen.drawLine(159,159,0,239, white, BOTTOM_SCREEN)
	-- Screen.drawLine(160,160,0,239, white, BOTTOM_SCREEN)
	return nil
end



---------------------------------------------------------------------------

loadFiles()

Sound.init()

if bgmEnabled then
	Sound.play(bgm,LOOP,0x08,0x09)
	bgmStarted = true
end

moneyWriten = false

deck = getFreshDeck()

---------------------------------------------------------------------------

while true do
	Screen.waitVblankStart()

	pad = Controls.read()
	xTouch, yTouch = Controls.readTouch()
	Screen.refresh()
	Screen.clear(TOP_SCREEN)
	Screen.clear(BOTTOM_SCREEN)
	
	Screen.fillRect(0, 399, 0, 239, background, TOP_SCREEN)
	Screen.fillRect(0, 319, 0, 239, background, BOTTOM_SCREEN)

	if playerBet > playerMoney then playerBet = playerMoney end
	menuResponse = drawAndCheckMenu()

	Screen.debugPrint(143,225, "Blackjack 3DS v0.2", white, BOTTOM_SCREEN)
	-- Screen.debugPrint(5,225, "d:"..debug, white, BOTTOM_SCREEN)
	
	if (currentState == 'menu') then
		if moneyWriten == false then
			writeMoneyFile()
			moneyWriten = true
		end


		if dealerHand then
			if (playerMoney > oldPlayerMoney) then
				Screen.debugPrint(5,5, "Cash: $"..playerMoney.." (+"..(playerMoney - oldPlayerMoney)..")", white, BOTTOM_SCREEN)
			else
				Screen.debugPrint(5,5, "Cash: $"..playerMoney.." ("..(playerMoney - oldPlayerMoney)..")", white, BOTTOM_SCREEN)
			end
			-- Screen.debugPrint(5,25, table.concat(roundResults), white, BOTTOM_SCREEN)
			renderDealerPlayerLine()
			dealerHandValue = dealerHand.getValue()
			Screen.debugPrint(10,5,"Dealer: "..dealerHandValue,white,TOP_SCREEN)
			dealerHandRenderer(13, 17)
			for key, value in pairs(playerHands) do
				Screen.debugPrint(10+(200*(key-1)),126,value.getValue()..": $"..value.getBet().." ("..value.getResult()..")",white,TOP_SCREEN)
				playerHandRenderer(13+(200*(key-1)), 138, value)
			end

		else
			Screen.drawImage(0,0, title, TOP_SCREEN)
			Screen.debugPrint(5,5, "Cash: $"..playerMoney, white, BOTTOM_SCREEN)
		end


		if ((menuResponse == 'newHand') or buttonPressed(KEY_A)) and (playerMoney >= minBet) then
			nextState = 'playerBet'
		end

		if (menuResponse == 'options') or buttonPressed(KEY_X) then
			nextState = 'options'
		end

		if (menuResponse == 'exit') or buttonPressed(KEY_START) then
			Sound.close(bgm)
			Sound.term()
			System.exit()
		end
		
	elseif (currentState == 'options') then
		if dealerHand then
			-- Screen.debugPrint(5,25, table.concat(roundResults), white, BOTTOM_SCREEN)
			renderDealerPlayerLine()
			dealerHandValue = dealerHand.getValue()
			Screen.debugPrint(10,5,"Dealer: "..dealerHandValue,white,TOP_SCREEN)
			dealerHandRenderer(13, 17)
			for key, value in pairs(playerHands) do
				Screen.debugPrint(10+(200*(key-1)),126,value.getValue()..": $"..value.getBet().." ("..value.getResult()..")",white,TOP_SCREEN)
				playerHandRenderer(13+(200*(key-1)), 138, value)
			end
		else
			Screen.drawImage(0,0, title, TOP_SCREEN)
		end

		Screen.debugPrint(5,5, "Options", white, BOTTOM_SCREEN)

		if (menuResponse == 'dealerStandsSoft17') then dealerHitsSoft17 = false end
		if (menuResponse == 'dealerHitsSoft17') then  dealerHitsSoft17 = true end
		if (menuResponse == 'insurance') then offerInsurance = true end
		if (menuResponse == 'noInsurance') then offerInsurance = false end
		if (menuResponse == 'bgmOn') then
			bgmEnabled = true
			if not bgmStarted then
				Sound.play(bgm,LOOP,0x08,0x09)
				bgmStarted = true
			elseif not Sound.isPlaying(bgm) then
				Sound.resume(bgm)
			end
		end
		if (menuResponse == 'bgmOff') then
			bgmEnabled = false
			if bgmStarted then Sound.pause(bgm) end
		end
		if (menuResponse == 'sfxOn') then sfxEnabled = true end
		if (menuResponse == 'sfxOff') then sfxEnabled = false end

		if (menuResponse == 'backToMenu') or (buttonPressed(KEY_B)) then
			writeSettingsFile()
			nextState = 'menu'
		end
		
	elseif (currentState == 'playerBet') then
		Screen.debugPrint(5,5, "Cash: $"..playerMoney, white, BOTTOM_SCREEN)
		renderDealerPlayerLine()

	  	if (menuResponse == 'bet') or buttonPressed(KEY_A) then
			nextState = 'turnStart'
		end

	  	if (menuResponse == 'plus') or buttonPressed(KEY_R) then
	  		if (playerBet < maxBet) and ((playerBet + betIncrement) <= playerMoney) then
	  			playerBet = playerBet + betIncrement
	  		end
		end

	  	if (menuResponse == 'minus') or buttonPressed(KEY_L) then
	  		if playerBet > minBet then
	  			playerBet = playerBet - betIncrement
	  		end
		end

		if (menuResponse == 'bet50') then
			if playerMoney >= 50 then
				playerBet = 50
			end
		end

		if (menuResponse == 'bet100') then
			if playerMoney >= 100 then
				playerBet = 100
			end
		end

		if (menuResponse == 'bet500') then
			if playerMoney >= 500 then
				playerBet = 500
			end
		end

		if (menuResponse == 'backToMenu') or (buttonPressed(KEY_B)) then
			dealerHand = nil
			nextState = 'menu'
		end

	elseif (currentState == 'turnStart') then
		Screen.debugPrint(5,5, "Cash: $"..(playerMoney - moneyWagered()), white, BOTTOM_SCREEN)
		
		deck = getFreshDeck()
		
		dealerHand = newHand({})
		dealerHand.dealCard()
		dealerHand.dealCard()
	
		oldPlayerMoney = playerMoney
		playerHasInsurance = false
		playerDoubledDown = false
		playerHands = {}
		playerHandIndex = 1
		table.insert(playerHands, newHand({}, playerBet))
		playerHands[1].dealCard()
		playerHands[1].dealCard()

		playSFX('dealCard')

		roundResults = {}
		
		if (dealerHand.getCards()[1][1] == 'A') and ((playerMoney - (playerBet / 2.0)) > 0) and offerInsurance then
			nextState = 'offerInsurance'
		elseif (playerHands[1].handStatus() == 'blackjack') then
			nextState = 'dealerTurn'
			playSFX('flipCard')
		else
			nextState = 'dealerPeek'
		end
		
	elseif (currentState == 'offerInsurance') then
		Screen.debugPrint(5,5, "Cash: $"..(playerMoney - moneyWagered()), white, BOTTOM_SCREEN)

		renderDealerPlayerLine()
	
		Screen.debugPrint(10,5,"Dealer",white,TOP_SCREEN)
		dealerHandRenderer(13, 17, true)
		
		playerHandValue = playerHands[1].getValue()
		Screen.debugPrint(10,126,playerHandValue..": $"..playerHands[1].getBet(),white,TOP_SCREEN)
		playerHandRenderer(13, 138, playerHands[1])

		-- Screen.debugPrint(5,45, "X to buy insurance for $"..math.floor(playerBet / 2.0), white, BOTTOM_SCREEN)
		if (menuResponse == 'buyInsurance') or buttonPressed(KEY_X) then
			playerHasInsurance = true
			if (playerHands[1].handStatus() == 'blackjack') then
				nextState = 'dealerTurn'
				playSFX('flipCard')
			else
				nextState = 'dealerPeek'
			end
		end

		-- Screen.debugPrint(5,25, "A to continue", white, BOTTOM_SCREEN)
		if (menuResponse == 'skipInsurance') or buttonPressed(KEY_B) then
			if (playerHands[1].handStatus() == 'blackjack') then
				nextState = 'dealerTurn'
				playSFX('flipCard')
			else
				nextState = 'dealerPeek'
			end
		end

	elseif (currentState == 'dealerPeek') then
		Screen.debugPrint(5,5, "Cash: $"..(playerMoney - moneyWagered()), white, BOTTOM_SCREEN)
		renderDealerPlayerLine()
		Screen.debugPrint(10,5,"Dealer",white,TOP_SCREEN)
		dealerHandRenderer(13, 17, true)
		playerHandValue = playerHands[1].getValue()
		Screen.debugPrint(10,126,playerHandValue..": $"..playerHands[1].getBet(),white,TOP_SCREEN)
		playerHandRenderer(13, 138, playerHands[1])




		if (dealerHand.handStatus() == 'blackjack') then
			nextState = 'dealerTurn'
			playSFX('flipCard')
		else
			nextState = 'playerTurn'
		end

	elseif (currentState == 'playerTurn') then
		Screen.debugPrint(5,5, "Cash: $"..(playerMoney - moneyWagered()), white, BOTTOM_SCREEN)
		renderDealerPlayerLine()
		Screen.debugPrint(10,5,"Dealer",white,TOP_SCREEN)
		dealerHandRenderer(13, 17, true)
		for key, value in pairs(playerHands) do
			Screen.debugPrint(10+(200*(key-1)),126,value.getValue()..": $"..value.getBet(),white,TOP_SCREEN)
			if (key == playerHandIndex) and splitActive() then
				playerHandRenderer(13+(200*(key-1)), 138, value)
			else
				playerHandRenderer(13+(200*(key-1)), 138, value, cardSpritesDim)
			end
		end

		local currentHand = playerHands[playerHandIndex]
		local playerHandValue = currentHand.getValue()
		
		if (playerHandValue > 21) or (playerHandValue == 21) or ((currentHand.getDoubledDown() == true) and (currentHand.getSize() > 2)) then
			if (playerHandIndex == 1) and splitActive() then -- split active
				playerHandIndex = 2
			else
				nextState = 'dealerTurn'
				playSFX('flipCard')
			end
		end
		
		-- Screen.debugPrint(5,25, "A to hit", white, BOTTOM_SCREEN)
		-- Screen.debugPrint(5,45, "B to stand", white, BOTTOM_SCREEN)


		if (menuResponse == 'stand') or buttonPressed(KEY_B) then
			if (playerHandIndex == 1) and splitActive() then -- split active
				playerHandIndex = 2
			else
				nextState = 'dealerTurn'
				playSFX('flipCard')
			end
		elseif (menuResponse == 'hit') or buttonPressed(KEY_A) then
			currentHand.dealCard()

			playSFX('dealCard')
		end

		if (currentHand.getSize() == 2) and (currentHand.getDoubledDown() == false) and ((playerMoney - moneyWagered() - playerBet) >= 0) then
			-- Screen.debugPrint(5,85, "X to double down", white, BOTTOM_SCREEN)
			if (menuResponse == 'double') or buttonPressed(KEY_X) then
				currentHand.doubleDown()
				playSFX('flipCard')
			end
		else
			Screen.fillRect(5,105, 155, 215, background, BOTTOM_SCREEN )
		end

		if not(splitActive()) and (currentHand.canSplit() == true) and (currentHand.getDoubledDown() == false) and ((playerMoney - moneyWagered() - playerBet) >= 0) then 
			-- Screen.debugPrint(5,105, "R to split", white, BOTTOM_SCREEN)
			if (menuResponse == 'split') or buttonPressed(KEY_R) then
				local cards = playerHands[1].getCards()
				local bet = playerHands[1].getBet()
				playerHands = { newHand({cards[1]}, bet), newHand({cards[2]}, bet) }
				playerHands[1].dealCard()
				playerHands[2].dealCard()

				playSFX('dealCard')
			end
		else -- hide button
			Screen.fillRect(214,314, 155, 215, background, BOTTOM_SCREEN )
		end

		if (getTableSize(playerHands) == 1) and (currentHand.getSize() == 2) and (currentHand.getDoubledDown() == false) then
			-- Screen.debugPrint(5,65, "Y to surrender", white, BOTTOM_SCREEN)
			if (menuResponse == 'surrender') or buttonPressed(KEY_Y) then
				currentHand.setResult('Surrendered')
				nextState = 'dealerTurn'
				playSFX('flipCard')
			end
		else
			Screen.fillRect(109,210, 155, 215, background, BOTTOM_SCREEN )
		end

	elseif (currentState == 'dealerTurn') then

		Screen.debugPrint(5,5, "Cash: $"..(playerMoney - moneyWagered()), white, BOTTOM_SCREEN)
		renderDealerPlayerLine()
		dealerHandValue = dealerHand.getValue()
		Screen.debugPrint(10,5,"Dealer: "..dealerHandValue,white,TOP_SCREEN)
		dealerHandRenderer(13, 17)
		for key, value in pairs(playerHands) do
			Screen.debugPrint(10+(200*(key-1)),126,value.getValue()..": $"..value.getBet(),white,TOP_SCREEN)
			playerHandRenderer(13+(200*(key-1)), 138, value)
		end


		dealerAnimationCounter = dealerAnimationCounter + 1
		if dealerCanReceiveCard() then
			if (dealerAnimationCounter > 20) then
				dealerHand.dealCard()
				dealerAnimationCounter = 0
				playSFX('dealCard')
			end
		else
			if (dealerAnimationCounter > 10) then
				dealerAnimationCounter = 0

				if (playerHasInsurance == true) then
					if (dealerHand.handStatus() == 'blackjack') then
						playerMoney = playerMoney + playerBet -- to cancel out the bet that will be removed
						playerHands[1].setResult("Insured")
					else
						playerMoney = playerMoney - (playerBet / 2.0)
					end
				end

				for key, value in pairs(playerHands) do

					playerHandValue = value.getValue()
					dealerHandValue = dealerHand.getValue()
					if value.getResult() == 'Surrendered' then -- player already surrendered
						table.insert(roundResults, 'surrendered')
						playerMoney = playerMoney - (playerBet / 2.0)
					elseif value.handStatus() == 'bust' then -- player bust
						table.insert(roundResults, 'playerBust')
						playerMoney = playerMoney - value.getBet()
						value.setResult("Lost")
					elseif value.handStatus() == 'blackjack' then -- player has blackjack
						if dealerHand.handStatus() == 'blackjack' then -- dealer also has blackjack
							table.insert(roundResults, 'push')
							value.setResult("Push")
						else
							table.insert(roundResults, 'playerBlackjack')
							if splitActive() then
								playerMoney = playerMoney + value.getBet()
								value.setResult("Won")
							else
								playerMoney = playerMoney + value.getBet() * 1.5
								value.setResult("Blackjack")
							end
						end
					elseif dealerHand.handStatus() == 'blackjack' then -- dealer blackjack always wins unless player has blackjack
						table.insert(roundResults, 'dealerBlackjack')
						playerMoney = playerMoney - value.getBet()
						if (playerHasInsurance == false) then
							value.setResult("Lost")
						end
					elseif dealerHand.handStatus() == 'bust' then -- dealer bust
						table.insert(roundResults, 'dealerBust')
						playerMoney = playerMoney + value.getBet()
						value.setResult("Won")
					elseif (dealerHandValue > playerHandValue) then -- dealer high
						table.insert(roundResults, 'dealerHigh')
						playerMoney = playerMoney - value.getBet()
						value.setResult("Lost")
					elseif (dealerHandValue < playerHandValue) then -- player high
						table.insert(roundResults, 'playerHigh')
						playerMoney = playerMoney + value.getBet()
						value.setResult("Won")
					elseif (dealerHandValue == playerHandValue) then -- push
						table.insert(roundResults, 'push')
						value.setResult("Push")
					else
						table.insert(roundResults, 'undefined?')
					end
				end

				playerMoney = math.floor(playerMoney)

				if (playerMoney >= minBet) then
					nextState = 'menu'
					moneyWriten = false

				else
					nextState = 'gameOver'
					moneyWriten = false
				end
			end

		end

	elseif currentState == 'gameOver' then
		Screen.debugPrint(5,5, "Game Over", white, BOTTOM_SCREEN)

		-- Screen.debugPrint(5,25, table.concat(roundResults), white, BOTTOM_SCREEN)
		renderDealerPlayerLine()
		dealerHandValue = dealerHand.getValue()
		Screen.debugPrint(10,5,"Dealer: "..dealerHandValue,white,TOP_SCREEN)
		dealerHandRenderer(13, 17)
		for key, value in pairs(playerHands) do
			Screen.debugPrint(10+(200*(key-1)),126,value.getValue()..": $"..value.getBet().." ("..value.getResult()..")",white,TOP_SCREEN)
			playerHandRenderer(13+(200*(key-1)), 138, value)
		end

		Screen.fillRect(5,314, 25, 150, buttonFill, BOTTOM_SCREEN )

		if (menuResponse == 'restart') or (buttonPressed(KEY_X)) then
			playerMoney = 1000
			playerBet = 100
			dealerHand = nil -- will reset the menu
			nextState = 'menu'
		end
	end
	
	playerMoney = math.floor(playerMoney)
	oldPad = pad
	oldX, oldY = xTouch, yTouch
	currentState = nextState
	Screen.flip()
end