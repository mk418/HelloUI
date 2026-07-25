local ADDON_NAME, ns = ...

ns.Darkmode = {}
local Darkmode = ns.Darkmode

local Config = ns.Config

--------------------------------------------------------------------------
-- Darkmode
--
-- Desaturate plus a flat grey tint over Blizzard's frame art. The technique
-- is the old module's; the target list is not, and could not be - most of
-- what DragonflightUI's 1000-line Darkmode touched was DragonflightUI's own
-- replacement art.
--
-- AN EXPLICIT ALLOWLIST, NEVER AN ENUMERATION. This is a hard rule, not a
-- style preference, and it is the whole reason this module is written the way
-- it is:
--
--   * Four sibling addons park a Hello*MinimapButton directly on the Minimap
--     frame - HelloGear, HelloLog, HelloStock and HelloWorldBuffs. Anything
--     that walks Minimap's children greys out four addons' icons, which is
--     exactly what the old module's UpdateMinimapButton did.
--
--   * HelloWarrior and HelloTotems both use SetDesaturated on their own
--     buttons as LIVE STATE - out-of-range tint and empty-slot placeholders.
--     A second desaturation pass over those does not merely look wrong, it
--     corrupts a signal read mid-fight.
--
--   * Masque is installed (with Masque_Cirque and OPieMasque) and owns action
--     button art. So the actionbar area here is limited to BAR art and never
--     touches a button, because Masque may have replaced those objects
--     outright and the user chose that skin.
--
-- TWO AREAS FROM THE OLD PROFILE ARE DELIBERATELY GONE:
--
--   buffs - there is no stock target. 1.15.9 buff buttons are anonymous
--   pooled frames, AuraButtonArtTemplate carries no buff border at all, and
--   the only border it does have (DebuffBorder) is dispel-type colour, i.e.
--   live state again.
--
--   general UI - it was already a no-op. DragonflightUI's Module:UpdateUI
--   checked its enable flag and returned without touching a single texture,
--   so its defaults never did anything and there is nothing to port.
--
-- If a tint mysteriously stops applying, the first suspect is Leatrix_Plus:
-- it also re-textures PlayerFrameTexture under its player-frame options and
-- blanks MinimapCluster.BorderTop.
--------------------------------------------------------------------------

-- Each entry is resolved lazily through a function, because some of these
-- frames are created after we load and all of them may be absent.
local ENTRIES = {
    -- Unit frames. PlayerFrameTexture and PetFrameTexture are named in
    -- Blizzard's XML; TargetFrameTextureFrameTexture is reached through
    -- $parent nesting and is dereferenced unguarded by the working fork,
    -- so it resolves on this client.
    { area = "unitframes", get = function() return _G["PlayerFrameTexture"] end },
    { area = "unitframes", get = function() return _G["TargetFrameTextureFrameTexture"] end },
    { area = "unitframes", get = function() return _G["PetFrameTexture"] end },

    -- Minimap. The ring border, the header art, and both zoom buttons in
    -- normal and disabled state - the buttons are Enable()/Disable()d rather
    -- than re-textured, so the disabled art really does get shown at the
    -- zoom limits and a one-shot tint on it is enough.
    { area = "minimap", get = function() return _G["MinimapBorder"] end },
    { area = "minimap", get = function()
        local c = _G["MinimapCluster"]
        return c and c.BorderTop
    end },
    { area = "minimap", get = function()
        local b = _G["MinimapZoomIn"]
        return b and b.GetNormalTexture and b:GetNormalTexture()
    end },
    { area = "minimap", get = function()
        local b = _G["MinimapZoomIn"]
        return b and b.GetDisabledTexture and b:GetDisabledTexture()
    end },
    { area = "minimap", get = function()
        local b = _G["MinimapZoomOut"]
        return b and b.GetNormalTexture and b:GetNormalTexture()
    end },
    { area = "minimap", get = function()
        local b = _G["MinimapZoomOut"]
        return b and b.GetDisabledTexture and b:GetDisabledTexture()
    end },

    -- Action bar art only. MainMenuBarTexture0-3 are the bar backdrop
    -- panels. Nothing here reaches a button.
    { area = "actionbars", get = function() return _G["MainMenuBarTexture0"] end },
    { area = "actionbars", get = function() return _G["MainMenuBarTexture1"] end },
    { area = "actionbars", get = function() return _G["MainMenuBarTexture2"] end },
    { area = "actionbars", get = function() return _G["MainMenuBarTexture3"] end },

    -- Cast bars. Border is a parentKey on both frames.
    { area = "castbar", get = function()
        local f = _G["PlayerCastingBarFrame"]
        return f and f.Border
    end },
    { area = "castbar", get = function()
        local f = _G["PetCastingBarFrame"]
        return f and f.Border
    end },
}

