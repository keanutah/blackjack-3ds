white = Color.new(255,255,255)
black = Color.new(0,0,0)
background = Color.new(7,99,36)
buttonFill = Color.new(9,86,32)
buttonText = Color.new(200,200,200)

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
cardBack = Screen.loadImage(System.currentDirectory().."/images/cardback.png")

aButton = Screen.loadImage(System.currentDirectory().."/images/a.png")
bButton = Screen.loadImage(System.currentDirectory().."/images/b.png")
xButton = Screen.loadImage(System.currentDirectory().."/images/x.png")
yButton = Screen.loadImage(System.currentDirectory().."/images/y.png")
rButton = Screen.loadImage(System.currentDirectory().."/images/r.png")
startButton = Screen.loadImage(System.currentDirectory().."/images/start.png")

-- bgm = Sound.openOgg((System.currentDirectory().."/sound/bgm.ogg"), false)

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

currentState = 'menu'
nextState = 'menu'

dealerAnimationCounter = 0

fullLengthCardSpacing = 75
singleHandCollapseCardSpacing = 35
splitHandCardSpacing = 20


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
	end

	return sum
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
	table.remove(deck, index)
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
			if (dealerHand.getValue() < 17) and (playerHands[1].handStatus() == 'valid') and (playerHands[2].handStatus() == 'valid') then
				return true
			end
		else
			if (dealerHand.getValue() < 17) and (playerHands[1].handStatus() == 'valid') then
				return true
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
	end
	if not withinCoords(x, y, x1, x2, y1, y2) and _G[returnString..'Trigger'] then
		_G[returnString..'Trigger'] = false
		return returnString
	end
	return false
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
		getResult = getResult
	}
end

---------------------------------------------------------------------------

