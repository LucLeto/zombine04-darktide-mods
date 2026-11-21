local mod = get_mod("true_level")
local ref = "party_invite"
local GROUP_FINDER_ACCOUNT_ID = "00000000-0000-0000-0000-000000000000"
local math_min = math.min
local pairs = pairs
local string_find = string.find
local type = type

local _party_popups = {}
local _popup_bindings = setmetatable({}, { __mode = "k" })
local _popup_params = {}
local _presenting_data = nil
local _popup_handler = nil

local _presence_entry = function(account_id)
    local presence_manager = Managers.presence
    local presences = presence_manager and presence_manager._presences_by_account_id

    return presences and presences[account_id]
end

local _finish_popup_attempt = function(attempts, key)
    local attempt = attempts and attempts[key]

    if not attempt then
        return nil
    end

    local outstanding = attempt.outstanding - 1

    attempt.outstanding = outstanding

    if outstanding <= 0 then
        attempts[key] = nil
    end

    return attempt
end

local _is_popup_mapped = function(binding)
    local party_manager = Managers.party_immaterium
    local popups = party_manager and party_manager[binding.popups]

    return popups ~= nil and popups[binding.key] == binding.popup_id
end

local _prune_popup_bindings = function()
    for data, binding in pairs(_popup_bindings) do
        if not _is_popup_mapped(binding) then
            _popup_bindings[data] = nil
        end
    end
end

local _set_rendered_state = function(binding, true_levels, enabled)
    binding.true_levels = true_levels
    binding.havoc_rank = true_levels and true_levels.havoc_rank
    binding.enabled = enabled
end

local _decorate = function(data, binding, text)
    local reference = binding.ref
    local true_levels = mod.get_true_levels(binding.character_id)
    local enabled = mod.is_enabled_feature(reference)

    _set_rendered_state(binding, true_levels, enabled)

    local params = data.description_text_params
    local player_name = params and params.player_name

    if not enabled or not true_levels or type(player_name) ~= "string" or not string_find(text, player_name, 1, true) then
        return text
    end

    local name = mod.replace_level(player_name, true_levels, reference)

    if name == player_name then
        return text
    end

    table.clear(_popup_params)

    for key, value in pairs(params) do
        _popup_params[key] = value
    end

    _popup_params.player_name = name
    mod.debug.timing("ui_rendered", binding.character_id, reference)

    return Localize(data.description_text, true, _popup_params)
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

mod.register_party_popup = function(description_text, popup)
    _party_popups[description_text] = popup
end

mod.track_party_popup = function(func, manager, attempts_key, key, account_id, ...)
    local attempt = nil

    if key and account_id then
        local attempts = manager[attempts_key]

        if not attempts then
            attempts = {}
            manager[attempts_key] = attempts
        end

        local presence = _presence_entry(account_id)

        attempt = attempts[key]

        if attempt then
            attempt.outstanding = attempt.outstanding + 1

            if attempt.account_id ~= account_id or attempt.presence ~= presence then
                attempt.ambiguous = true
            end
        else
            attempt = {
                account_id = account_id,
                presence = presence,
                outstanding = 1,
                ambiguous = false,
            }
            attempts[key] = attempt
        end
    end

    func(manager, ...)

    if attempt and not attempt.presence then
        attempt.presence = _presence_entry(account_id)
    end
end

mod.register_party_popup("loc_social_party_invite_received_description", {
    ref = ref,
    title_text = "loc_social_party_invite_received_header",
    popups = "_invite_popups",
    attempts = "tl_invite_attempts",
})

mod:hook(CLASS.PartyImmateriumManager, "_handle_immaterium_invite", function(func, self, party_id, invite_token, inviter_account_id)
    if inviter_account_id == GROUP_FINDER_ACCOUNT_ID then
        return func(self, party_id, invite_token, inviter_account_id)
    end

    mod.track_party_popup(func, self, "tl_invite_attempts", party_id, inviter_account_id, party_id, invite_token, inviter_account_id)
end)

