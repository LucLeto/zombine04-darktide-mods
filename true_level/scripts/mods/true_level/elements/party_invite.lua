local mod = get_mod("true_level")
local ref = "party_invite"
local INVITE_TITLE = "loc_social_party_invite_received_header"
local INVITE_DESCRIPTION = "loc_social_party_invite_received_description"
local GROUP_FINDER_ACCOUNT_ID = "00000000-0000-0000-0000-000000000000"
local math_min = math.min
local pairs = pairs
local string_find = string.find
local type = type

local _invite_bindings = setmetatable({}, { __mode = "k" })
local _invite_params = {}
local _presenting_data = nil
local _popup_handler = nil

local _presence_entry = function(account_id)
    local presence_manager = Managers.presence
    local presences = presence_manager and presence_manager._presences_by_account_id

    return presences and presences[account_id]
end

local _finish_invite_attempt = function(attempts, party_id)
    local attempt = attempts and attempts[party_id]

    if not attempt then
        return nil
    end

    local outstanding = attempt.outstanding - 1

    attempt.outstanding = outstanding

    if outstanding <= 0 then
        attempts[party_id] = nil
    end

    return attempt
end

local _is_invite_mapped = function(binding)
    local party_manager = Managers.party_immaterium
    local invite_popups = party_manager and party_manager._invite_popups

    return invite_popups ~= nil and invite_popups[binding.party_id] == binding.popup_id
end

local _prune_invite_bindings = function()
    for data, binding in pairs(_invite_bindings) do
        if not _is_invite_mapped(binding) then
            _invite_bindings[data] = nil
        end
    end
end

local _set_rendered_state = function(binding, true_levels, enabled)
    binding.true_levels = true_levels
    binding.havoc_rank = true_levels and true_levels.havoc_rank
    binding.enabled = enabled
end

local _decorate = function(data, binding, text)
    local true_levels = mod.get_true_levels(binding.character_id)
    local enabled = mod.is_enabled_feature(ref)

    _set_rendered_state(binding, true_levels, enabled)

    local params = data.description_text_params
    local player_name = params and params.player_name

    if not enabled or not true_levels or type(player_name) ~= "string" or not string_find(text, player_name, 1, true) then
        return text
    end

    local name = mod.replace_level(player_name, true_levels, ref)

    if name == player_name then
        return text
    end

    table.clear(_invite_params)

    for key, value in pairs(params) do
        _invite_params[key] = value
    end

    _invite_params.player_name = name
    mod.debug.timing("ui_rendered", binding.character_id, ref)

    return Localize(data.description_text, true, _invite_params)
end

local _refresh_description = function(handler, data, ui_renderer)
    local widgets_by_name = handler._widgets_by_name
    local description_content = widgets_by_name.description_text.content
    local previous_text = description_content.text

    handler:_set_description_text(Localize(data.description_text, true, data.description_text_params))

    if description_content.text == previous_text then
        return
    end

    local popup_height = handler:_update_popup_text_height(ui_renderer)
    local background_style = widgets_by_name.popup_background.style
    local texture_style = background_style.texture
    local background_height = texture_style.size[2]
    local background_limit = math_min(popup_height, background_height)
    local uvs = texture_style.uvs

    texture_style.size_addition[2] = background_limit - background_height
    uvs[1][2] = 0
    uvs[2][2] = background_limit / background_height
    -- 26: what the enter animation adds to the terminal background
    background_style.terminal.size_addition[2] = popup_height + 26
    widgets_by_name.edge_bottom.offset[2] = popup_height * 0.5
    widgets_by_name.edge_top.offset[2] = -popup_height * 0.5

    handler:_force_update_scenegraph()
end

mod:hook(CLASS.PartyImmateriumManager, "_handle_immaterium_invite", function(func, self, party_id, invite_token, inviter_account_id)
    local attempt = nil

    if party_id and inviter_account_id and inviter_account_id ~= GROUP_FINDER_ACCOUNT_ID then
        local attempts = self.tl_invite_attempts

        if not attempts then
            attempts = {}
            self.tl_invite_attempts = attempts
        end

        local presence = _presence_entry(inviter_account_id)

        attempt = attempts[party_id]

        if attempt then
            attempt.outstanding = attempt.outstanding + 1

            if attempt.account_id ~= inviter_account_id or attempt.presence ~= presence then
                attempt.ambiguous = true
            end
        else
            attempt = {
                account_id = inviter_account_id,
                presence = presence,
                outstanding = 1,
                ambiguous = false,
            }
            attempts[party_id] = attempt
        end
    end

    func(self, party_id, invite_token, inviter_account_id)

    if attempt and not attempt.presence then
        attempt.presence = _presence_entry(inviter_account_id)
    end
end)

