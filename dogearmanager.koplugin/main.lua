--[[--
Dogear Manager plugin for KOReader.

Allows users to swap and resize their digital bookmark (dogear) icon
directly from the Tools menu, without needing a computer.

Custom dogear designs can be placed in either:
    <plugin_folder>/icons/         (bundled with the plugin)
    <koreader_data_dir>/icons/dogears/  (user-added icons)

@module koplugin.DogearManager
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local DogearManager = WidgetContainer:extend{
    name = "dogearmanager",
    is_doc_only = false,
}

-- Supported image extensions for dogear designs.
local SUPPORTED_EXTENSIONS = {
    [".png"] = true,
    [".svg"] = true,
    [".alpha"] = true,
    [".bmp"] = true,
    [".jpg"] = true,
    [".jpeg"] = true,
}

--- Returns the path to the user's dogear icons folder.
function DogearManager:getIconsDir()
    return DataStorage:getDataDir() .. "/icons/dogears"
end

--- Returns the path to the icons folder bundled inside the plugin folder.
function DogearManager:getPluginIconsDir()
    return self.path .. "/icons"
end

--- Scans a directory and appends valid image entries to the given list.
-- Each entry is a table with keys: text (filename) and path (full path).
local function scanDir(dir, list, seen)
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok then return end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local ext = entry:match("(%.[^%.]+)$")
            if ext and SUPPORTED_EXTENSIONS[ext:lower()] and not seen[entry] then
                seen[entry] = true
                table.insert(list, { text = entry, path = dir .. "/" .. entry })
            end
        end
    end
end

--- Scans both icon folders and returns a list of {text, path} tables.
function DogearManager:scanDesigns()
    local designs = {}
    local seen = {}
    -- Plugin-bundled icons come first; user icons can override by filename.
    scanDir(self:getPluginIconsDir(), designs, seen)
    scanDir(self:getIconsDir(), designs, seen)
    table.sort(designs, function(a, b) return a.text < b.text end)
    return designs
end

--- Prompts the user to restart KOReader so changes take effect.
function DogearManager:promptRestart()
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to restart now to see the changes?"),
        ok_text = _("Restart"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            if Device:canRestart() then
                UIManager:restartKOReader()
            else
                UIManager:show(InfoMessage:new{
                    text = _("Automatic restart is not supported on this device. Please restart KOReader manually."),
                })
            end
        end,
    })
end

--- Forces the live dogear widget to rebuild with current settings.
function DogearManager:applyDogearToLive()
    if self.ui and self.ui.dogear then
        self.ui.dogear.dogear_size = nil
        self.ui.dogear:setupDogear()
        self.ui.dogear:resetLayout()
    end
end

--- Applies the selected design by saving it to settings.
function DogearManager:applyDesign(filename, full_path)
    G_reader_settings:saveSetting("dogear_custom_icon", full_path)
    G_reader_settings:saveSetting("dogear_custom_icon_name", filename)

    self:applyDogearToLive()
    self:promptRestart()
end

--- Shows the design selection submenu.
function DogearManager:showDesignMenu()
    local designs = self:scanDesigns()

    if #designs == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No custom bookmark designs found.\n\nPlace image files (.png, .svg, .bmp, .jpg) in:\n")
                .. self:getPluginIconsDir() .. "\n" .. _("or") .. "\n"
                .. self:getIconsDir(),
        })
        return
    end

    -- Build menu items from scanned designs.
    local menu_items = {}
    for _, design in ipairs(designs) do
        local filename = design.text
        local full_path = design.path
        table.insert(menu_items, {
            text = filename,
            callback = function()
                self:applyDesign(filename, full_path)
            end,
        })
    end

    -- Add an option to reset to the default dogear.
    table.insert(menu_items, {
        text = _("-- Reset to Default --"),
        callback = function()
            G_reader_settings:delSetting("dogear_custom_icon")
            G_reader_settings:delSetting("dogear_custom_icon_name")
            self:applyDogearToLive()
            self:promptRestart()
        end,
    })

    local Menu = require("ui/widget/menu")
    local Screen = Device.screen

    local design_menu = Menu:new{
        title = _("Change Bookmark Design"),
        item_table = menu_items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function()
            UIManager:close(design_menu)
        end,
    }

    UIManager:show(design_menu)
end

