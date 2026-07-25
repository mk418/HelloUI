local ADDON_NAME, ns = ...

ns.Friends = {}
local Friends = ns.Friends

local Config = ns.Config

--------------------------------------------------------------------------
-- Friends list
--
-- FriendsFrame_UpdateFriendButton is still the hook point on 1.15.9. There
-- is no ScrollBox path and no FriendsListFrameMixin here - the friends list
-- is still a HybridScrollFrame with recycled buttons - so the port from
-- DragonflightUI's Utility module is close to direct.
--
-- Recycled buttons are the thing to get right: every field we set has to be
-- set on every pass, for every button, including back to the default. A
-- button that was a class-coloured warrior a scroll ago will be reused for an
-- offline friend, and if we only ever write colours we will leave the warrior
-- red on a grey row.
--------------------------------------------------------------------------

-- Both APIs return a LOCALISED class name, not the English token that
-- RAID_CLASS_COLORS is keyed by, so the lookup has to go backwards through
-- Blizzard's own localisation tables. Built once, lazily, because the tables
-- are populated by the client before any friends list can be drawn.
local classToken = nil

local function buildClassTokens()
    if classToken then return classToken end
    classToken = {}
    for _, tbl in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
        if type(tbl) == "table" then
            for token, localised in pairs(tbl) do
                if type(localised) == "string" then classToken[localised] = token end
            end
        end
    end
    return classToken
end

local function colorFor(localisedClass)
    if not Config:Enabled("friendsClassColor") then return nil end
    if not localisedClass then return nil end
    local token = buildClassTokens()[localisedClass]
    if not token then return nil end
    return ns:ClassColor(token)
end

--------------------------------------------------------------------------
-- The <3 heart
--
-- Ported as-is from the old Utility module because it is twenty lines and it
-- is charming. Texture 135451 is the interface heart icon.
--------------------------------------------------------------------------

local HEART_TEXTURE = 135451

local function heartFor(button)
    if not button.HelloUIHeart then
        local heart = button:CreateTexture(nil, "OVERLAY")
        heart:SetTexture(HEART_TEXTURE)
        heart:SetSize(20, 20)
        -- gameIcon is the BNet client badge and is the anchor the original
        -- used; fall back to the button's right edge when it is absent (a
        -- plain WoW friend row has no game icon).
        if button.gameIcon then
            heart:SetPoint("RIGHT", button.gameIcon, "LEFT", -2, 0)
        else
            heart:SetPoint("RIGHT", button, "RIGHT", -8, 0)
        end
        button.HelloUIHeart = heart
    end
    return button.HelloUIHeart
end

local function applyHeart(button, note)
    local want = Config:Enabled("friendsHeart")
        and type(note) == "string" and note:find("<3", 1, true) ~= nil

    if not want then
        if button.HelloUIHeart then button.HelloUIHeart:Hide() end
        return
    end
    heartFor(button):Show()
end

--------------------------------------------------------------------------

local function applyToButton(button)
    if not button or not button.buttonType then return end

    local nameText = button.name
    if not nameText or not nameText.SetTextColor then return end

    local colored = false
    local note

    if button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local info = C_FriendList and C_FriendList.GetFriendInfoByIndex
            and C_FriendList.GetFriendInfoByIndex(button.id)
        if info then
            note = info.notes
            if info.connected then
                local r, g, b = colorFor(info.className)
                if r then
                    nameText:SetTextColor(r, g, b)
                    colored = true
                end
            end
        end

    elseif button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        -- BNGetFriendInfo is still the shape Blizzard's own 1.15.9
        -- FriendsFrame.lua uses on this path, so it is the right call here
        -- even though it is a wide multi-return.
        if BNGetFriendInfo then
            local _, _, _, _, _, bnetIDGameAccount, client, isOnline,
                  _, _, _, _, noteText = BNGetFriendInfo(button.id)
            note = noteText
            if isOnline and client == BNET_CLIENT_WOW and bnetIDGameAccount and BNGetGameAccountInfo then
                local _, _, _, _, _, _, _, class = BNGetGameAccountInfo(bnetIDGameAccount)
                local r, g, b = colorFor(class)
                if r then
                    nameText:SetTextColor(r, g, b)
                    colored = true
                end
            end
        end
    end

    -- No fallback repaint. Recycling is handled for us: this runs as a
    -- hooksecurefunc on FriendsFrame_UpdateFriendButton, which has already set
    -- the correct colour for this row before we get here - and it uses four
    -- different ones (FRIENDS_WOW_NAME_COLOR online, FRIENDS_GRAY_COLOR
    -- offline, FRIENDS_BNET_NAME_COLOR for BNet, grey again for offline BNet).
    -- An earlier version repainted un-coloured rows with FRIENDS_WOW_NAME_COLOR
    -- to "clean up after recycling", which turned every offline friend blue.
    -- Leaving Blizzard's colour alone is both simpler and correct.
    button.HelloUIColored = colored

    applyHeart(button, note)
end

function Friends:Refresh()
    -- Repaint whatever is currently on screen. The list is a HybridScrollFrame
    -- of recycled buttons, and the scroll frame is reached by its GLOBAL name:
    -- FriendsFrame.xml declares `<ScrollFrame name="FriendsFrameFriendsScrollFrame">`
    -- as a child of FriendsListFrame with no parentKey, so the tempting
    -- `FriendsListFrame.ScrollFrame` is nil on this client and silently made
    -- this whole function a no-op.
    local scroll = _G["FriendsFrameFriendsScrollFrame"]
    local buttons = scroll and scroll.buttons
    if not buttons then return end
    for _, button in ipairs(buttons) do
        applyToButton(button)
    end
end

function Friends:Apply()
    Friends:Refresh()
end

function Friends:Init()
    if type(_G["FriendsFrame_UpdateFriendButton"]) == "function" then
        hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button)
            if not Config:Get("enabled") then return end
            ns:SafeCall("Friends:button", applyToButton, button)
        end)
        Friends.hooked = true
    end
end

function Friends:StatusText()
    if not Friends.hooked then
        return "friends: |cffffd100no FriendsFrame_UpdateFriendButton hook|r"
    end
    return nil
end

function Friends:Status()
    if not Friends.hooked then
        ns:Print("friends: |cffffd100FriendsFrame_UpdateFriendButton not found|r")
        return
    end
    ns:Print("friends: class colour %s, heart %s",
        Config:Enabled("friendsClassColor") and "on" or "off",
        Config:Enabled("friendsHeart") and "on" or "off")
end
