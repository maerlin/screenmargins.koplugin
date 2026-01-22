--[[--
Plugin for configuring screen margins/viewport to handle devices with bezels.

@module koplugin.screenmargins
--]]--

local Device = require("device")
local Geom = require("ui/geometry")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

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
    -- Get the original screen size (before any viewport is applied)
    -- Store it if not already stored - this is our "source of truth" for the real screen size
    local original_screen_size = G_reader_settings:readSetting("screen_original_size")
    if not original_screen_size then
        -- First time loading - get the actual screen size from the framebuffer
        -- Use getScreenWidth/getScreenHeight which return the real screen size, not viewport size
        original_screen_size = {
            w = Screen:getScreenWidth(),
            h = Screen:getScreenHeight(),
        }
        G_reader_settings:saveSetting("screen_original_size", original_screen_size)
        logger.dbg("ScreenMargins: Stored original screen size:", original_screen_size)
    end
    self.original_screen_size = original_screen_size
    
    -- Load viewport settings
    local viewport_data = G_reader_settings:readSetting("screen_viewport")
    if viewport_data then
        self.viewport = Geom:new(viewport_data)
    else
        -- Default: use full screen (based on original screen size)
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

function ScreenMargins:applyViewport()
    if not self.viewport or not self.original_screen_size then
        return
    end
    
    local screen_w = self.original_screen_size.w
    local screen_h = self.original_screen_size.h
    
    -- Validate viewport bounds against original screen size
    if self.viewport.x < 0 or self.viewport.x >= screen_w or
       self.viewport.y < 0 or self.viewport.y >= screen_h or
       self.viewport.w <= 0 or self.viewport.h <= 0 or
       self.viewport.x + self.viewport.w > screen_w or
       self.viewport.y + self.viewport.h > screen_h then
        logger.warn("ScreenMargins: Invalid viewport, resetting to full screen")
        self.viewport = Geom:new{x = 0, y = 0, w = screen_w, h = screen_h}
        self:saveSettings()
    end
    
    -- Apply viewport if device supports it
    -- Check if viewport actually changed to avoid unnecessary updates
    local viewport_changed = not Device.viewport or
        Device.viewport.x ~= self.viewport.x or
        Device.viewport.y ~= self.viewport.y or
        Device.viewport.w ~= self.viewport.w or
        Device.viewport.h ~= self.viewport.h
    
    if viewport_changed then
        Device.viewport = self.viewport
        if Screen.setViewport then
            Screen:setViewport(self.viewport)
            -- Adjust touch input if needed
            if Device.input and (self.viewport.x ~= 0 or self.viewport.y ~= 0) then
                -- Remove old hook if exists
                if Device.input.event_adjust_hooks then
                    for i, hook in ipairs(Device.input.event_adjust_hooks) do
                        if hook.func == Device.input.adjustTouchTranslate then
                            table.remove(Device.input.event_adjust_hooks, i)
                            break
                        end
                    end
                end
                -- Add new hook
                Device.input:registerEventAdjustHook(
                    Device.input.adjustTouchTranslate,
                    {x = 0 - self.viewport.x, y = 0 - self.viewport.y}
                )
            end
            logger.dbg("ScreenMargins: Applied viewport", self.viewport)
        end
    end
end

function ScreenMargins:addToMainMenu(menu_items)
    menu_items.screenmargins = {
        text = _("Screen margins"),
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
                    if not self.original_screen_size then
                        self:loadSettings()
                    end
                    self.viewport = Geom:new{
                        x = 0,
                        y = 0,
                        w = self.original_screen_size.w,
                        h = self.original_screen_size.h,
                    }
                    self:saveSettings()
                    self:applyViewport()
                    UIManager:askForRestart(_("Screen margins have been reset to full screen. Please restart KOReader for the changes to take full effect."))
                end,
            },
            {
                text = _("Show current settings"),
                callback = function()
                    if not self.original_screen_size then
                        self:loadSettings()
                    end
                    local screen_w = self.original_screen_size.w
                    local screen_h = self.original_screen_size.h
                    local info = string.format(
                        _("Screen size: %d × %d\nViewport: x=%d, y=%d, w=%d, h=%d\n\nMargins:\n  Top: %d px\n  Bottom: %d px\n  Left: %d px\n  Right: %d px"),
                        screen_w, screen_h,
                        self.viewport.x, self.viewport.y, self.viewport.w, self.viewport.h,
                        self.viewport.y,
                        screen_h - (self.viewport.y + self.viewport.h),
                        self.viewport.x,
                        screen_w - (self.viewport.x + self.viewport.w)
                    )
                    UIManager:show(InfoMessage:new{
                        text = info,
                    })
                end,
            },
        },
    }
