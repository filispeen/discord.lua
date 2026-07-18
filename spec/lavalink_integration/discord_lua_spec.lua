-- spec/lavalink_integration/discord_lua_spec.lua
-- Tests for the discord.lua <-> filispeen/lavalink.lua integration shim.
--
-- The real libs.LavalinkManager belongs to filispeen/lavalink.lua, a
-- separate project not vendored here, so it is mocked: these tests only
-- verify the shim's own responsibilities (clientId resolution, wiring
-- sendPayload to Client:voice_state_update, and forwarding
-- voice_state_update/voice_server_update into handleVoiceUpdate).

package.path = "lib/?.lua;lib/?/?.lua;examples/lavalink_integration/?.lua;" .. package.path

local function make_mock_lavalink_manager()
    local created_with = nil
    local handle_voice_update_calls = {}

    local MockManager = {}
    MockManager.__index = MockManager

    local mock_module = {
        new = function(opts)
            created_with = opts
            local self = setmetatable({}, MockManager)
            return self
        end,
    }

    function MockManager:handleVoiceUpdate(packet)
        table.insert(handle_voice_update_calls, packet)
    end

    return mock_module, function() return created_with end, handle_voice_update_calls
end

local function make_bot(user)
    local listeners = {}
    local sent_voice_updates = {}

    local bot = {
        user = user,
        client = {
            voice_state_update = function(_self, guild_id, channel_id, self_mute, self_deaf)
                table.insert(sent_voice_updates, {
                    guild_id = guild_id,
                    channel_id = channel_id,
                    self_mute = self_mute,
                    self_deaf = self_deaf,
                })
            end,
        },
        on = function(_self, event, callback)
            listeners[event] = listeners[event] or {}
            table.insert(listeners[event], callback)
        end,
        emit = function(_self, event, ...)
            for _, cb in ipairs(listeners[event] or {}) do
                cb(...)
            end
        end,
    }

    return bot, sent_voice_updates
end

describe("lavalink.lua discord.lua integration shim", function()
    it("resolves clientId from bot.user.id when not given explicitly", function()
        local mock_module, get_created_with = make_mock_lavalink_manager()
        package.loaded["libs.LavalinkManager"] = mock_module
        package.loaded["discord_lua"] = nil
        local create_integration = require("discord_lua")

        local bot = make_bot({ id = "12345" })
        create_integration(bot, { nodes = {} })

        assert.equals("12345", get_created_with().clientId)
    end)

    it("errors when bot.user is nil and no clientId was given", function()
        package.loaded["discord_lua"] = nil
        local create_integration = require("discord_lua")

        local bot = make_bot(nil)

        assert.has_error(function()
            create_integration(bot, { nodes = {} })
        end)
    end)

    it("uses an explicitly provided clientId over bot.user.id", function()
        local mock_module, get_created_with = make_mock_lavalink_manager()
        package.loaded["libs.LavalinkManager"] = mock_module
        package.loaded["discord_lua"] = nil
        local create_integration = require("discord_lua")

        local bot = make_bot({ id = "12345" })
        create_integration(bot, { nodes = {}, clientId = "override" })

        assert.equals("override", get_created_with().clientId)
    end)

    it("sendPayload forwards the unwrapped voice state to Client:voice_state_update", function()
        local mock_module, get_created_with = make_mock_lavalink_manager()
        package.loaded["libs.LavalinkManager"] = mock_module
        package.loaded["discord_lua"] = nil
        local create_integration = require("discord_lua")

        local bot, sent = make_bot({ id = "12345" })
        create_integration(bot, { nodes = {} })

        local send_payload = get_created_with().sendPayload
        send_payload("111", {
            op = 4,
            d = { guild_id = "111", channel_id = "222", self_mute = false, self_deaf = true },
        })

        assert.equals(1, #sent)
        assert.equals("111", sent[1].guild_id)
        assert.equals("222", sent[1].channel_id)
        assert.is_true(sent[1].self_deaf)
    end)

    it("does not override an explicitly provided sendPayload", function()
        local mock_module = make_mock_lavalink_manager()
        package.loaded["libs.LavalinkManager"] = mock_module
        package.loaded["discord_lua"] = nil
        local create_integration = require("discord_lua")

        local bot = make_bot({ id = "12345" })
        local custom_called = false

        create_integration(bot, {
            nodes = {},
            sendPayload = function() custom_called = true end,
        })

        assert.is_false(custom_called)
    end)

    it("forwards bot voice_state_update events into handleVoiceUpdate", function()
        local mock_module, _get_created_with, handle_voice_update_calls = make_mock_lavalink_manager()
        package.loaded["libs.LavalinkManager"] = mock_module
        package.loaded["discord_lua"] = nil
        local create_integration = require("discord_lua")

        local bot = make_bot({ id = "12345" })
        create_integration(bot, { nodes = {} })

        bot:emit("voice_state_update", { guild_id = "111", channel_id = "222" })

        assert.equals(1, #handle_voice_update_calls)
        assert.equals("VOICE_STATE_UPDATE", handle_voice_update_calls[1].t)
        assert.equals("111", handle_voice_update_calls[1].d.guild_id)
    end)

    it("forwards bot voice_server_update events into handleVoiceUpdate", function()
        local mock_module, _get_created_with, handle_voice_update_calls = make_mock_lavalink_manager()
        package.loaded["libs.LavalinkManager"] = mock_module
        package.loaded["discord_lua"] = nil
        local create_integration = require("discord_lua")

        local bot = make_bot({ id = "12345" })
        create_integration(bot, { nodes = {} })

        bot:emit("voice_server_update", { guild_id = "111", endpoint = "example.discord.media" })

        assert.equals(1, #handle_voice_update_calls)
        assert.equals("VOICE_SERVER_UPDATE", handle_voice_update_calls[1].t)
        assert.equals("example.discord.media", handle_voice_update_calls[1].d.endpoint)
    end)
end)
