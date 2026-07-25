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
    "_G",
}