end

function ScreenMargins:showConfigDialog()
    if not self.original_screen_size then
        self:loadSettings()
    end
    local screen_w = self.original_screen_size.w
    local screen_h = self.original_screen_size.h
    
    local function showXDialog()
        local x_dialog = SpinWidget:new{
            title_text = _("Viewport X offset"),
            info_text = _("Horizontal offset from left edge of screen."),
            value = self.viewport.x,
            value_min = 0,
            value_max = screen_w - 1,
            value_step = 1,
            value_hold_step = 10,
            unit = _("px"),
            callback = function(spin)
                if not spin then return end
                self.viewport.x = spin.value
                -- Ensure viewport doesn't exceed screen bounds
                if self.viewport.x + self.viewport.w > screen_w then
                    self.viewport.w = screen_w - self.viewport.x
                end
                self:saveSettings()
                self:applyViewport()
                UIManager:askForRestart(_("Screen margins have been updated. Please restart KOReader for the changes to take full effect."))
            end,
        }
        UIManager:show(x_dialog)
    end
    
    local function showYDialog()
        local y_dialog = SpinWidget:new{
            title_text = _("Viewport Y offset"),
            info_text = _("Vertical offset from top edge of screen."),
            value = self.viewport.y,
            value_min = 0,
            value_max = screen_h - 1,
            value_step = 1,
            value_hold_step = 10,
            unit = _("px"),
            callback = function(spin)
                if not spin then return end
                self.viewport.y = spin.value
                -- Ensure viewport doesn't exceed screen bounds
                if self.viewport.y + self.viewport.h > screen_h then
                    self.viewport.h = screen_h - self.viewport.y
                end
                self:saveSettings()
                self:applyViewport()
                UIManager:askForRestart(_("Screen margins have been updated. Please restart KOReader for the changes to take full effect."))
            end,
        }
        UIManager:show(y_dialog)
    end
    
    local function showWidthDialog()
        local max_w = screen_w - self.viewport.x
        local w_dialog = SpinWidget:new{
            title_text = _("Viewport width"),
            info_text = _("Width of the usable screen area."),
            value = self.viewport.w,
            value_min = 1,
            value_max = max_w,
            value_step = 1,
            value_hold_step = 10,
            unit = _("px"),
            callback = function(spin)
                if not spin then return end
                self.viewport.w = spin.value
                -- Ensure viewport doesn't exceed screen bounds
                if self.viewport.x + self.viewport.w > screen_w then
                    self.viewport.x = screen_w - self.viewport.w
                end
                self:saveSettings()
                self:applyViewport()
                UIManager:askForRestart(_("Screen margins have been updated. Please restart KOReader for the changes to take full effect."))
            end,
        }
        UIManager:show(w_dialog)
    end
    
    local function showHeightDialog()
        local max_h = screen_h - self.viewport.y
        local h_dialog = SpinWidget:new{
            title_text = _("Viewport height"),
            info_text = _("Height of the usable screen area."),
            value = self.viewport.h,
            value_min = 1,
            value_max = max_h,
            value_step = 1,
            value_hold_step = 10,
            unit = _("px"),
            callback = function(spin)
                if not spin then return end
                self.viewport.h = spin.value
                -- Ensure viewport doesn't exceed screen bounds
                if self.viewport.y + self.viewport.h > screen_h then
                    self.viewport.y = screen_h - self.viewport.h
                end
                self:saveSettings()
                self:applyViewport()
                UIManager:askForRestart(_("Screen margins have been updated. Please restart KOReader for the changes to take full effect."))
            end,
        }
        UIManager:show(h_dialog)
    end
    
    -- Show a menu to select which parameter to configure
    local ButtonDialog = require("ui/widget/buttondialog")
    local config_menu = ButtonDialog:new{
        title = _("Configure screen margins"),
        buttons = {
            {
                {
                    text = _("X offset (left margin)"),
                    callback = showXDialog,
                },
                {
                    text = _("Y offset (top margin)"),
                    callback = showYDialog,
                },
            },
            {
                {
                    text = _("Width"),
                    callback = showWidthDialog,
                },
                {
                    text = _("Height"),
                    callback = showHeightDialog,
                },
            },
        },
    }
    UIManager:show(config_menu)
end

return ScreenMargins
