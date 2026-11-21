local mod = get_mod("true_level")
local PopupStyle = require("scripts/ui/view_elements/view_element_player_social_popup/view_element_player_social_popup_styles")
local RosterViewStyles = require("scripts/ui/views/social_menu_roster_view/social_menu_roster_view_styles")
local SocialConstants = require("scripts/managers/data_service/services/social/social_constants")
local SocialMenuSettings = require("scripts/ui/views/social_menu_view/social_menu_view_settings")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local ref = "social_menu"
local PARTY_STATUS_OTHER = SocialConstants.PartyStatus.other
local PLAYER_PANEL_WIDTH = RosterViewStyles.player_panel_size[1]
local NAME_STYLE = RosterViewStyles.blueprints.player_plaque.name_or_activity
local MEMBERSHIP_STYLE = RosterViewStyles.blueprints.player_plaque.party_membership
local MEMBERSHIP_TEXT = string.format("%d/%d ", SocialMenuSettings.max_num_party_members, SocialMenuSettings.max_num_party_members)
local MEMBERSHIP_GAP = 8
local ELLIPSIS = "..."
local LAST_CHARACTER_PATTERN = "[%z\1-\127\194-\244][\128-\191]*$"
local string_find = string.find
local string_gsub = string.gsub
local string_sub = string.sub
local text_size = UIRenderer.text_size

local _names = {}
local _membership_width = nil
local _membership_renderer = nil

local _text_width = function(ui_renderer, text, font_size)
    return (text_size(ui_renderer, text, NAME_STYLE.font_type, font_size))
end

local _max_name_width = function(ui_renderer, has_membership)
    local max_width = PLAYER_PANEL_WIDTH - NAME_STYLE.offset[1] + MEMBERSHIP_STYLE.offset[1]

    if not has_membership then
        return max_width
    end

    if _membership_renderer ~= ui_renderer then
        _membership_width = text_size(ui_renderer, MEMBERSHIP_TEXT, MEMBERSHIP_STYLE.font_type, MEMBERSHIP_STYLE.font_size)
        _membership_renderer = ui_renderer
    end

    return max_width - _membership_width - MEMBERSHIP_GAP
end

local _fit_name = function(ui_renderer, text, character_name, has_membership)
    local max_width = _max_name_width(ui_renderer, has_membership)
    local font_size = NAME_STYLE.font_size_default
    local width = _text_width(ui_renderer, text, font_size)

    if width <= max_width then
        return text
    end

    local min_font_size = NAME_STYLE.font_size_small

    while width > max_width and font_size > min_font_size do
        font_size = font_size - 1
        width = _text_width(ui_renderer, text, font_size)
    end

    local name_start, name_end = string_find(text, character_name, 1, true)

    if width > max_width and name_start then
        local prefix = string_sub(text, 1, name_start - 1)
        local suffix = string_sub(text, name_end + 1)
        local name = character_name

        while width > max_width and name ~= "" do
            name = string_gsub(name, LAST_CHARACTER_PATTERN, "")
            text = prefix .. name .. ELLIPSIS .. suffix
            width = _text_width(ui_renderer, text, font_size)
        end
    end

    local size_markup = "{#size(" .. font_size .. ")}"

    return size_markup .. string_gsub(text, "{#reset%(%)}", "{#reset()}" .. size_markup)
end

-- Social Menu
mod:hook(CLASS.SocialMenuRosterView, "formatted_character_name", function(func, self, player_info)
    local character_name = func(self, player_info)

    if mod.should_replace(ref) then
        table.clear(_names)
        mod.synced(ref)
    elseif not mod.is_enabled_feature(ref) then
        return character_name
    end

    local profile = player_info:profile()
    local character_id = profile and profile.character_id

    if not character_id then
        return character_name
    end

    local true_levels = mod.get_true_levels(character_id)
    local has_membership = player_info:party_status() == PARTY_STATUS_OTHER or player_info:player_activity_id() == "mission"
    local entry = _names[character_id]

    if entry and entry.base == character_name and entry.true_levels == true_levels and entry.has_membership == has_membership
        and (not true_levels or entry.havoc_rank == true_levels.havoc_rank) then
        return entry.text
    end

    local text = character_name

    if true_levels then
        local decorated = mod.replace_level(character_name, true_levels, ref)
        local ui_renderer = self._ui_renderer

        if decorated ~= character_name and ui_renderer then
            text = _fit_name(ui_renderer, decorated, player_info:character_name(), has_membership)
        else
            text = decorated
        end
    end

    local havoc_rank = true_levels and true_levels.havoc_rank

    if entry then
        entry.base = character_name
        entry.text = text
        entry.true_levels = true_levels
        entry.havoc_rank = havoc_rank
        entry.has_membership = has_membership
    else
        _names[character_id] = {
            base = character_name,
            text = text,
            true_levels = true_levels,
            havoc_rank = havoc_rank,
            has_membership = has_membership,
        }
    end

    return text
end)

mod:hook_safe(CLASS.SocialMenuRosterView, "on_exit", function(self)
    table.clear(_names)
    _membership_renderer = nil
end)

-- Selected Player Popup
mod:hook_safe(CLASS.ViewElementPlayerSocialPopup, "_set_player_info", function(self, parent, player_info)
    if not mod.is_enabled_feature(ref) then
        return
    end

    local profile = player_info:profile()
    local character_id = profile and profile.character_id

    if character_id then
        local player_header = self._widgets_by_name.player_header
        local content = player_header.content
        local style = player_header.style
        local true_levels = mod.get_true_levels(character_id)

        if true_levels then
            content.player_display_name = mod.replace_level(content.player_display_name, true_levels, ref)

            local player_display_name = content.player_display_name
            local player_display_name_style = style.player_display_name
            local player_display_name_font_type = player_display_name_style.font_type
            local player_display_name_font_size = player_display_name_style.font_size
            local user_display_name = content.user_display_name
            local user_display_name_style = style.user_display_name
            local user_display_name_font_type = user_display_name_style.font_type
            local user_display_name_font_size = user_display_name_style.font_size
            local ui_renderer = self._ui_renderer
            local ui_renderer_text_size = UIRenderer.text_size
            local player_display_name_width = ui_renderer_text_size(ui_renderer, player_display_name, player_display_name_font_type, player_display_name_font_size)
            local user_display_name_width = ui_renderer_text_size(ui_renderer, user_display_name, user_display_name_font_type, user_display_name_font_size)
            local extra_text_padding = PopupStyle.extra_text_padding
            local text_width = math.max(player_display_name_width, user_display_name_width) + extra_text_padding
            local header_width = self:_scenegraph_size("player_info_header")
            local info_area_width = self:_scenegraph_size("player_info_area")

            if header_width < text_width then
                self:_set_scenegraph_size("player_info_header", math.min(text_width, info_area_width))

                while info_area_width < player_display_name_width + extra_text_padding and player_display_name_font_size > 6 do
                    player_display_name_font_size = player_display_name_font_size - 1
                    player_display_name_width = ui_renderer_text_size(ui_renderer, player_display_name, player_display_name_font_type, player_display_name_font_size)
                end

                player_display_name_style.font_size = player_display_name_font_size

                while info_area_width < user_display_name_width + extra_text_padding and user_display_name_font_size > 6 do
                    user_display_name_font_size = user_display_name_font_size - 1
                    user_display_name_width = ui_renderer_text_size(ui_renderer, user_display_name, user_display_name_font_type, user_display_name_font_size)
                end

                user_display_name_style.font_size = user_display_name_font_size
            end
        end
    end
end)
