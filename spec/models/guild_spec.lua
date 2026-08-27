-- spec/models/guild_spec.lua
-- Tests for the Guild model, focused on soundboard integration

require("spec_helper")

local Guild = require("./models/guild")

local function make_http(get_response, post_response)
    local calls = {}
    return {
        get = function(_self, endpoint)
            table.insert(calls, { method = "get", endpoint = endpoint })
            return get_response
        end,
        post = function(_self, endpoint, payload)
            table.insert(calls, { method = "post", endpoint = endpoint, payload = payload })
            return post_response
        end,
    }, calls
end

describe("Guild", function()
    describe("Guild.new", function()
        it("reads core fields from the payload", function()
            local guild = Guild.new({ id = "1", name = "Test Guild" })
            assert.equals("1", guild.id)
            assert.equals("Test Guild", guild.name)
        end)

        it("stores an optional http client", function()
            local http = {}
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.equals(http, guild.http)
        end)
    end)

    describe("Guild:fetch_sounds", function()
        it("errors when no http client is attached", function()
            local guild = Guild.new({ id = "1", name = "Test" })
            assert.has_error(function()
                guild:fetch_sounds()
            end)
        end)

        it("GETs the guild soundboard-sounds endpoint and returns Sound instances", function()
            local http, calls = make_http({ items = {
                { sound_id = "1", name = "boop" },
                { sound_id = "2", name = "beep" },
            } })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local sounds = guild:fetch_sounds()

            assert.equals(1, #calls)
            assert.equals("/guilds/guild1/soundboard-sounds", calls[1].endpoint)
            assert.equals(2, #sounds)
            assert.equals("boop", sounds[1].name)
            assert.equals("guild1", sounds[1].guild_id)
        end)

        it("handles a bare array response with no items wrapper", function()
            local http = make_http({ { sound_id = "1", name = "boop" } })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local sounds = guild:fetch_sounds()

            assert.equals(1, #sounds)
        end)
    end)

    describe("Guild:create_sound", function()
        it("errors when no http client is attached", function()
            local guild = Guild.new({ id = "1", name = "Test" })
            assert.has_error(function()
                guild:create_sound({ name = "boop", sound = "data:audio/mpeg;base64,AA" })
            end)
        end)

        it("requires opts.name", function()
            local http = make_http()
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.has_error(function()
                guild:create_sound({ sound = "data:audio/mpeg;base64,AA" })
            end)
        end)

        it("requires opts.sound", function()
            local http = make_http()
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.has_error(function()
                guild:create_sound({ name = "boop" })
            end)
        end)

        it("POSTs the guild soundboard-sounds endpoint and returns a Sound", function()
            local http, calls = make_http(nil, { sound_id = "1", name = "boop", volume = 1.0 })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local sound = guild:create_sound({ name = "boop", sound = "data:audio/mpeg;base64,AA" })

            assert.equals(1, #calls)
            assert.equals("/guilds/guild1/soundboard-sounds", calls[1].endpoint)
            assert.equals("boop", calls[1].payload.name)
            assert.equals("boop", sound.name)
            assert.equals("guild1", sound.guild_id)
        end)

        it("defaults volume to 1.0 when not given", function()
            local http, calls = make_http(nil, { sound_id = "1", name = "boop" })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            guild:create_sound({ name = "boop", sound = "data:audio/mpeg;base64,AA" })

            assert.equals(1.0, calls[1].payload.volume)
        end)
    end)

    describe("Guild:fetch_scheduled_events", function()
        it("errors when no http client is attached", function()
            local guild = Guild.new({ id = "1", name = "Test" })
            assert.has_error(function()
                guild:fetch_scheduled_events()
            end)
        end)

        it("GETs the guild scheduled-events endpoint and returns ScheduledEvent instances", function()
            local http, calls = make_http({
                { id = "1", guild_id = "guild1", name = "Community night" },
                { id = "2", guild_id = "guild1", name = "Raid" },
            })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local events = guild:fetch_scheduled_events()

            assert.equals(1, #calls)
            assert.equals("/guilds/guild1/scheduled-events?with_user_count=1", calls[1].endpoint)
            assert.equals(2, #events)
            assert.equals("Community night", events[1].name)
            assert.equals(guild, events[1].guild)
        end)

        it("omits with_user_count when explicitly disabled", function()
            local http, calls = make_http({})
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            guild:fetch_scheduled_events(false)

            assert.equals("/guilds/guild1/scheduled-events?with_user_count=0", calls[1].endpoint)
        end)
    end)

    describe("Guild:fetch_scheduled_event", function()
        it("GETs a single scheduled event by id", function()
            local http, calls = make_http({ id = "1", guild_id = "guild1", name = "Community night" })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local event = guild:fetch_scheduled_event("1")

            assert.equals("/guilds/guild1/scheduled-events/1?with_user_count=1", calls[1].endpoint)
            assert.equals("Community night", event.name)
        end)
    end)

    describe("Guild:create_scheduled_event", function()
        it("errors when no http client is attached", function()
            local guild = Guild.new({ id = "1", name = "Test" })
            assert.has_error(function()
                guild:create_scheduled_event({ name = "x", start_time = "t", channel_id = "c1" })
            end)
        end)

        it("requires opts.name", function()
            local http = make_http()
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.has_error(function()
                guild:create_scheduled_event({ start_time = "t", channel_id = "c1" })
            end)
        end)

        it("requires opts.start_time", function()
            local http = make_http()
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.has_error(function()
                guild:create_scheduled_event({ name = "x", channel_id = "c1" })
            end)
        end)

        it("requires opts.channel_id or opts.location", function()
            local http = make_http()
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.has_error(function()
                guild:create_scheduled_event({ name = "x", start_time = "t" })
            end)
        end)

        it("POSTs a voice-channel event with entity_type 2", function()
            local http, calls = make_http(nil, { id = "1", guild_id = "guild1", name = "x" })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            guild:create_scheduled_event({ name = "x", start_time = "t", channel_id = "c1" })

            assert.equals("/guilds/guild1/scheduled-events", calls[1].endpoint)
            assert.equals("c1", calls[1].payload.channel_id)
            assert.equals(2, calls[1].payload.entity_type)
        end)

        it("POSTs an external event with entity_metadata.location", function()
            local http, calls = make_http(nil, { id = "1", guild_id = "guild1", name = "x" })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local event = guild:create_scheduled_event({ name = "x", start_time = "t", location = "The Park" })

            assert.equals(3, calls[1].payload.entity_type)
            assert.equals("The Park", calls[1].payload.entity_metadata.location)
            assert.equals("x", event.name)
        end)
    end)

    describe("Guild:fetch_automod_rules", function()
        it("errors when no http client is attached", function()
            local guild = Guild.new({ id = "1", name = "Test" })
            assert.has_error(function()
                guild:fetch_automod_rules()
            end)
        end)

        it("GETs the guild auto-moderation rules endpoint and returns AutoModRule instances", function()
            local http, calls = make_http({
                { id = "1", guild_id = "guild1", name = "Spam filter", trigger_type = 1, actions = {} },
                { id = "2", guild_id = "guild1", name = "Link filter", trigger_type = 2, actions = {} },
            })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local rules = guild:fetch_automod_rules()

            assert.equals(1, #calls)
            assert.equals("/guilds/guild1/auto-moderation/rules", calls[1].endpoint)
            assert.equals(2, #rules)
            assert.equals("Spam filter", rules[1].name)
            assert.equals(guild, rules[1].guild)
        end)
    end)

    describe("Guild:fetch_automod_rule", function()
        it("GETs a single automod rule by id", function()
            local http, calls = make_http({
                id = "1",
                guild_id = "guild1",
                name = "Spam filter",
                trigger_type = 1,
                actions = {},
            })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local rule = guild:fetch_automod_rule("1")

            assert.equals("/guilds/guild1/auto-moderation/rules/1", calls[1].endpoint)
            assert.equals("Spam filter", rule.name)
        end)
    end)

    describe("Guild:create_automod_rule", function()
        it("errors when no http client is attached", function()
            local guild = Guild.new({ id = "1", name = "Test" })
            assert.has_error(function()
                guild:create_automod_rule({ name = "x", trigger_type = 1, actions = {} })
            end)
        end)

        it("requires opts.name", function()
            local http = make_http()
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.has_error(function()
                guild:create_automod_rule({ trigger_type = 1, actions = {} })
            end)
        end)

        it("requires opts.trigger_type", function()
            local http = make_http()
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.has_error(function()
                guild:create_automod_rule({ name = "x", actions = {} })
            end)
        end)

        it("requires opts.actions", function()
            local http = make_http()
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.has_error(function()
                guild:create_automod_rule({ name = "x", trigger_type = 1 })
            end)
        end)

        it("POSTs the guild auto-moderation rules endpoint and returns an AutoModRule", function()
            local AutoMod = require("./models/automod")
            local http, calls = make_http(
                nil,
                { id = "1", guild_id = "guild1", name = "x", trigger_type = 1, actions = {} }
            )
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)
            local action = AutoMod.AutoModAction.new(1, AutoMod.AutoModActionMetadata.new({ custom_message = "no" }))

            local rule = guild:create_automod_rule({
                name = "x",
                trigger_type = 1,
                actions = { action },
                enabled = true,
                exempt_role_ids = { "r1" },
            })

            assert.equals("/guilds/guild1/auto-moderation/rules", calls[1].endpoint)
            assert.equals("x", calls[1].payload.name)
            assert.equals(1, calls[1].payload.event_type)
            assert.equals(1, calls[1].payload.actions[1].type)
            assert.equals("no", calls[1].payload.actions[1].metadata.custom_message)
            assert.is_true(calls[1].payload.enabled)
            assert.same({ "r1" }, calls[1].payload.exempt_roles)
            assert.equals("x", rule.name)
        end)

        it("defaults event_type to 1 and enabled to false", function()
            local http, calls = make_http(
                nil,
                { id = "1", guild_id = "guild1", name = "x", trigger_type = 1, actions = {} }
            )
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            guild:create_automod_rule({ name = "x", trigger_type = 1, actions = {} })

            assert.equals(1, calls[1].payload.event_type)
            assert.is_false(calls[1].payload.enabled)
        end)

        it("serializes trigger_metadata when given", function()
            local AutoMod = require("./models/automod")
            local http, calls = make_http(
                nil,
                { id = "1", guild_id = "guild1", name = "x", trigger_type = 1, actions = {} }
            )
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)
            local trigger_metadata = AutoMod.AutoModTriggerMetadata.new({ keyword_filter = { "bad" } })

            guild:create_automod_rule({
                name = "x",
                trigger_type = 1,
                actions = {},
                trigger_metadata = trigger_metadata,
            })

            assert.same({ "bad" }, calls[1].payload.trigger_metadata.keyword_filter)
        end)
    end)

    describe("Guild:fetch_audit_logs", function()
        it("errors when no http client is attached", function()
            local guild = Guild.new({ id = "1", name = "Test" })
            assert.has_error(function()
                guild:fetch_audit_logs()
            end)
        end)

        it("GETs the guild audit-logs endpoint and returns AuditLogEntry instances", function()
            local http, calls = make_http({
                audit_log_entries = {
                    { id = "1", guild_id = "guild1", action_type = 20, user_id = "mod1" },
                    { id = "2", guild_id = "guild1", action_type = 22, user_id = "mod1" },
                },
            })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local entries = guild:fetch_audit_logs()

            assert.equals(1, #calls)
            assert.equals("/guilds/guild1/audit-logs?limit=100", calls[1].endpoint)
            assert.equals(2, #entries)
            assert.equals("1", entries[1].id)
            assert.equals(20, entries[1].action_type)
            assert.equals(guild, entries[1].guild)
        end)

        it("includes optional filters as query parameters", function()
            local http, calls = make_http({ audit_log_entries = {} })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            guild:fetch_audit_logs({ limit = 10, before = "b1", after = "a1", user_id = "u1", action_type = 20 })

            local endpoint = calls[1].endpoint
            assert.is_not_nil(endpoint:find("limit=10", 1, true))
            assert.is_not_nil(endpoint:find("before=b1", 1, true))
            assert.is_not_nil(endpoint:find("after=a1", 1, true))
            assert.is_not_nil(endpoint:find("user_id=u1", 1, true))
            assert.is_not_nil(endpoint:find("action_type=20", 1, true))
        end)

        it("returns an empty table when the response has no entries", function()
            local http = make_http({})
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local entries = guild:fetch_audit_logs()
            assert.same({}, entries)
        end)
    end)

    describe("Guild:fetch_templates", function()
        it("errors when no http client is attached", function()
            local guild = Guild.new({ id = "1", name = "Test" })
            assert.has_error(function()
                guild:fetch_templates()
            end)
        end)

        it("GETs the guild templates endpoint and returns Template instances", function()
            local http, calls = make_http({
                { code = "abc", usage_count = 1, name = "T1", source_guild_id = "guild1" },
                { code = "def", usage_count = 2, name = "T2", source_guild_id = "guild1" },
            })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local templates = guild:fetch_templates()

            assert.equals(1, #calls)
            assert.equals("/guilds/guild1/templates", calls[1].endpoint)
            assert.equals(2, #templates)
            assert.equals("abc", templates[1].code)
            assert.equals("T2", templates[2].name)
        end)
    end)

    describe("Guild:create_template", function()
        it("errors when no http client is attached", function()
            local guild = Guild.new({ id = "1", name = "Test" })
            assert.has_error(function()
                guild:create_template({ name = "New" })
            end)
        end)

        it("errors when opts.name is missing", function()
            local http = make_http({})
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)
            assert.has_error(function()
                guild:create_template({})
            end)
        end)

        it("POSTs the guild templates endpoint and returns a Template instance", function()
            local http, calls = make_http(nil, {
                code = "new1",
                usage_count = 0,
                name = "New Template",
                source_guild_id = "guild1",
            })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local template = guild:create_template({ name = "New Template", description = "desc" })

            assert.equals(1, #calls)
            assert.equals("/guilds/guild1/templates", calls[1].endpoint)
            assert.equals("New Template", calls[1].payload.name)
            assert.equals("desc", calls[1].payload.description)
            assert.equals("new1", template.code)
        end)
    end)
end)
