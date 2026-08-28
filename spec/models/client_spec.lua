-- spec/models/client_spec.lua
-- Tests for models.client, focused on the channel cache wiring
-- (Client:get_channel, GUILD_CREATE/CHANNEL_CREATE/CHANNEL_UPDATE/
-- CHANNEL_DELETE dispatch handling).

require("spec_helper")

local Client = require("./models/client")

describe("Client:get_channel", function()
    it("returns nil when the channel is not cached and there is no rest/http", function()
        local client = Client.new("token")
        assert.is_nil(client:get_channel("channel1"))
    end)

    it("returns a Channel built from a cached raw payload", function()
        local client = Client.new("token")
        client.channels:put({ id = "channel1", name = "general", type = 0, guild_id = "guild1" })

        local channel = client:get_channel("channel1")
        assert.is_not_nil(channel)
        assert.equals("general", channel.name)
    end)

    it("attaches a minimal guild stand-in with the right id", function()
        local client = Client.new("token")
        client.channels:put({ id = "channel1", name = "voice", type = 2, guild_id = "guild1" })

        local channel = client:get_channel("channel1")
        assert.is_not_nil(channel.guild)
        assert.equals("guild1", channel.guild.id)
    end)

    it("leaves guild nil when the cached payload has no guild_id", function()
        local client = Client.new("token")
        client.channels:put({ id = "dm1", name = nil, type = 1 })

        local channel = client:get_channel("dm1")
        assert.is_nil(channel.guild)
    end)

    it("falls back to rest:get_channel when not cached", function()
        local client = Client.new("token")
        client.rest = {
            get_channel = function(_self, id)
                return { id = id, name = "from_rest", type = 0, guild_id = "guild9" }
            end,
        }

        local channel = client:get_channel("channel2")
        assert.is_not_nil(channel)
        assert.equals("from_rest", channel.name)
        assert.equals("guild9", channel.guild.id)
    end)
end)

describe("Client channel cache dispatch wiring", function()
    local function make_client_with_fake_gateway()
        local client = Client.new("token")
        local dispatch_handlers = {}

        client.gateway = {
            on_shard_ready = function() end,
            on_shard_error = function() end,
            on_shard_disconnect = function() end,
            on_ready = function() end,
            on_dispatch = function(_self, name, callback)
                dispatch_handlers[name] = callback
            end,
            start = function() end,
        }

        -- Re-run the same registration block start_gateway uses, without
        -- actually requiring gateway.manager or opening a real connection.
        local gateway_manager_stub = { new = function() return client.gateway end }
        package.loaded["../gateway/manager"] = gateway_manager_stub
        client:start_gateway()
        package.loaded["../gateway/manager"] = nil

        return client, dispatch_handlers
    end

    it("populates the channel cache from GUILD_CREATE", function()
        local client, handlers = make_client_with_fake_gateway()

        handlers["GUILD_CREATE"]({
            id = "guild1",
            channels = {
                { id = "channel1", name = "general", type = 0 },
                { id = "channel2", name = "voice", type = 2 },
            },
        })

        assert.equals("guild1", client.channels:get("channel1").guild_id)
        assert.equals("guild1", client.channels:get("channel2").guild_id)
    end)

    it("adds a channel from CHANNEL_CREATE", function()
        local client, handlers = make_client_with_fake_gateway()

        handlers["CHANNEL_CREATE"]({ id = "channel3", name = "new-channel", guild_id = "guild1" })

        assert.equals("new-channel", client.channels:get("channel3").name)
    end)

    it("overwrites a channel from CHANNEL_UPDATE", function()
        local client, handlers = make_client_with_fake_gateway()

        handlers["CHANNEL_CREATE"]({ id = "channel3", name = "old-name", guild_id = "guild1" })
        handlers["CHANNEL_UPDATE"]({ id = "channel3", name = "new-name", guild_id = "guild1" })

        assert.equals("new-name", client.channels:get("channel3").name)
    end)

    it("removes a channel from CHANNEL_DELETE", function()
        local client, handlers = make_client_with_fake_gateway()

        handlers["CHANNEL_CREATE"]({ id = "channel3", name = "temp", guild_id = "guild1" })
        handlers["CHANNEL_DELETE"]({ id = "channel3", guild_id = "guild1" })

        assert.is_nil(client.channels:get("channel3"))
    end)
end)