function drawAndCheckMenu ()
	if currentState == 'menu' then
		Screen.fillRect(5,314, 25, 85, buttonFill, BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 25, 85, black, BOTTOM_SCREEN )
		Screen.drawImage(8,28, aButton, BOTTOM_SCREEN)
		Screen.debugPrint(118,50, "New Hand", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 25, 85, 'newHand') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,314, 90, 150, buttonFill, BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 90, 150, black, BOTTOM_SCREEN )
		Screen.drawImage(8,93, xButton, BOTTOM_SCREEN)
		Screen.debugPrint(128,115, "Options", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 90, 150, 'options') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,314, 155, 215, buttonFill, BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(8,158, startButton, BOTTOM_SCREEN)
		Screen.debugPrint(142,180, "Exit", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 155, 215, 'exit') or trigger
		if trigger then return trigger end

	elseif currentState == 'options' then
		Screen.fillRect(5,314, 155, 215, buttonFill, BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(8,158, bButton, BOTTOM_SCREEN)
		Screen.debugPrint(142,180, "Back", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 155, 215, 'backToMenu') or trigger
		if trigger then return trigger end

	elseif currentState == 'offerInsurance' then
		Screen.fillRect(5,314, 25, 85, buttonFill, BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 25, 85, black, BOTTOM_SCREEN )
		Screen.drawImage(8,28, aButton, BOTTOM_SCREEN)
		Screen.debugPrint(80,50, "Decline Insurance", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 25, 85, 'skipInsurance') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,314, 90, 150, buttonFill, BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 90, 150, black, BOTTOM_SCREEN )
		Screen.drawImage(8,93, xButton, BOTTOM_SCREEN)
		Screen.debugPrint(70,115, "Buy Insurance ($"..math.floor(playerBet / 2.0)..")", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 90, 150, 'buyInsurance') or trigger
		if trigger then return trigger end

	elseif currentState == 'playerTurn' then
		Screen.fillRect(5,314, 25, 85, buttonFill, BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 25, 85, black, BOTTOM_SCREEN )
		Screen.drawImage(8,28, aButton, BOTTOM_SCREEN)
		Screen.debugPrint(147,50, "Hit", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 25, 85, 'hit') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,314, 90, 150, buttonFill, BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,314, 90, 150, black, BOTTOM_SCREEN )
		Screen.drawImage(8,93, bButton, BOTTOM_SCREEN)
		Screen.debugPrint(135,115, "Stand", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 314, 90, 150, 'stand') or trigger
		if trigger then return trigger end

		Screen.fillRect(5,105, 155, 215, buttonFill, BOTTOM_SCREEN )
		Screen.fillEmptyRect(5,105, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(8,158, xButton, BOTTOM_SCREEN)
		Screen.debugPrint(27,180, "Double", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 5, 105, 155, 215, 'double') or trigger
		if trigger then return trigger end

		Screen.fillRect(109,210, 155, 215, buttonFill, BOTTOM_SCREEN )
		Screen.fillEmptyRect(109,210, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(112,158, yButton, BOTTOM_SCREEN)
		Screen.debugPrint(114,180, "Surrender", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 109, 210, 155, 215, 'surrender') or trigger
		if trigger then return trigger end

		Screen.fillRect(214,314, 155, 215, buttonFill, BOTTOM_SCREEN )
		Screen.fillEmptyRect(214,314, 155, 215, black, BOTTOM_SCREEN )
		Screen.drawImage(217,158, rButton, BOTTOM_SCREEN)
		Screen.debugPrint(243,180, "Split", buttonText, BOTTOM_SCREEN)
		local trigger = menuTrigger(xTouch, yTouch, 214, 314, 155, 215, 'split') or trigger
		if trigger then return trigger end

	elseif currentState == 'gameOver' then
		Screen.fillRect(5,314, 155, 215, buttonFill, BOTTOM_SCREEN )
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

-- Sound.init()
-- Sound.play(bgm,LOOP,0x08,0x09)

fileStream = io.open(System.currentDirectory().."/money.file",FREAD)
fileMoney = io.read(fileStream,0,10)
io.close(fileStream)

if tonumber(fileMoney) == nil then
	fileStream = io.open(System.currentDirectory().."/money.file",FCREATE)
	local size = string.len(tostring(playerMoney))
	io.write(fileStream,0,'0000000000', 10)
	io.write(fileStream,10-size,playerMoney, size) 
	io.close(fileStream)
else
	playerMoney = tonumber(fileMoney)
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

	menuResponse = drawAndCheckMenu()

	Screen.debugPrint(150,225, "Blackjack 3DS v0.1", white, BOTTOM_SCREEN)
	-- Screen.debugPrint(5,225, "d:"..fileMoney, white, BOTTOM_SCREEN)
	
	if (currentState == 'menu') then

		if moneyWriten == false then
			fileStream = io.open(System.currentDirectory().."/money.file",FCREATE)
			local size = string.len(tostring(playerMoney))
			io.write(fileStream,0,'0000000000', 10)
			io.write(fileStream,10-size,playerMoney, size) 
			io.close(fileStream)
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
			Screen.debugPrint(5,5, "Cash: $"..playerMoney, white, BOTTOM_SCREEN)
		end


		if ((menuResponse == 'newHand') or buttonPressed(KEY_A)) and (playerMoney >= playerBet) then
			nextState = 'playerBet'
		end

		if (menuResponse == 'options') or buttonPressed(KEY_SELECT) then
			nextState = 'options'
		end

		if (menuResponse == 'exit') or buttonPressed(KEY_START) then
			Sound.term()
			System.exit()
		end
		
	elseif (currentState == 'options') then
		Screen.debugPrint(5,5, "Options", white, BOTTOM_SCREEN)

		Screen.fillRect(5,314, 25, 150, buttonFill, BOTTOM_SCREEN )

		if (menuResponse == 'backToMenu') or (buttonPressed(KEY_B)) then
			nextState = 'menu'
		end
		
	elseif (currentState == 'playerBet') then
		Screen.debugPrint(5,5, "Cash: $"..playerMoney, white, BOTTOM_SCREEN)
	  	playerBet = 100
		nextState = 'turnStart'

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

		roundResults = {}
		
		if (dealerHand.getCards()[1][1] == 'A') and ((playerMoney - (playerBet / 2.0)) > 0) then
			nextState = 'offerInsurance'
		elseif (playerHands[1].handStatus() == 'blackjack') then
			nextState = 'dealerTurn'
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
			else
				nextState = 'dealerPeek'
			end
		end

		-- Screen.debugPrint(5,25, "A to continue", white, BOTTOM_SCREEN)
		if (menuResponse == 'skipInsurance') or buttonPressed(KEY_A) then
			if (playerHands[1].handStatus() == 'blackjack') then
				nextState = 'dealerTurn'
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
			end
		end
		
		-- Screen.debugPrint(5,25, "A to hit", white, BOTTOM_SCREEN)
		-- Screen.debugPrint(5,45, "B to stand", white, BOTTOM_SCREEN)


		if (menuResponse == 'stand') or buttonPressed(KEY_B) then
			if (playerHandIndex == 1) and splitActive() then -- split active
				playerHandIndex = 2
			else
				nextState = 'dealerTurn'
			end
		elseif (menuResponse == 'hit') or buttonPressed(KEY_A) then
			currentHand.dealCard()
		end

		if (currentHand.getSize() == 2) and (currentHand.getDoubledDown() == false) and ((playerMoney - playerBet) > 0) then
			-- Screen.debugPrint(5,85, "X to double down", white, BOTTOM_SCREEN)
			if (menuResponse == 'double') or buttonPressed(KEY_X) then
				currentHand.doubleDown()
			end
		else
			Screen.fillRect(5,105, 155, 215, background, BOTTOM_SCREEN )
		end

		if not(splitActive()) and (currentHand.canSplit() == true) and (currentHand.getDoubledDown() == false) and ((playerMoney - playerBet) > 0) then 
			-- Screen.debugPrint(5,105, "R to split", white, BOTTOM_SCREEN)
			if (menuResponse == 'split') or buttonPressed(KEY_R) then
				local cards = playerHands[1].getCards()
				local bet = playerHands[1].getBet()
				playerHands = { newHand({cards[1]}, bet), newHand({cards[2]}, bet) }
				playerHands[1].dealCard()
				playerHands[2].dealCard()
			end
		else -- hide button
			Screen.fillRect(214,314, 155, 215, background, BOTTOM_SCREEN )
		end

		if (getTableSize(playerHands) == 1) and (currentHand.getSize() == 2) and (currentHand.getDoubledDown() == false) then
			-- Screen.debugPrint(5,65, "Y to surrender", white, BOTTOM_SCREEN)
			if (menuResponse == 'surrender') or buttonPressed(KEY_Y) then
				currentHand.setResult('Surrendered')
				nextState = 'dealerTurn'
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
			end
		else
			if (dealerAnimationCounter > 10) then
				dealerAnimationCounter = 0

				if (playerHasInsurance == true) then
					if (dealerHand.handStatus() == 'blackjack') then
						playerMoney = playerMoney + value.getBet() -- to cancel out the bet that will be removed
						value.setResult("Insured")
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

				if (playerMoney >= playerBet) then
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