--- Shows the size adjustment dialog with a slider and live icon preview.
-- Builds (or rebuilds) the dialog at the given scale value.
-- @param scale number  current scale factor (default: read from settings)
function DogearManager:showSizeSlider(scale)
    local Screen = Device.screen

    -- Read saved scale if not provided; clamp and round to nearest 0.1.
    if not scale then
        scale = G_reader_settings:readSetting("dogear_scale_factor") or 1
    end
    scale = math.floor(scale * 10 + 0.5) / 10
    scale = math.max(0.5, math.min(4.0, scale))

    -- Base preview size – matches the real dogear_max_size formula from
    -- ReaderDogear: math.ceil(min(W, H) / 32), then scaled.
    local screen_min = math.min(Screen:getWidth(), Screen:getHeight())
    local base_px    = math.ceil(screen_min / 32)
    local preview_px = math.max(12, math.ceil(base_px * scale))

    local custom_icon = G_reader_settings:readSetting("dogear_custom_icon")

    -- Build the icon preview widget.
    local preview_widget
    if custom_icon and lfs.attributes(custom_icon, "mode") == "file" then
        preview_widget = ImageWidget:new{
            file   = custom_icon,
            width  = preview_px,
            height = preview_px,
            alpha  = true,
        }
    else
        -- Solid black square as a stand-in for the dogear corner.
        preview_widget = FrameContainer:new{
            width      = preview_px,
            height     = preview_px,
            background = Blitbuffer.COLOR_BLACK,
            bordersize = 0,
            padding    = 0,
        }
    end

    -- top_widget is the root widget passed to UIManager:show / close.
    -- Declare it here so button closures can reference it.
    local top_widget

    -- Close the dialog and rebuild at a new scale (live-update pattern).
    -- Deferred via nextTick so the rebuild happens after current event handling.
    local function rebuild(new_scale)
        UIManager:close(top_widget)
        UIManager:nextTick(function()
            self:showSizeSlider(new_scale)
        end)
    end

    -- ── layout helpers ─────────────────────────────────────────────────
    local dialog_w  = math.floor(Screen:getWidth() * 0.82)
    local pad       = Size.padding.large
    local inner_w   = dialog_w - pad * 2
    -- Fixed preview area height keeps the dialog from jumping in size.
    local preview_h = base_px * 4 + pad * 2
    local hspan     = Size.span.horizontal_default
    local vspan_lg  = Size.span.vertical_large
    local vspan_def = Size.span.vertical_default

    -- ── controls row: −0.5  −  [value]  +  +0.5 ───────────────────────
    local step_btn_w  = math.floor(inner_w / 6)
    local value_box_w = math.floor(inner_w / 4)

    local controls_row = HorizontalGroup:new{
        align = "center",
        Button:new{
            text     = "-0.5",
            width    = step_btn_w,
            callback = function()
                rebuild(math.max(0.5, math.floor((scale - 0.5) * 10 + 0.5) / 10))
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text     = "-",
            width    = step_btn_w,
            callback = function()
                rebuild(math.max(0.5, math.floor((scale - 0.1) * 10 + 0.5) / 10))
            end,
        },
        HorizontalSpan:new{ width = hspan },
        CenterContainer:new{
            dimen = Geom:new{ w = value_box_w, h = Screen:scaleBySize(32) },
            TextWidget:new{
                text = string.format("%.1fx", scale),
                face = Font:getFace("cfont", 22),
                bold = true,
            },
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text     = "+",
            width    = step_btn_w,
            callback = function()
                rebuild(math.min(4.0, math.floor((scale + 0.1) * 10 + 0.5) / 10))
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text     = "+0.5",
            width    = step_btn_w,
            callback = function()
                rebuild(math.min(4.0, math.floor((scale + 0.5) * 10 + 0.5) / 10))
            end,
        },
    }

    -- ── action row: Cancel  Reset  Apply ───────────────────────────────
    local actions_row = HorizontalGroup:new{
        align = "center",
        Button:new{
            text     = _("Cancel"),
            callback = function()
                UIManager:close(top_widget)
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text     = _("Reset"),
            callback = function()
                G_reader_settings:delSetting("dogear_scale_factor")
                UIManager:close(top_widget)
                self:applyDogearToLive()
                self:promptRestart()
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text     = _("Apply"),
            callback = function()
                G_reader_settings:saveSetting("dogear_scale_factor", scale)
                UIManager:close(top_widget)
                self:applyDogearToLive()
                self:promptRestart()
            end,
        },
    }

    -- ── assemble dialog ────────────────────────────────────────────────
    local dialog_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius     = Size.radius.window,
        padding    = pad,
        VerticalGroup:new{
            align = "center",
            -- Title
            TextWidget:new{
                text = _("Adjust Bookmark Size"),
                face = Font:getFace("cfont", 22),
                bold = true,
            },
            VerticalSpan:new{ width = vspan_lg },
            -- Preview label
            TextWidget:new{
                text = _("Preview (tap \194\177 to resize):"),
                face = Font:getFace("cfont", 16),
            },
            VerticalSpan:new{ width = vspan_def },
            -- Preview area (fixed height so dialog doesn't jump)
            CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = preview_h },
                preview_widget,
            },
            VerticalSpan:new{ width = vspan_lg },
            -- Scale controls
            controls_row,
            VerticalSpan:new{ width = vspan_lg },
            -- Action buttons
            actions_row,
        },
    }

    -- Wrap in InputContainer so KOReader dispatches gesture events.
    -- Override onGesture to forward the raw gesture down the widget tree
    -- via handleEvent; this lets child Button widgets receive the tap
    -- through their own onGesture → TapSelect path.
    top_widget = InputContainer:new{
        modal = true,
        dimen = Screen:getSize(),
    }
    top_widget[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        MovableContainer:new{ dialog_frame },
    }

    if Device:isTouchDevice() then
        function top_widget:onGesture(ev)
            -- Forward the raw gesture to children so Buttons can match
            -- their TapSelect gesture and fire callbacks.
            if self[1] and self[1]:handleEvent(Event:new("Gesture", ev)) then
                return true
            end
            -- Tap outside the dialog dismisses it.
            if ev.ges == "tap" and dialog_frame.dimen then
                if ev.pos:notIntersectWith(dialog_frame.dimen) then
                    UIManager:close(self)
                    return true
                end
            end
        end
    end

    UIManager:show(top_widget)