mod:hook_safe(CLASS.PartyImmateriumManager, "_decline_party_invite", function(self, party_id, invite_token, answer_code)
    if answer_code ~= nil then
        _finish_popup_attempt(self.tl_invite_attempts, party_id)
    end
end)

mod:hook_safe(CLASS.PartyImmateriumInviteNotificationHandler, "add_invite", function(self, party_id)
    local party_manager = Managers.party_immaterium

    if party_manager and party_manager._invite_notification_handler == self then
        _finish_popup_attempt(party_manager.tl_invite_attempts, party_id)
    end
end)

mod:hook_safe(CLASS.PartyImmateriumManager, "destroy", function(self)
    for _, popup in pairs(_party_popups) do
        self[popup.attempts] = nil
    end

    table.clear(_popup_bindings)
end)

mod:hook_safe(CLASS.UIManager, "event_show_ui_popup", function(self, data)
    local popup = _party_popups[data.description_text]

    if not popup or data.title_text ~= popup.title_text then
        return
    end

    local party_manager = Managers.party_immaterium
    local popups = party_manager and party_manager[popup.popups]

    if not popups then
        return
    end

    local active_popups = self._active_popups
    local popup_id = nil

    for i = 1, #active_popups do
        local active_popup = active_popups[i]

        if active_popup.data == data then
            popup_id = active_popup.id

            break
        end
    end

    if not popup_id then
        return
    end

    local key = nil

    for id, mapped_popup_id in pairs(popups) do
        if mapped_popup_id == popup_id then
            if key then
                return
            end

            key = id
        end
    end

    if not key then
        return
    end

    local attempt = _finish_popup_attempt(party_manager[popup.attempts], key)
    local presence = attempt and not attempt.ambiguous and attempt.presence

    if not presence then
        return
    end

    local character_id = presence:character_id()

    if not character_id or character_id == "" then
        return
    end

    _prune_popup_bindings()

    _popup_bindings[data] = {
        popups = popup.popups,
        key = key,
        popup_id = popup_id,
        ref = popup.ref,
        character_id = character_id,
        true_levels = nil,
        havoc_rank = nil,
        enabled = nil,
    }
end)

mod:hook(CLASS.ConstantElementPopupHandler, "_setup_presentation", function(func, self, data, ui_renderer)
    local binding = _popup_bindings[data]

    if binding and not _is_popup_mapped(binding) then
        _popup_bindings[data] = nil
        binding = nil
    end

    if not binding then
        return func(self, data, ui_renderer)
    end

    _presenting_data = data
    _popup_handler = self
    func(self, data, ui_renderer)
    _presenting_data = nil
    mod.synced(binding.ref)
end)

mod:hook(CLASS.ConstantElementPopupHandler, "_set_description_text", function(func, self, text)
    local data = _presenting_data

    if not data then
        local popup = self._active_popup

        data = popup and popup.data
    end

    local binding = data and _popup_bindings[data]

    if binding and type(text) == "string" then
        if _is_popup_mapped(binding) then
            text = _decorate(data, binding, text)
        else
            _popup_bindings[data] = nil
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
    local binding = _popup_bindings[data]

    if not binding or self._on_enter_anim_id then
        return
    end

    local reference = binding.ref
    local true_levels = mod.get_true_levels(binding.character_id)
    local enabled = mod.is_enabled_feature(reference)

    if true_levels == binding.true_levels and enabled == binding.enabled
        and (not true_levels or true_levels.havoc_rank == binding.havoc_rank)
        and not mod.should_replace(reference) then
        return
    end

    if popup.closing or not _is_popup_mapped(binding) then
        _popup_bindings[data] = nil

        return
    end

    _set_rendered_state(binding, true_levels, enabled)
    _refresh_description(self, data, ui_renderer)
    mod.synced(reference)
end)

mod.restore_party_invite = function()
    local handler = _popup_handler
    local popup = handler and handler._active_popup
    local data = popup and popup.data
    local binding = data and _popup_bindings[data]

    if binding and not popup.closing and not handler._on_enter_anim_id and _is_popup_mapped(binding) then
        _refresh_description(handler, data, handler:ui_renderer())
    end
end