describe("Client:fetch_template", function()
    local function fake_http()
        local calls = {}
        return {
            calls = calls,
            get = function(_self, endpoint)
                table.insert(calls, { method = "GET", endpoint = endpoint })
                return {
                    code = "abc123",
                    usage_count = 1,
                    name = "Fetched",
                    source_guild_id = "g1",
                }
            end,
        }, calls
    end

    it("errors when no http client is attached", function()
        local client = Client.new("token")
        assert.has_error(function()
            client:fetch_template("abc123")
        end)
    end)

    it("errors when no code is given", function()
        local client = Client.new("token")
        client.http = (fake_http())
        assert.has_error(function()
            client:fetch_template(nil)
        end)
    end)

    it("GETs the template endpoint with a bare code", function()
        local client = Client.new("token")
        local http, calls = fake_http()
        client.http = http

        local template = client:fetch_template("abc123")

        assert.equals(1, #calls)
        assert.equals("/guilds/templates/abc123", calls[1].endpoint)
        assert.equals("Fetched", template.name)
    end)

    it("strips a discord.new URL down to the bare code", function()
        local client = Client.new("token")
        local http, calls = fake_http()
        client.http = http

        client:fetch_template("https://discord.new/abc123")

        assert.equals("/guilds/templates/abc123", calls[1].endpoint)
    end)

    it("strips a bare discord.new/ prefix without a scheme", function()
        local client = Client.new("token")
        local http, calls = fake_http()
        client.http = http

        client:fetch_template("discord.new/abc123")

        assert.equals("/guilds/templates/abc123", calls[1].endpoint)
    end)
end)

describe("Client:fetch_widget", function()
    local function fake_http()
        local calls = {}
        return {
            calls = calls,
            get = function(_self, endpoint)
                table.insert(calls, { method = "GET", endpoint = endpoint })
                return {
                    id = "guild1",
                    name = "Fetched Guild",
                    instant_invite = "https://discord.gg/abc123",
                    channels = {},
                    members = {},
                }
            end,
        }, calls
    end

    it("errors when no http client is attached", function()
        local client = Client.new("token")
        assert.has_error(function()
            client:fetch_widget("guild1")
        end)
    end)

    it("errors when no guild_id is given", function()
        local client = Client.new("token")
        client.http = (fake_http())
        assert.has_error(function()
            client:fetch_widget(nil)
        end)
    end)

    it("GETs the guild widget.json endpoint and returns a Widget", function()
        local client = Client.new("token")
        local http, calls = fake_http()
        client.http = http

        local widget = client:fetch_widget("guild1")

        assert.equals(1, #calls)
        assert.equals("/guilds/guild1/widget.json", calls[1].endpoint)
        assert.equals("Fetched Guild", widget.name)
        assert.equals("https://discord.gg/abc123", widget:invite_url())
    end)
end)

describe("Client remaining gateway dispatch wiring", function()
    local function make_client_with_fake_gateway()
        local client = Client.new("token")
        local handlers = {}
        client.gateway = {
            on_shard_ready = function() end,
            on_shard_error = function() end,
            on_shard_disconnect = function() end,
            on_ready = function() end,
            on_dispatch = function(_self, name, callback)
                handlers[name] = callback
            end,
            start = function() end,
        }
        package.loaded["../gateway/manager"] = { new = function() return client.gateway end }
        client:start_gateway()
        package.loaded["../gateway/manager"] = nil
        return client, handlers
    end

    it("registers every remaining Discord gateway event", function()
        local _, handlers = make_client_with_fake_gateway()
        local names = {
            "CHANNEL_PINS_UPDATE", "GUILD_UPDATE", "GUILD_DELETE",
            "GUILD_EMOJIS_UPDATE", "GUILD_STICKERS_UPDATE",
            "AUTO_MODERATION_RULE_CREATE", "AUTO_MODERATION_RULE_UPDATE",
            "AUTO_MODERATION_RULE_DELETE", "AUTO_MODERATION_ACTION_EXECUTION",
            "MESSAGE_POLL_VOTE_ADD", "MESSAGE_POLL_VOTE_REMOVE",
            "STAGE_INSTANCE_CREATE", "STAGE_INSTANCE_UPDATE", "STAGE_INSTANCE_DELETE",
            "GUILD_SOUNDBOARD_SOUND_CREATE", "GUILD_SOUNDBOARD_SOUND_UPDATE",
            "GUILD_SOUNDBOARD_SOUND_DELETE", "GUILD_SOUNDBOARD_SOUNDS_UPDATE",
            "GUILD_AUDIT_LOG_ENTRY_CREATE", "ENTITLEMENT_CREATE", "ENTITLEMENT_UPDATE",
            "ENTITLEMENT_DELETE", "SUBSCRIPTION_CREATE", "SUBSCRIPTION_UPDATE",
            "SUBSCRIPTION_DELETE", "USER_UPDATE", "VOICE_CHANNEL_EFFECT_SEND",
            "VOICE_CHANNEL_STATUS_UPDATE", "APPLICATION_COMMAND_PERMISSIONS_UPDATE",
        }
        for _, name in ipairs(names) do
            assert.is_function(handlers[name])
        end
    end)

    it("caches and emits typed AutoMod, stage, soundboard, audit log and user models", function()
        local client, handlers = make_client_with_fake_gateway()
        local received = {}
        client:on("automod_rule_create", function(rule) received.rule = rule end)
        client:on("stage_instance_create", function(instance) received.instance = instance end)
        client:on("guild_soundboard_sound_create", function(sound) received.sound = sound end)
        client:on("audit_log_entry_create", function(entry) received.entry = entry end)
        client:on("user_update", function(old_user, user) received.old_user, received.user = old_user, user end)

        handlers["AUTO_MODERATION_RULE_CREATE"]({
            id = "rule1", guild_id = "guild1", name = "rule", event_type = 1,
            trigger_type = 1, trigger_metadata = {}, actions = {}, enabled = true,
        })
        handlers["STAGE_INSTANCE_CREATE"]({ id = "stage1", guild_id = "guild1", channel_id = "channel1", topic = "topic" })
        handlers["GUILD_SOUNDBOARD_SOUND_CREATE"]({ sound_id = "sound1", guild_id = "guild1", name = "sound" })
        handlers["GUILD_AUDIT_LOG_ENTRY_CREATE"]({ id = "entry1", guild_id = "guild1", action_type = 10, changes = {} })
        client.user = { id = "old" }
        handlers["USER_UPDATE"]({ id = "user1", username = "new", discriminator = "0" })

        assert.equals("rule1", received.rule.id)
        assert.equals("stage1", received.instance.id)
        assert.equals("sound1", received.sound.id)
        assert.equals("entry1", received.entry.id)
        assert.equals("old", received.old_user.id)
        assert.equals("new", received.user.username)
        assert.equals(received.rule, client.automod_rules.guild1.rule1)
        assert.equals(received.instance, client.stage_instances.guild1.stage1)
        assert.equals(received.sound, client.soundboard_sounds.guild1.sound1)
    end)

    it("clears guild-scoped caches on GUILD_DELETE", function()
        local client, handlers = make_client_with_fake_gateway()
        client.channels:put({ id = "channel1", guild_id = "guild1" })
        client.members:put("guild1", { user = { id = "user1" } })
        client.roles:put("guild1", { id = "role1" })
        client.voice_states:update({ guild_id = "guild1", user_id = "user1", channel_id = "channel1" })
        client.automod_rules.guild1 = { rule1 = {} }
        client.stage_instances.guild1 = { stage1 = {} }
        client.soundboard_sounds.guild1 = { sound1 = {} }

        handlers["GUILD_DELETE"]({ id = "guild1" })

        assert.is_nil(client.channels:get("channel1"))
        assert.is_nil(client.members:get("guild1", "user1"))
        assert.is_nil(client.roles:get("guild1", "role1"))
        assert.is_nil(client.voice_states:get("guild1", "user1"))
        assert.is_nil(client.automod_rules.guild1)
        assert.is_nil(client.stage_instances.guild1)
        assert.is_nil(client.soundboard_sounds.guild1)
    end)
end)
