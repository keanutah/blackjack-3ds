white = Color.new(255,255,255)

Screen.waitVblankStart()
Screen.refresh()
Screen.debugPrint(5,5,'Loading...', white, TOP_SCREEN)
Screen.flip()

background = Color.new(7,99,36)

h,m,s = System.getTime()
seed = s + m * 60 + h * 3600
math.randomseed (seed)

oldPad = Controls.read()

cardSprites = Screen.loadImage(System.currentDirectory().."/images/cardsprites.png")
cardSpritesDim = Screen.loadImage(System.currentDirectory().."/images/cardspritesdim.png")
cardBack = Screen.loadImage(System.currentDirectory().."/images/cardback.png")

bgm = Sound.openOgg((System.currentDirectory().."/sound/bgm.ogg"), false)

suiteYIndices = { s=0, c=98, h=196, d=294 }
suiteXIndices = { ['A']=0, [2]=73, [3]=(73*2), [4]=(73*3), [5]=(73*4), [6]=(73*5), [7]=(73*6), [8]=(73*7), [9]=(73*8), [10]=(73*9), ['J']=(73*10), ['Q']=(73*11), ['K']=(73*12) }

cards = {2,3,4,5,6,7,8,9,10,'J','Q','K','A'}
suites = {'c','d','s','h'}

playerMoney = 1000

deck = nil
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

Sound.init()
Sound.play(bgm,LOOP,0x08,0x09) 

---------------------------------------------------------------------------

while true do
	Screen.waitVblankStart()
	pad = Controls.read()
	Screen.refresh()
	Screen.clear(TOP_SCREEN)
	Screen.clear(BOTTOM_SCREEN)
	
	Screen.fillRect(0, 399, 0, 239, background, TOP_SCREEN)
	Screen.fillRect(0, 319, 0, 239, background, BOTTOM_SCREEN)
	
	if (currentState == 'menu') then
		Screen.debugPrint(5,5, "Cash: $"..playerMoney, white, BOTTOM_SCREEN)
		Screen.debugPrint(5,25, "A to deal hand", white, BOTTOM_SCREEN)
		if (buttonPressed(KEY_A)) then
			nextState = 'playerBet'
		end
		
	elseif (currentState == 'options') then
		
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
		
		if (dealerHand.getCards()[1][1] == 'A') then
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

		Screen.debugPrint(5,45, "X to buy insurance for $"..math.floor(playerBet / 2.0), white, BOTTOM_SCREEN)
		if (buttonPressed(KEY_X)) then
			playerHasInsurance = true
			if (playerHands[1].handStatus() == 'blackjack') then
				nextState = 'dealerTurn'
			else
				nextState = 'dealerPeek'
			end
		end

		Screen.debugPrint(5,25, "A to continue", white, BOTTOM_SCREEN)
		if (buttonPressed(KEY_A)) then
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
		
		Screen.debugPrint(5,25, "A to hit", white, BOTTOM_SCREEN)
		Screen.debugPrint(5,45, "B to stand", white, BOTTOM_SCREEN)


		if (buttonPressed(KEY_B)) then
			if (playerHandIndex == 1) and splitActive() then -- split active
				playerHandIndex = 2
			else
				nextState = 'dealerTurn'
			end
		elseif (buttonPressed(KEY_A)) then
			currentHand.dealCard()
		end

		if (currentHand.getSize() == 2) and (currentHand.getDoubledDown() == false) then
			Screen.debugPrint(5,85, "X to double down", white, BOTTOM_SCREEN)
			if (buttonPressed(KEY_X)) then
				currentHand.doubleDown()
			end
		end

		if not(splitActive()) and (currentHand.canSplit() == true) and (currentHand.getDoubledDown() == false) then 
			Screen.debugPrint(5,105, "R to split", white, BOTTOM_SCREEN)
			if (buttonPressed(KEY_R)) then
				local cards = playerHands[1].getCards()
				local bet = playerHands[1].getBet()
				playerHands = { newHand({cards[1]}, bet), newHand({cards[2]}, bet) }
				playerHands[1].dealCard()
				playerHands[2].dealCard()
			end
		end

		if (getTableSize(playerHands) == 1) and (currentHand.getSize() == 2) and (currentHand.getDoubledDown() == false) then
			Screen.debugPrint(5,65, "Y to surrender", white, BOTTOM_SCREEN)
			if (buttonPressed(KEY_Y)) then
				currentHand.setResult('Surrendered')
				nextState = 'dealerTurn'
			end
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
				for key, value in pairs(playerHands) do
					if (playerHasInsurance == true) then
						if (dealerHand.handStatus() == 'blackjack') then
							playerMoney = playerMoney + value.getBet() -- to cancel out the bet that will be removed
							value.setResult("Insured")
						else
							playerMoney = playerMoney - (playerBet / 2.0)
						end
					end

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
				nextState = 'handTerm'
			end

		end


		
	elseif (currentState == 'handTerm') then
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


		Screen.debugPrint(5,25, "A to continue", white, BOTTOM_SCREEN)
		if (buttonPressed(KEY_A)) then
			nextState = 'menu'
		end
	end
	
	if (Controls.check(pad,KEY_START)) then
		Sound.term()
		System.exit()
	end
	
	playerMoney = math.floor(playerMoney)
	oldPad = pad
	currentState = nextState
	Screen.flip()
end