--[[--
Dogear Manager plugin for KOReader.

Allows users to swap and resize their digital bookmark (dogear) icon
directly from the Tools menu, without needing a computer.

Custom dogear designs can be placed in either:
    <plugin_folder>/icons/         (bundled with the plugin)
    <koreader_data_dir>/icons/dogears/  (user-added icons)

@module koplugin.DogearManager
--]]--

local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
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

--- Applies the selected design by saving it to settings.
function DogearManager:applyDesign(filename, full_path)
    G_reader_settings:saveSetting("dogear_custom_icon", full_path)
    G_reader_settings:saveSetting("dogear_custom_icon_name", filename)

    UIManager:show(InfoMessage:new{
        text = _("Bookmark design set to: ") .. filename,
        timeout = 2,
    })

    UIManager:scheduleIn(2.5, function()
        self:promptRestart()
    end)
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
            UIManager:show(InfoMessage:new{
                text = _("Bookmark design reset to default."),
                timeout = 2,
            })
            UIManager:scheduleIn(2.5, function()
                self:promptRestart()
            end)
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

--- Shows the size adjustment dialog with a numeric keypad.
function DogearManager:showSizeDialog()
    local current_scale = G_reader_settings:readSetting("dogear_scale_factor") or 1
    local size_dialog

    size_dialog = InputDialog:new{
        title = _("Adjust Bookmark Size"),
        description = _("Enter a size multiplier (e.g., 1 = default, 2 = twice as large, 0.5 = half size):"),
        input = tostring(current_scale),
        input_type = "number",
        input_hint = "1",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(size_dialog)
                    end,
                },
                {
                    text = _("Reset"),
                    callback = function()
                        G_reader_settings:delSetting("dogear_scale_factor")
                        UIManager:close(size_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Bookmark size reset to default."),
                            timeout = 2,
                        })
                        UIManager:scheduleIn(2.5, function()
                            self:promptRestart()
                        end)
                    end,
                },
                {
                    text = _("Apply"),
                    is_enter_default = true,
                    callback = function()
                        local value = size_dialog:getInputValue()
                        if value and type(value) == "number" and value > 0 then
                            G_reader_settings:saveSetting("dogear_scale_factor", value)
                            UIManager:close(size_dialog)

                            UIManager:show(InfoMessage:new{
                                text = _("Bookmark size set to ") .. tostring(value) .. "x",
                                timeout = 2,
                            })

                            UIManager:scheduleIn(2.5, function()
                                self:promptRestart()
                            end)
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Please enter a valid positive number."),
                                timeout = 2,
                            })
                        end
                    end,
                },
            },
        },
    }

    UIManager:show(size_dialog)
    size_dialog:onShowKeyboard()
end

--- Patches KOReader's ReaderDogear widget to apply saved scale and icon settings.
-- ReaderDogear computes its size purely from screen dimensions and never reads
-- dogear_scale_factor or dogear_custom_icon on its own, so we monkey-patch its
-- init() and setupDogear() methods here to inject our values.
function DogearManager:patchReaderDogear()
    local scale_factor = G_reader_settings:readSetting("dogear_scale_factor") or 1
    local custom_icon_path = G_reader_settings:readSetting("dogear_custom_icon")

    -- Nothing to do if both settings are at their defaults.
    if scale_factor == 1 and not custom_icon_path then
        return
    end

    local ReaderDogear = require("apps/reader/modules/readerdogear")

    -- Patch init() to multiply the min/max sizes by the scale factor.
    if scale_factor ~= 1 then
        local orig_init = ReaderDogear.init
        ReaderDogear.init = function(rd_self)
            orig_init(rd_self)
            rd_self.dogear_min_size = math.ceil(rd_self.dogear_min_size * scale_factor)
            rd_self.dogear_max_size = math.ceil(rd_self.dogear_max_size * scale_factor)
            -- Force setupDogear to rebuild with the new sizes.
            rd_self.dogear_size = nil
            rd_self:setupDogear()
        end
    end

    -- Patch setupDogear() to swap the built-in IconWidget for our custom image.
    if custom_icon_path then
        local ImageWidget = require("ui/widget/imagewidget")
        local orig_setupDogear = ReaderDogear.setupDogear
        ReaderDogear.setupDogear = function(rd_self, new_dogear_size)
            orig_setupDogear(rd_self, new_dogear_size)
            -- Replace the freshly-created IconWidget with our custom file.
            if rd_self.icon and rd_self.vgroup then
                rd_self.icon:free()
                rd_self.icon = ImageWidget:new{
                    file = custom_icon_path,
                    width = rd_self.dogear_size,
                    height = rd_self.dogear_size,
                    alpha = true,
                }
                rd_self.vgroup[2] = rd_self.icon
            end
        end
    end

    -- Also apply to the already-initialised instance when the plugin loads
    -- after ReaderDogear (which is the common case inside ReaderUI).
    if self.ui.dogear then
        if scale_factor ~= 1 then
            self.ui.dogear.dogear_min_size = math.ceil(self.ui.dogear.dogear_min_size * scale_factor)
            self.ui.dogear.dogear_max_size = math.ceil(self.ui.dogear.dogear_max_size * scale_factor)
        end
        -- Force a full rebuild so both scale and icon patches take effect.
        self.ui.dogear.dogear_size = nil
        self.ui.dogear:setupDogear()
        self.ui.dogear:resetLayout()
    end
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
                    self:showSizeDialog()
                end,
            },
            {
                text = _("Reset to Original Dogear"),
                keep_menu_open = false,
                callback = function()
                    G_reader_settings:delSetting("dogear_custom_icon")
                    G_reader_settings:delSetting("dogear_custom_icon_name")
                    G_reader_settings:delSetting("dogear_scale_factor")
                    UIManager:show(InfoMessage:new{
                        text = _("Dogear reset to original defaults."),
                        timeout = 2,
                    })
                    UIManager:scheduleIn(2.5, function()
                        self:promptRestart()
                    end)
                end,
            },
        },
    }
end

return DogearManager