end

--- Patches KOReader's ReaderDogear widget to apply saved scale and icon settings.
-- We monkey-patch setupDogear() once so that every call reads the current
-- dogear_scale_factor and dogear_custom_icon settings and applies them.
-- A guard flag on the class prevents double-patching when the plugin loads
-- in both FileManager and ReaderUI contexts.
function DogearManager:patchReaderDogear()
    local ReaderDogear = require("apps/reader/modules/readerdogear")

    if not ReaderDogear._dm_patched then
        ReaderDogear._dm_patched = true
        local orig_setupDogear = ReaderDogear.setupDogear
        ReaderDogear.setupDogear = function(rd_self, new_dogear_size)
            local sf = G_reader_settings:readSetting("dogear_scale_factor") or 1
            local icon_path = G_reader_settings:readSetting("dogear_custom_icon")

            -- Scale the requested size (or the default max).
            if sf ~= 1 then
                if new_dogear_size then
                    new_dogear_size = math.ceil(new_dogear_size * sf)
                else
                    new_dogear_size = math.ceil(rd_self.dogear_max_size * sf)
                end
            end

            orig_setupDogear(rd_self, new_dogear_size)

            -- Swap in custom icon if configured.
            if icon_path and lfs.attributes(icon_path, "mode") == "file"
               and rd_self.icon and rd_self.vgroup then
                rd_self.icon:free()
                rd_self.icon = ImageWidget:new{
                    file   = icon_path,
                    width  = rd_self.dogear_size,
                    height = rd_self.dogear_size,
                    alpha  = true,
                }
                rd_self.vgroup[2] = rd_self.icon
            end
        end
    end

    -- Apply to the already-initialised instance.
    self:applyDogearToLive()
end

function DogearManager:init()
    self.ui.menu:registerToMainMenu(self)
    self:patchReaderDogear()
end

function DogearManager:addToMainMenu(menu_items)
    menu_items.dogear_manager = {
        text = _("Dogear Manager"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Change Bookmark Design"),
                keep_menu_open = false,
                callback = function()
                    self:showDesignMenu()
                end,
            },
            {
                text = _("Adjust Bookmark Size"),
                keep_menu_open = false,
                callback = function()
                    self:showSizeSlider()
                end,
            },
            {
                text = _("Reset to Original Dogear"),
                keep_menu_open = false,
                callback = function()
                    G_reader_settings:delSetting("dogear_custom_icon")
                    G_reader_settings:delSetting("dogear_custom_icon_name")
                    G_reader_settings:delSetting("dogear_scale_factor")
                    self:applyDogearToLive()
                    self:promptRestart()
                end,
            },
        },
    }
end

return DogearManager
