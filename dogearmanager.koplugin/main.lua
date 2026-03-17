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
local logger = require("logger")
local _ = require("gettext")

local Screen = Device.screen

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
            G_reader_settings:flush()
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

--- Shows the size/margin adjustment dialog with a corner preview.
function DogearManager:showSizeSlider(scale, margin_top, margin_right, icon_idx)
    -- Read saved settings if not provided.
    if not scale then
        scale = G_reader_settings:readSetting("dogear_scale_factor") or 1
    end
    if not margin_top then
        margin_top = G_reader_settings:readSetting("dogear_margin_top") or 0
    end
    if not margin_right then
        margin_right = G_reader_settings:readSetting("dogear_margin_right") or 0
    end

    -- Clamp scale.
    scale = math.floor(scale * 10 + 0.5) / 10
    scale = math.max(0.5, math.min(4.0, scale))

    -- Base preview size – matches the real dogear_max_size formula from
    -- ReaderDogear: math.ceil(min(W, H) / 32), then scaled.
    local screen_min  = math.min(Screen:getWidth(), Screen:getHeight())
    local base_px     = math.ceil(screen_min / 32)
    local preview_px  = math.max(12, math.ceil(base_px * scale))

    -- Margin step and maximum.
    local margin_step = math.max(2, math.ceil(base_px / 4))
    local margin_max  = math.floor(screen_min / 4)

    -- Clamp margins.
    margin_top   = math.max(0, math.min(margin_max, margin_top))
    margin_right = math.max(0, math.min(margin_max, margin_right))

    -- Scan available designs for the icon selector.
    -- icon_idx == 0 means "use default dogear"; 1..N index into designs list.
    local designs = self:scanDesigns()
    if icon_idx == nil then
        local saved_icon = G_reader_settings:readSetting("dogear_custom_icon")
        icon_idx = 0
        if saved_icon then
            for i, d in ipairs(designs) do
                if d.path == saved_icon then
                    icon_idx = i
                    break
                end
            end
        end
    end

    local selected_icon_path = (icon_idx > 0 and designs[icon_idx]) and designs[icon_idx].path or nil
    local selected_icon_name = (icon_idx > 0 and designs[icon_idx]) and designs[icon_idx].text or nil

    local custom_icon = selected_icon_path

    -- Returns a fresh icon widget at the given pixel size.
    local function makeIconWidget(sz)
        if custom_icon and lfs.attributes(custom_icon, "mode") == "file" then
            return ImageWidget:new{
                file   = custom_icon,
                width  = sz,
                height = sz,
                alpha  = true,
            }
        else
            -- Solid black square as a stand-in for the dogear corner.
            return FrameContainer:new{
                width      = sz,
                height     = sz,
                background = Blitbuffer.COLOR_BLACK,
                bordersize = 0,
                padding    = 0,
            }
        end
    end

    -- top_widget is the root widget passed to UIManager:show / close.
    local top_widget

    -- Guard against queuing multiple rebuilds from rapid button taps.
    local rebuild_pending = false

    -- Close and rebuild at new values (live-update pattern).
    local function rebuild(ns, nmt, nmr, ni)
        if rebuild_pending then return end
        rebuild_pending = true
        UIManager:close(top_widget)
        UIManager:scheduleIn(0, function()
            self:showSizeSlider(ns, nmt, nmr, ni)
        end)
    end

    -- ── layout helpers ─────────────────────────────────────────────────
    local dialog_w  = math.floor(Screen:getWidth() * 0.80)
    local pad       = Size.padding.default
    local inner_w   = dialog_w - pad * 2
    local hspan     = Size.span.horizontal_default
    local vspan_lg  = Size.span.vertical_default
    local vspan_def = math.floor(Size.span.vertical_default / 2)

    -- ── corner preview ─────────────────────────────────────────────────
    local corner_h = base_px * 5 + pad * 2
    local corner_w = inner_w

    local repr_h = Screen:getHeight() / 6
    local repr_w = Screen:getWidth()

    local prev_mt   = math.floor(margin_top   * corner_h / repr_h)
    local prev_mr   = math.floor(margin_right * corner_w / repr_w)
    local prev_icon = math.max(8, math.floor(preview_px * corner_h / repr_h))

    -- Keep icon fully inside the preview area.
    prev_mt   = math.min(prev_mt,   corner_h - prev_icon - 2)
    prev_mr   = math.min(prev_mr,   corner_w - prev_icon - 2)
    local left_fill = math.max(0, corner_w - prev_mr - prev_icon)

    local corner_preview = FrameContainer:new{
        width      = corner_w,
        height     = corner_h,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        bordersize = Size.border.default,
        padding    = 0,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = math.max(0, prev_mt) },
            HorizontalGroup:new{
                align = "top",
                HorizontalSpan:new{ width = left_fill },
                makeIconWidget(prev_icon),
            },
        },
    }

    -- ── scale controls row ─────────────────────────────────────────────
    local btn_h       = Screen:scaleBySize(36)
    local step_btn_w  = math.floor(inner_w / 5)
    local value_box_w = inner_w - step_btn_w * 4 - hspan * 4

    local scale_row = HorizontalGroup:new{
        align = "center",
        Button:new{
            text     = "−.5",
            width    = step_btn_w,
            callback = function()
                rebuild(math.max(0.5, math.floor((scale - 0.5) * 10 + 0.5) / 10),
                        margin_top, margin_right, icon_idx)
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text     = "−",
            width    = step_btn_w,
            callback = function()
                rebuild(math.max(0.5, math.floor((scale - 0.1) * 10 + 0.5) / 10),
                        margin_top, margin_right, icon_idx)
            end,
        },
        HorizontalSpan:new{ width = hspan },
        CenterContainer:new{
            dimen = Geom:new{ w = value_box_w, h = btn_h },
            TextWidget:new{
                text = string.format("%.1f×", scale),
                face = Font:getFace("cfont", 20),
                bold = true,
            },
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text     = "+",
            width    = step_btn_w,
            callback = function()
                rebuild(math.min(4.0, math.floor((scale + 0.1) * 10 + 0.5) / 10),
                        margin_top, margin_right, icon_idx)
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text     = "+.5",
            width    = step_btn_w,
            callback = function()
                rebuild(math.min(4.0, math.floor((scale + 0.5) * 10 + 0.5) / 10),
                        margin_top, margin_right, icon_idx)
            end,
        },
    }

    -- ── margin control rows ─────────────────────────────────────────────
    local label_w = math.floor(inner_w * 0.18)
    local mbtn_w  = math.floor(inner_w / 6)
    local mval_w  = inner_w - label_w - mbtn_w * 2 - hspan * 3

    local function marginRow(label, value, on_dec, on_inc)
        return HorizontalGroup:new{
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{ w = label_w, h = btn_h },
                TextWidget:new{
                    text = label,
                    face = Font:getFace("cfont", 15),
                },
            },
            HorizontalSpan:new{ width = hspan },
            Button:new{
                text     = "−",
                width    = mbtn_w,
                callback = on_dec,
            },
            CenterContainer:new{
                dimen = Geom:new{ w = mval_w, h = btn_h },
                TextWidget:new{
                    text = value .. "px",
                    face = Font:getFace("cfont", 18),
                    bold = true,
                },
            },
            Button:new{
                text     = "+",
                width    = mbtn_w,
                callback = on_inc,
            },
        }
    end

    local top_margin_row = marginRow(
        _("Top"),
        margin_top,
        function()
            rebuild(scale, math.max(0, margin_top - margin_step), margin_right, icon_idx)
        end,
        function()
            rebuild(scale, math.min(margin_max, margin_top + margin_step), margin_right, icon_idx)
        end
    )

    local right_margin_row = marginRow(
        _("Right"),
        margin_right,
        function()
            rebuild(scale, margin_top, math.max(0, margin_right - margin_step), icon_idx)
        end,
        function()
            rebuild(scale, margin_top, math.min(margin_max, margin_right + margin_step), icon_idx)
        end
    )

    -- ── icon selector row ──────────────────────────────────────────────
    local icon_btn_w  = step_btn_w
    local icon_name_w = inner_w - icon_btn_w * 2 - hspan * 2
    local icon_display = selected_icon_name or _("default")

    local icon_row = HorizontalGroup:new{
        align = "center",
        Button:new{
            text     = "\226\151\128", -- ◀
            width    = icon_btn_w,
            enabled  = #designs > 0,
            callback = function()
                local new_idx = (icon_idx == 0) and #designs or (icon_idx - 1)
                rebuild(scale, margin_top, margin_right, new_idx)
            end,
        },
        HorizontalSpan:new{ width = hspan },
        CenterContainer:new{
            dimen = Geom:new{ w = icon_name_w, h = btn_h },
            TextWidget:new{
                text      = icon_display,
                face      = Font:getFace("cfont", 15),
                max_width = icon_name_w,
            },
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text     = "\226\150\182", -- ▶
            width    = icon_btn_w,
            enabled  = #designs > 0,
            callback = function()
                local new_idx = (icon_idx >= #designs) and 0 or (icon_idx + 1)
                rebuild(scale, margin_top, margin_right, new_idx)
            end,
        },
    }

    -- ── action row ─────────────────────────────────────────────────────
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
                G_reader_settings:delSetting("dogear_margin_top")
                G_reader_settings:delSetting("dogear_margin_right")
                G_reader_settings:delSetting("dogear_custom_icon")
                G_reader_settings:delSetting("dogear_custom_icon_name")
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
                G_reader_settings:saveSetting("dogear_margin_top", margin_top)
                G_reader_settings:saveSetting("dogear_margin_right", margin_right)
                if selected_icon_path then
                    G_reader_settings:saveSetting("dogear_custom_icon", selected_icon_path)
                    G_reader_settings:saveSetting("dogear_custom_icon_name", selected_icon_name)
                else
                    G_reader_settings:delSetting("dogear_custom_icon")
                    G_reader_settings:delSetting("dogear_custom_icon_name")
                end
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
            TextWidget:new{
                text = _("Bookmark Size & Margins"),
                face = Font:getFace("cfont", 18),
                bold = true,
            },
            VerticalSpan:new{ width = vspan_lg },
            corner_preview,
            VerticalSpan:new{ width = vspan_lg },
            scale_row,
            VerticalSpan:new{ width = vspan_lg },
            icon_row,
            VerticalSpan:new{ width = vspan_lg },
            top_margin_row,
            VerticalSpan:new{ width = vspan_def },
            right_margin_row,
            VerticalSpan:new{ width = vspan_lg },
            actions_row,
        },
    }

    -- Wrap in InputContainer so KOReader dispatches gesture events.
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
            if self[1] and self[1]:handleEvent(Event:new("Gesture", ev)) then
                return true
            end
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

