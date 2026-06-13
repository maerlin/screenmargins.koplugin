--[[--
Plugin for configuring screen margins/viewport to handle devices with bezels.

@module koplugin.screenmargins
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

local SETTING_ORIGINAL_SIZE = "screenmargins_original_size"
local SETTING_VIEWPORT = "screenmargins_viewport"
local LEGACY_SETTING_ORIGINAL_SIZE = "screen_original_size"
local LEGACY_SETTING_VIEWPORT = "screen_viewport"

local function toInteger(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return math.floor(number)
end

local function normalizeSize(size)
    if type(size) ~= "table" then
        return nil
    end
    local w = toInteger(size.w)
    local h = toInteger(size.h)
    if not w or not h or w <= 0 or h <= 0 then
        return nil
    end
    return { w = w, h = h }
end

local function copyViewport(viewport)
    return Geom:new{
        x = viewport.x,
        y = viewport.y,
        w = viewport.w,
        h = viewport.h,
    }
end

local function fullViewport(screen_size)
    return Geom:new{
        x = 0,
        y = 0,
        w = screen_size.w,
        h = screen_size.h,
    }
end

local function normalizeViewport(viewport, screen_w, screen_h)
    if type(viewport) ~= "table" then
        return nil
    end

    local x = toInteger(viewport.x or 0)
    local y = toInteger(viewport.y or 0)
    local w = toInteger(viewport.w)
    local h = toInteger(viewport.h)

    if not x or not y or not w or not h or
       x < 0 or y < 0 or w <= 0 or h <= 0 or
       x + w > screen_w or y + h > screen_h then
        return nil
    end

    return Geom:new{ x = x, y = y, w = w, h = h }
end

local function sameViewport(left, right)
    return left and right and
        left.x == right.x and left.y == right.y and
        left.w == right.w and left.h == right.h
end

local function sameRawSize(raw, size)
    return type(raw) == "table" and raw.w == size.w and raw.h == size.h
end

local function sameRawViewport(raw, viewport)
    return type(raw) == "table" and
        raw.x == viewport.x and raw.y == viewport.y and
        raw.w == viewport.w and raw.h == viewport.h
end

local function clamp(value, min_value, max_value)
    local number = toInteger(value) or min_value
    if max_value < min_value then
        max_value = min_value
    end
    if number < min_value then
        return min_value
    elseif number > max_value then
        return max_value
    end
    return number
end

-- Full-screen overlay that draws black bars at the margin positions,
-- giving a "papercut frame" preview of how the margins will look without
-- requiring an actual viewport change.
local MarginOverlay = Widget:extend{}

function MarginOverlay:paintTo(bb, x, y)
    local black = Blitbuffer.COLOR_BLACK
    local m = self.margins
    local sw = self.screen_w
    local sh = self.screen_h
    -- Top and bottom bars span the full width.
    if m.top > 0 then
        bb:paintRect(x, y, sw, m.top, black)
    end
    if m.bottom > 0 then
        bb:paintRect(x, y + sh - m.bottom, sw, m.bottom, black)
    end
    -- Left and right bars fill only the space between the top and bottom bars
    -- so the corners are not double-painted.
    local inner_y = y + m.top
    local inner_h = sh - m.top - m.bottom
    if inner_h > 0 then
        if m.left > 0 then
            bb:paintRect(x, inner_y, m.left, inner_h, black)
        end
        if m.right > 0 then
            bb:paintRect(x + sw - m.right, inner_y, m.right, inner_h, black)
        end
    end
end

local ScreenMargins = WidgetContainer:extend{
    name = "screenmargins",
    is_doc_only = false,
}

function ScreenMargins:init()
    self:loadSettings()
    self:applyViewport()
    self.ui.menu:registerToMainMenu(self)
end

function ScreenMargins:loadSettings()
    local current_screen_size = normalizeSize{
        w = Screen:getScreenWidth(),
        h = Screen:getScreenHeight(),
    }
    if not current_screen_size then
        error("ScreenMargins: invalid screen size reported by device")
    end

    local stored_original_size = G_reader_settings:readSetting(SETTING_ORIGINAL_SIZE)
    local original_screen_size = normalizeSize(stored_original_size)
    local save_original_size = original_screen_size and not sameRawSize(stored_original_size, original_screen_size)

    if not original_screen_size then
        original_screen_size = normalizeSize(G_reader_settings:readSetting(LEGACY_SETTING_ORIGINAL_SIZE))
        save_original_size = original_screen_size ~= nil
    end

    if not original_screen_size then
        original_screen_size = current_screen_size
        save_original_size = true
        logger.dbg("ScreenMargins: Stored original screen size:", original_screen_size)
    elseif original_screen_size.w ~= current_screen_size.w or original_screen_size.h ~= current_screen_size.h then
        -- Swapped dimensions means a rotation — preserve the stored canonical size.
        local is_rotation = (
            original_screen_size.w == current_screen_size.h and
            original_screen_size.h == current_screen_size.w
        )
        if not is_rotation then
            original_screen_size = current_screen_size
            save_original_size = true
            logger.warn("ScreenMargins: Screen size changed, refreshed original size:", original_screen_size)
        end
    end
    self.original_screen_size = original_screen_size

    if save_original_size then
        G_reader_settings:saveSetting(SETTING_ORIGINAL_SIZE, {
            w = original_screen_size.w,
            h = original_screen_size.h,
        })
    end

    -- Preserve any viewport already set by KOReader/device quirks as our baseline.
    -- This keeps installing the plugin from changing devices that already need a
    -- built-in viewport and lets us compensate for the touch hook that KOReader
    -- may already have registered for that baseline.
    self._base_viewport = normalizeViewport(
        Device.viewport,
        original_screen_size.w,
        original_screen_size.h
    ) or fullViewport(original_screen_size)

    local stored_viewport = G_reader_settings:readSetting(SETTING_VIEWPORT)
    local viewport = normalizeViewport(stored_viewport, original_screen_size.w, original_screen_size.h)
    local save_viewport = viewport and not sameRawViewport(stored_viewport, viewport)
    self._has_saved_viewport = stored_viewport ~= nil

    if not viewport then
        local legacy_viewport = G_reader_settings:readSetting(LEGACY_SETTING_VIEWPORT)
        viewport = normalizeViewport(
            legacy_viewport,
            original_screen_size.w,
            original_screen_size.h
        )
        save_viewport = viewport ~= nil
        self._has_saved_viewport = self._has_saved_viewport or legacy_viewport ~= nil
    end

    if not viewport then
        viewport = copyViewport(self._base_viewport)
        -- Overwrite a malformed namespaced value, but avoid creating settings on
        -- a fresh install where neither current nor legacy settings exist.
        save_viewport = self._has_saved_viewport
    end

    self.viewport = viewport
    if save_viewport then
        self:saveSettings()
    end
end

function ScreenMargins:saveSettings()
    self._has_saved_viewport = true
    G_reader_settings:saveSetting(SETTING_VIEWPORT, {
        x = self.viewport.x,
        y = self.viewport.y,
        w = self.viewport.w,
        h = self.viewport.h,
    })
end

function ScreenMargins.promptRestart(_self, reason)
    local message
    if reason == "reset" then
        message = _(
            "Screen margins have been reset to full screen. " ..
            "Please restart KOReader for the changes to take full effect."
        )
    else
        message = _(
            "Screen margins have been updated. " ..
            "Please restart KOReader for the changes to take full effect."
        )
    end
    UIManager:askForRestart(message)
end

function ScreenMargins:applyViewport(force)
    if not self.viewport or not self.original_screen_size then
        return false
    end

    local screen_w = self.original_screen_size.w
    local screen_h = self.original_screen_size.h
    local viewport = normalizeViewport(self.viewport, screen_w, screen_h)

    if not viewport then
        logger.warn("ScreenMargins: Invalid viewport, resetting to full screen")
        viewport = fullViewport(self.original_screen_size)
        self.viewport = viewport
        self:saveSettings()
    else
        self.viewport = viewport
    end

    if not force and not self._has_saved_viewport then
        return true
    end

    local viewport_changed = force or not sameViewport(Device.viewport, self.viewport)
    if not viewport_changed then
        self:_syncTouchHook()
        return true
    end

    if not Screen.setViewport then
        logger.warn("ScreenMargins: Device screen does not support custom viewports")
        return false
    end

    local ok, err = pcall(Screen.setViewport, Screen, self.viewport)
    if not ok then
        logger.warn("ScreenMargins: Failed to apply viewport:", err)
        return false
    end

    Device.viewport = copyViewport(self.viewport)
    self:_syncTouchHook()
    logger.dbg("ScreenMargins: Applied viewport", self.viewport)
    return true
end

-- KOReader may reset the framebuffer viewport on rotation, so re-apply ours.
-- SetViewport operates on physical screen coordinates, which don't change with
-- rotation, so the stored viewport is used as-is.
function ScreenMargins:onSetRotationMode()
    if not self._has_saved_viewport then
        return
    end
    UIManager:nextTick(function()
        self:applyViewport(true)
        UIManager:setDirty("all", "full")
    end)
end

-- Kept for compatibility with any KOReader/device event that may emit this.
function ScreenMargins:onScreenRotate()
    if not self._has_saved_viewport then
        return
    end
    self:applyViewport(true)
    UIManager:setDirty("all", "full")
end

function ScreenMargins:stopPlugin()
    if self._base_viewport and Screen.setViewport then
        local ok, err = pcall(Screen.setViewport, Screen, self._base_viewport)
        if not ok then
            logger.warn("ScreenMargins: Failed to restore base viewport:", err)
        else
            Device.viewport = copyViewport(self._base_viewport)
        end
    end
    if self._touch_hook_params then
        self._touch_hook_params.x = 0
        self._touch_hook_params.y = 0
    end
    UIManager:setDirty("all", "full")
    return true
end

function ScreenMargins:_syncTouchHook()
    if not Device.input or not Device.input.registerEventAdjustHook or
       not Device.input.adjustTouchTranslate or not self.viewport then
        return
    end

    local base_viewport = self._base_viewport or fullViewport(self.original_screen_size)
    local offset_x = base_viewport.x - self.viewport.x
    local offset_y = base_viewport.y - self.viewport.y

    if not self._touch_hook_params then
        if offset_x == 0 and offset_y == 0 then
            return
        end
        self._touch_hook_params = { x = offset_x, y = offset_y }
        Device.input:registerEventAdjustHook(
            Device.input.adjustTouchTranslate,
            self._touch_hook_params
        )
    else
        self._touch_hook_params.x = offset_x
        self._touch_hook_params.y = offset_y
    end
end

function ScreenMargins:_getMargins()
    local screen_w = self.original_screen_size.w
    local screen_h = self.original_screen_size.h
    local viewport = normalizeViewport(self.viewport, screen_w, screen_h) or fullViewport(self.original_screen_size)
    return {
        top    = viewport.y,
        bottom = screen_h - (viewport.y + viewport.h),
        left   = viewport.x,
        right  = screen_w - (viewport.x + viewport.w),
    }
end

function ScreenMargins:_normalizeMargins(margins)
    local screen_w = self.original_screen_size.w
    local screen_h = self.original_screen_size.h
    local normalized = {}

    normalized.top = clamp(margins.top, 0, screen_h - 1)
    normalized.bottom = clamp(margins.bottom, 0, screen_h - normalized.top - 1)
    normalized.left = clamp(margins.left, 0, screen_w - 1)
    normalized.right = clamp(margins.right, 0, screen_w - normalized.left - 1)

    return normalized
end

function ScreenMargins:_setMargins(margins)
    margins = self:_normalizeMargins(margins)
    local screen_w = self.original_screen_size.w
    local screen_h = self.original_screen_size.h
    self.viewport = Geom:new{
        x = margins.left,
        y = margins.top,
        w = screen_w - margins.left - margins.right,
        h = screen_h - margins.top - margins.bottom,
    }
end

function ScreenMargins:addToMainMenu(menu_items)
    menu_items.screenmargins = {
        text = _("Screen margins"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Configure margins"),
                callback = function()
                    self:showConfigDialog()
                end,
            },
            {
                text = _("Reset to full screen"),
                callback = function()
                    self.viewport = fullViewport(self.original_screen_size)
                    self:saveSettings()
                    self:applyViewport()
                    self:promptRestart("reset")
                end,
            },
            {
                text = _("Show current settings"),
                callback = function()
                    local screen_w = self.original_screen_size.w
                    local screen_h = self.original_screen_size.h
                    local m = self:_getMargins()
                    local info = string.format(
                        _(
                            "Screen size: %d × %d\n" ..
                            "Viewport: x=%d, y=%d, w=%d, h=%d\n\n" ..
                            "Margins:\n" ..
                            "  Top: %d px\n" ..
                            "  Bottom: %d px\n" ..
                            "  Left: %d px\n" ..
                            "  Right: %d px"
                        ),
                        screen_w, screen_h,
                        self.viewport.x, self.viewport.y, self.viewport.w, self.viewport.h,
                        m.top, m.bottom, m.left, m.right
                    )
                    UIManager:show(InfoMessage:new{ text = info })
                end,
            },
        },
    }
end

function ScreenMargins:showConfigDialog(restore_point)
    local screen_w = self.original_screen_size.w
    local screen_h = self.original_screen_size.h

    -- Snapshot the viewport so Cancel reverts to the state before the dialog
    -- was first opened. When re-entering from a preview Cancel, the original
    -- restore point is passed through so it isn't lost.
    local viewport_before = restore_point and copyViewport(restore_point) or copyViewport(self.viewport)
    local function showMarginSpinner(title, info, current_value, value_max, on_set)
        UIManager:show(SpinWidget:new{
            title_text = title,
            info_text = info,
            value = current_value,
            value_min = 0,
            value_max = math.max(0, value_max),
            value_step = 1,
            value_hold_step = 10,
            unit = _("px"),
            ok_text = _("Set"),
            callback = function(spin)
                if not spin then return end
                on_set(spin.value)
                -- Only updates self.viewport in memory.
                -- Preview/Apply in the parent dialog drive what happens next.
            end,
        })
    end

    local config_menu
    config_menu = ButtonDialog:new{
        title = _("Configure screen margins"),
        tap_close_callback = function()
            self.viewport = copyViewport(viewport_before)
        end,
        buttons = {
            {
                {
                    text = _("Top"),
                    callback = function()
                        local m = self:_getMargins()
                        showMarginSpinner(
                            _("Top margin"),
                            _("Pixels to trim from the top of the screen."),
                            m.top,
                            screen_h - m.bottom - 1,
                            function(v)
                                m.top = v
                                self:_setMargins(m)
                            end
                        )
                    end,
                },
                {
                    text = _("Bottom"),
                    callback = function()
                        local m = self:_getMargins()
                        showMarginSpinner(
                            _("Bottom margin"),
                            _("Pixels to trim from the bottom of the screen."),
                            m.bottom,
                            screen_h - m.top - 1,
                            function(v)
                                m.bottom = v
                                self:_setMargins(m)
                            end
                        )
                    end,
                },
            },
            {
                {
                    text = _("Left"),
                    callback = function()
                        local m = self:_getMargins()
                        showMarginSpinner(
                            _("Left margin"),
                            _("Pixels to trim from the left of the screen."),
                            m.left,
                            screen_w - m.right - 1,
                            function(v)
                                m.left = v
                                self:_setMargins(m)
                            end
                        )
                    end,
                },
                {
                    text = _("Right"),
                    callback = function()
                        local m = self:_getMargins()
                        showMarginSpinner(
                            _("Right margin"),
                            _("Pixels to trim from the right of the screen."),
                            m.right,
                            screen_w - m.left - 1,
                            function(v)
                                m.right = v
                                self:_setMargins(m)
                            end
                        )
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.viewport = copyViewport(viewport_before)
                        UIManager:close(config_menu)
                    end,
                },
                {
                    text = _("Preview"),
                    callback = function()
                        local overlay = MarginOverlay:new{
                            screen_w = screen_w,
                            screen_h = screen_h,
                            margins  = self:_getMargins(),
                            dimen    = Geom:new{x = 0, y = 0, w = screen_w, h = screen_h},
                        }
                        local confirm_dialog
                        confirm_dialog = ButtonDialog:new{
                            title = _("Black areas show where margins will be applied."),
                            dismissable = false,
                            buttons = {
                                {
                                    {
                                        text = _("Cancel"),
                                        callback = function()
                                            UIManager:close(confirm_dialog)
                                            UIManager:close(overlay)
                                            self:showConfigDialog(viewport_before)
                                            UIManager:setDirty("all", "full")
                                        end,
                                    },
                                    {
                                        text = _("Apply"),
                                        callback = function()
                                            UIManager:close(confirm_dialog)
                                            UIManager:close(overlay)
                                            self:saveSettings()
                                            self:promptRestart()
                                        end,
                                    },
                                },
                            },
                        }
                        UIManager:close(config_menu)
                        UIManager:show(overlay)
                        UIManager:show(confirm_dialog)
                        UIManager:setDirty(overlay, "full")
                    end,
                },
                {
                    text = _("Apply"),
                    callback = function()
                        self:saveSettings()
                        UIManager:close(config_menu)
                        self:promptRestart()
                    end,
                },
            },
        },
    }
    UIManager:show(config_menu)
end

return ScreenMargins