Darkmode.AREAS = { "unitframes", "minimap", "actionbars", "castbar" }

--------------------------------------------------------------------------
-- Original state
--
-- GetVertexColor is safe to read. Desaturation deliberately is NOT read
-- back: IsDesaturated is gated behind the client's secret-value machinery on
-- this build, and every texture on the allowlist above is ordinary
-- un-desaturated stock frame art, so restoring to false is correct without
-- having to ask.
--
-- Keyed by texture object, and the object is re-read on every pass rather
-- than cached, because some of these are button textures that Blizzard may
-- replace wholesale when it re-textures a button.
--------------------------------------------------------------------------

local saved = {}

local function record(tex)
    if saved[tex] then return end
    local r, g, b, a = 1, 1, 1, 1
    if tex.GetVertexColor then
        local ok, vr, vg, vb, va = pcall(tex.GetVertexColor, tex)
        if ok and vr then r, g, b, a = vr, vg, vb, va or 1 end
    end
    saved[tex] = { r = r, g = g, b = b, a = a }
end

local function tintOne(tex, desaturate, r, g, b)
    record(tex)
    if tex.SetDesaturated then pcall(tex.SetDesaturated, tex, desaturate and true or false) end
    if tex.SetVertexColor then tex:SetVertexColor(r, g, b, saved[tex].a or 1) end
end

local function restoreOne(tex)
    local s = saved[tex]
    if not s then return end
    if tex.SetDesaturated then pcall(tex.SetDesaturated, tex, false) end
    if tex.SetVertexColor then tex:SetVertexColor(s.r, s.g, s.b, s.a or 1) end
    saved[tex] = nil
end

--------------------------------------------------------------------------

function Darkmode:Apply()
    local on = Config:Enabled("darkmode")
    local areas = Config:GetTable("darkmodeAreas")
    local tint = Config:GetTable("darkmodeTint")
    local desaturate = Config:Get("darkmodeDesaturate")
    local r = tint.r or 0.4
    local g = tint.g or 0.4
    local b = tint.b or 0.4

    local applied, found = 0, 0

    for _, entry in ipairs(ENTRIES) do
        local ok, tex = pcall(entry.get)
        if ok and tex then
            found = found + 1
            if on and areas[entry.area] then
                tintOne(tex, desaturate, r, g, b)
                applied = applied + 1
            else
                restoreOne(tex)
            end
        end
    end

    Darkmode.found = found
    Darkmode.applied = applied
end

function Darkmode:Init()
    -- Blizzard re-textures a few of these in normal play, and whether
    -- SetTexture clears the desaturation flag is not answerable from the Lua
    -- source. Re-applying on the events that drive those re-textures is
    -- cheap and makes the question moot.
    local function reapply(label)
        return function() ns:SafeCall("Darkmode:" .. label, Darkmode.Apply, Darkmode) end
    end

    ns:On("PLAYER_TARGET_CHANGED", reapply("target"))
    ns:On("UNIT_PET", reapply("pet"))
    ns:On("PLAYER_ENTERING_WORLD", reapply("pew"))
end

function Darkmode:StatusText()
    if not Darkmode.found then return nil end
    return ("darkmode: %d/%d art pieces found"):format(Darkmode.applied or 0, Darkmode.found)
end

function Darkmode:Status()
    if not Config:Enabled("darkmode") then
        ns:Print("darkmode: off")
        return
    end
    local tint = Config:GetTable("darkmodeTint")
    local areas = Config:GetTable("darkmodeAreas")
    local on = {}
    for _, area in ipairs(Darkmode.AREAS) do
        if areas[area] then on[#on + 1] = area end
    end
    ns:Print("darkmode: %d of %d art pieces tinted %.2f/%.2f/%.2f%s",
        Darkmode.applied or 0, Darkmode.found or 0,
        tint.r or 0.4, tint.g or 0.4, tint.b or 0.4,
        Config:Get("darkmodeDesaturate") and ", desaturated" or "")
    ns:Print("  |cff808080areas: %s|r", #on > 0 and table.concat(on, ", ") or "none")
end