--- Patches KOReader's ReaderDogear widget to apply saved scale, icon, and
-- margin settings. Wrapped in pcall so a failure here never prevents
-- documents from opening.
function DogearManager:patchReaderDogear()
    local ok, err = pcall(function()
        local ReaderDogear = require("apps/reader/modules/readerdogear")

        if not ReaderDogear._dm_patched then
            ReaderDogear._dm_patched = true
            local orig_setupDogear = ReaderDogear.setupDogear
            local orig_resetLayout = ReaderDogear.resetLayout

            local function applyMarginOffset(rd_self)
                local mt = G_reader_settings:readSetting("dogear_margin_top")   or 0
                local mr = G_reader_settings:readSetting("dogear_margin_right") or 0
                if rd_self[1] and rd_self[1].dimen then
                    rd_self[1].dimen.w = Screen:getWidth() - mr
                end
                if mt ~= 0 and rd_self.top_pad and rd_self.vgroup then
                    rd_self.top_pad.width = (rd_self.dogear_y_offset or 0) + mt
                    rd_self[1].dimen.h = (rd_self.dogear_y_offset or 0) + rd_self.dogear_size + mt
                    rd_self.vgroup:resetLayout()
                end
            end

            ReaderDogear.setupDogear = function(rd_self, new_dogear_size)
                local sf = G_reader_settings:readSetting("dogear_scale_factor") or 1
                local icon_path = G_reader_settings:readSetting("dogear_custom_icon")

                if sf ~= 1 then
                    if new_dogear_size then
                        new_dogear_size = math.ceil(new_dogear_size * sf)
                    elseif rd_self.dogear_max_size then
                        new_dogear_size = math.ceil(rd_self.dogear_max_size * sf)
                    end
                end

                orig_setupDogear(rd_self, new_dogear_size)

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

                applyMarginOffset(rd_self)
            end

            if orig_resetLayout then
                ReaderDogear.resetLayout = function(rd_self, ...)
                    orig_resetLayout(rd_self, ...)
                    applyMarginOffset(rd_self)
                end
            end

            local orig_updateDogearOffset = ReaderDogear.updateDogearOffset
            if orig_updateDogearOffset then
                ReaderDogear.updateDogearOffset = function(rd_self, ...)
                    orig_updateDogearOffset(rd_self, ...)
                    applyMarginOffset(rd_self)
                end
            end
        end

    end)

    if not ok then
        logger.err("DogearManager: patchReaderDogear failed:", err)
    end
    self:applyDogearToLive()
end

function DogearManager:init()
    self.ui.menu:registerToMainMenu(self)
end

function DogearManager:onReaderReady()
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
                text = _("Adjust Bookmark Size & Margins"),
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
                    G_reader_settings:delSetting("dogear_margin_top")
                    G_reader_settings:delSetting("dogear_margin_right")
                    self:applyDogearToLive()
                    UIManager:show(InfoMessage:new{
                        text    = _("Dogear reset to original defaults."),
                        timeout = 2,
                    })
                end,
            },
        },
    }
end

return DogearManager
