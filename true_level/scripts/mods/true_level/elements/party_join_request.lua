local mod = get_mod("true_level")
local ref = "party_join_request"

mod.register_party_popup("loc_party_request_to_join_description", {
    ref = ref,
    title_text = "loc_party_request_to_join_header",
    popups = "_request_to_join_popups",
    attempts = "tl_join_request_attempts",
})

mod:hook(CLASS.PartyImmateriumManager, "_request_to_join_popup", function(func, self, joiner_account_id)
    mod.track_party_popup(func, self, "tl_join_request_attempts", joiner_account_id, joiner_account_id, joiner_account_id)
end)
