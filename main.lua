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
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

-- Full-screen overlay that draws black bars at the margin positions,
-- giving a "papercut frame" preview of how the margins will look without
-- requiring an actual viewport change.
local MarginOverlay = WidgetContainer:extend{}

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
    if m.left > 0 then
        bb:paintRect(x, inner_y, m.left, inner_h, black)
    end
    if m.right > 0 then
        bb:paintRect(x + sw - m.right, inner_y, m.right, inner_h, black)
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
    local original_screen_size = G_reader_settings:readSetting("screen_original_size")
    local current_screen_size = {
        w = Screen:getScreenWidth(),
        h = Screen:getScreenHeight(),
    }
    if not original_screen_size then
        original_screen_size = current_screen_size
        G_reader_settings:saveSetting("screen_original_size", original_screen_size)
        logger.dbg("ScreenMargins: Stored original screen size:", original_screen_size)
    elseif original_screen_size.w ~= current_screen_size.w or original_screen_size.h ~= current_screen_size.h then
        -- Swapped dimensions means a rotation — preserve the stored canonical size.
        local is_rotation = (
            original_screen_size.w == current_screen_size.h and
            original_screen_size.h == current_screen_size.w
        )
        if not is_rotation then
            original_screen_size = current_screen_size
            G_reader_settings:saveSetting("screen_original_size", original_screen_size)
            logger.warn("ScreenMargins: Screen size changed, refreshed original size:", original_screen_size)
        end
    end
    self.original_screen_size = original_screen_size

    local viewport_data = G_reader_settings:readSetting("screen_viewport")
    if viewport_data then
        self.viewport = Geom:new(viewport_data)
    else
        self.viewport = Geom:new{
            x = 0,
            y = 0,
            w = original_screen_size.w,
            h = original_screen_size.h,
        }
    end
end

function ScreenMargins:saveSettings()
    G_reader_settings:saveSetting("screen_viewport", {
        x = self.viewport.x,
        y = self.viewport.y,
        w = self.viewport.w,
        h = self.viewport.h,
    })
end

function ScreenMargins:promptRestart(reason)
    local message
    if reason == "reset" then
        message = _("Screen margins have been reset to full screen. Please restart KOReader for the changes to take full effect.")
    else
        message = _("Screen margins have been updated. Please restart KOReader for the changes to take full effect.")
    end
    UIManager:askForRestart(message)
end

function ScreenMargins:applyViewport()
    if not self.viewport or not self.original_screen_size then return end

    local screen_w = self.original_screen_size.w
    local screen_h = self.original_screen_size.h

    if self.viewport.x < 0 or self.viewport.x >= screen_w or
       self.viewport.y < 0 or self.viewport.y >= screen_h or
       self.viewport.w <= 0 or self.viewport.h <= 0 or
       self.viewport.x + self.viewport.w > screen_w or
       self.viewport.y + self.viewport.h > screen_h then
        logger.warn("ScreenMargins: Invalid viewport, resetting to full screen")
        self.viewport = Geom:new{x = 0, y = 0, w = screen_w, h = screen_h}
        self:saveSettings()
    end

    local viewport_changed = not Device.viewport or
        Device.viewport.x ~= self.viewport.x or
        Device.viewport.y ~= self.viewport.y or
        Device.viewport.w ~= self.viewport.w or
        Device.viewport.h ~= self.viewport.h

    if viewport_changed then
        Device.viewport = self.viewport
        if Screen.setViewport then
            Screen:setViewport(self.viewport)
            if Device.input then
                self:_unregisterTouchHook()
                if self.viewport.x ~= 0 or self.viewport.y ~= 0 then
                    self:_registerTouchHook()
                end
            end
            logger.dbg("ScreenMargins: Applied viewport", self.viewport)
        end
    end
end

function ScreenMargins:_registerTouchHook()
    self._touch_hook_params = {
        x = -self.viewport.x,
        y = -self.viewport.y,
        _screenmargins = true,
    }
    Device.input:registerEventAdjustHook(
        Device.input.adjustTouchTranslate,
        self._touch_hook_params
    )
end

function ScreenMargins:_unregisterTouchHook()
    if not self._touch_hook_params or not Device.input.event_adjust_hooks then return end
    for i = #Device.input.event_adjust_hooks, 1, -1 do
        if Device.input.event_adjust_hooks[i].params == self._touch_hook_params then
            table.remove(Device.input.event_adjust_hooks, i)
            break
        end
    end
    self._touch_hook_params = nil
end

function ScreenMargins:_getMargins()
    local screen_w = self.original_screen_size.w
    local screen_h = self.original_screen_size.h
    return {
        top    = self.viewport.y,
        bottom = screen_h - (self.viewport.y + self.viewport.h),
        left   = self.viewport.x,
        right  = screen_w - (self.viewport.x + self.viewport.w),
    }
end

function ScreenMargins:_setMargins(margins)
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
                    self.viewport = Geom:new{
                        x = 0,
                        y = 0,
                        w = self.original_screen_size.w,
                        h = self.original_screen_size.h,
                    }
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
                        _("Screen size: %d × %d\nViewport: x=%d, y=%d, w=%d, h=%d\n\nMargins:\n  Top: %d px\n  Bottom: %d px\n  Left: %d px\n  Right: %d px"),
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
    local viewport_before = restore_point or Geom:new{
        x = self.viewport.x,
        y = self.viewport.y,
        w = self.viewport.w,
        h = self.viewport.h,
    }
    local function showMarginSpinner(title, info, current_value, value_max, on_set)
        UIManager:show(SpinWidget:new{
            title_text = title,
            info_text = info,
            value = current_value,
            value_min = 0,
            value_max = value_max,
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
                        self.viewport = viewport_before
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