mod:hook_safe(CLASS.PartyImmateriumManager, "_decline_party_invite", function(self, party_id, invite_token, answer_code)
    if answer_code ~= nil then
        _finish_invite_attempt(self.tl_invite_attempts, party_id)
    end
end)

mod:hook_safe(CLASS.PartyImmateriumInviteNotificationHandler, "add_invite", function(self, party_id)
    local party_manager = Managers.party_immaterium

    if party_manager and party_manager._invite_notification_handler == self then
        _finish_invite_attempt(party_manager.tl_invite_attempts, party_id)
    end
end)

mod:hook_safe(CLASS.PartyImmateriumManager, "destroy", function(self)
    self.tl_invite_attempts = nil
    table.clear(_invite_bindings)
end)

mod:hook_safe(CLASS.UIManager, "event_show_ui_popup", function(self, data)
    if data.description_text ~= INVITE_DESCRIPTION or data.title_text ~= INVITE_TITLE then
        return
    end

    local party_manager = Managers.party_immaterium
    local invite_popups = party_manager and party_manager._invite_popups

    if not invite_popups then
        return
    end

    local active_popups = self._active_popups
    local popup_id = nil

    for i = 1, #active_popups do
        local popup = active_popups[i]

        if popup.data == data then
            popup_id = popup.id

            break
        end
    end

    if not popup_id then
        return
    end

    local party_id = nil

    for id, invite_popup_id in pairs(invite_popups) do
        if invite_popup_id == popup_id then
            if party_id then
                return
            end

            party_id = id
        end
    end

    if not party_id then
        return
    end

    local attempt = _finish_invite_attempt(party_manager.tl_invite_attempts, party_id)
    local presence = attempt and not attempt.ambiguous and attempt.presence

    if not presence then
        return
    end

    local character_id = presence:character_id()

    if not character_id or character_id == "" then
        return
    end

    _prune_invite_bindings()

    _invite_bindings[data] = {
        party_id = party_id,
        popup_id = popup_id,
        character_id = character_id,
        true_levels = nil,
        havoc_rank = nil,
        enabled = nil,
    }
end)

mod:hook(CLASS.ConstantElementPopupHandler, "_setup_presentation", function(func, self, data, ui_renderer)
    local binding = _invite_bindings[data]

    if binding and not _is_invite_mapped(binding) then
        _invite_bindings[data] = nil
        binding = nil
    end

    if not binding then
        return func(self, data, ui_renderer)
    end

    _presenting_data = data
    _popup_handler = self
    func(self, data, ui_renderer)
    _presenting_data = nil
    mod.synced(ref)
end)

mod:hook(CLASS.ConstantElementPopupHandler, "_set_description_text", function(func, self, text)
    local data = _presenting_data

    if not data then
        local popup = self._active_popup

        data = popup and popup.data
    end

    local binding = data and _invite_bindings[data]

    if binding and type(text) == "string" then
        if _is_invite_mapped(binding) then
            text = _decorate(data, binding, text)
        else
            _invite_bindings[data] = nil
        end
    end

    return func(self, text)
end)

mod:hook_safe(CLASS.ConstantElementPopupHandler, "update", function(self, dt, t, ui_renderer)
    local popup = self._active_popup

    if not popup then
        return
    end

    local data = popup.data
    local binding = _invite_bindings[data]

    if not binding or self._on_enter_anim_id then
        return
    end

    local true_levels = mod.get_true_levels(binding.character_id)
    local enabled = mod.is_enabled_feature(ref)

    if true_levels == binding.true_levels and enabled == binding.enabled
        and (not true_levels or true_levels.havoc_rank == binding.havoc_rank)
        and not mod.should_replace(ref) then
        return
    end

    if popup.closing or not _is_invite_mapped(binding) then
        _invite_bindings[data] = nil

        return
    end

    _set_rendered_state(binding, true_levels, enabled)
    _refresh_description(self, data, ui_renderer)
    mod.synced(ref)
end)

mod.restore_party_invite = function()
    local handler = _popup_handler
    local popup = handler and handler._active_popup
    local data = popup and popup.data
    local binding = data and _invite_bindings[data]

    if binding and not popup.closing and not handler._on_enter_anim_id and _is_invite_mapped(binding) then
        _refresh_description(handler, data, handler:ui_renderer())
    end
end
