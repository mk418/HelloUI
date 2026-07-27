-- luacheck configuration for HelloUI (World of Warcraft Classic Era addon).
-- WoW runs on Lua 5.1. From the addon root, run:  luacheck .

std = "lua51"

max_line_length = false
unused_args = false

ignore = {
    "211/ADDON_NAME",  -- `local ADDON_NAME, ns = ...` idiom; name unused in most files
    "432/self",        -- inner callbacks (OnClick/OnEnter/...) take their own `self`
}

-- True globals this addon owns or mutates. Everything else lives on the `ns`
-- table threaded in via `local ADDON_NAME, ns = ...`.
globals = {
    "HelloUIDB",       -- SavedVariables
    "HelloUICharDB",   -- SavedVariablesPerCharacter
    "SlashCmdList",
    "SLASH_HELLOUI1",
    "SLASH_HELLOUI2",
    "StaticPopupDialogs",
    "_G",
}

-- The WoW API surface this addon reads. Declared so `luacheck .` comes back
-- clean and a genuinely undefined variable is visible instead of buried in
-- thirty "accessing undefined variable" lines, same as HelloGear.
read_globals = {
    -- Core widget and event API
    "CreateFrame",
    "UIParent",
    "CopyTable",
    "C_EditMode",
    "EditModePresetLayoutManager",
    "Enum",
    "hooksecurefunc",
    "InCombatLockdown",
    "DEFAULT_CHAT_FRAME",
    "GameTooltip",
    "UnitClass",
    "UnitName",
    "UnitLevel",
    "UnitXP",
    "UnitXPMax",
    "GetMaxPlayerLevel",
    "GetMaxLevelForPlayerExpansion",
    "GetXPExhaustion",
    "BreakUpLargeNumbers",
    "GetTrackingTexture",
    "StaticPopup_Show",
    -- Dropdown menu API, as HelloBuffCap's options panel uses it.
    "UIDropDownMenu_SetWidth",
    "UIDropDownMenu_Initialize",
    "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_AddButton",
    "UIDropDownMenu_SetText",
    "ShowUIPanel",
    "HideUIPanel",

    -- Namespaced API
    "C_AddOns",
    "C_ClassColor",
    "C_CVar",
    "C_EventUtils",
    "C_FriendList",
    "C_PlayerInfo",
    "C_Reputation",

    -- Legacy fallbacks, only reached when the namespaced form is absent
    "GetCVar",
    "SetCVar",
    "IsAddOnLoaded",
    "GetWatchedFactionInfo",

    -- Settings and Edit Mode
    "Settings",
    "InterfaceOptions_AddCategory",
    "InterfaceOptionsFrame_OpenToCategory",
    "EditModeManagerFrame",

    -- Frames and mixins this addon reads state from
    "StatusTrackingBarManager",
    "UnitFrameHealthBar_Update",

    -- Class colours
    "RAID_CLASS_COLORS",
    "CUSTOM_CLASS_COLORS",
    "LOCALIZED_CLASS_NAMES_MALE",
    "LOCALIZED_CLASS_NAMES_FEMALE",
    "FACTION_BAR_COLORS",

    -- Friends list
    "BNGetFriendInfo",
    "BNGetGameAccountInfo",
    "BNET_CLIENT_WOW",
    "FRIENDS_BUTTON_TYPE_BNET",
    "FRIENDS_BUTTON_TYPE_WOW",
    "FRIENDS_WOW_NAME_COLOR",
}
