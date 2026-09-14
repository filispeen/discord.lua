require("spec_helper")

local enums = require("./core/enums")
local Channel = require("./models/channel")
local Thread = require("./models/thread")
local Member = require("./models/member")
local Message = require("./models/message")
local ApplicationCommand = require("./interactions/application_command")
local CommandTree = require("./interactions/command_tree")

describe("Discord API v10 support", function()
    it("uses Discord's current channel and thread type ids", function()
        local names = {
            [0] = "text", [1] = "private", [2] = "voice", [4] = "category",
            [5] = "announcement", [10] = "announcement_thread",
            [11] = "public_thread", [12] = "private_thread",
            [13] = "stage_voice", [14] = "directory", [15] = "forum", [16] = "media",
        }
        for id, name in pairs(names) do
            assert.equals(name, Channel.new({ id = "c", type = id }):get_type_name())
        end
        for _, id in ipairs({ 10, 11, 12 }) do assert.is_true(Thread.new({ id = "t", type = id }):is_thread()) end
        assert.is_false(Thread.new({ id = "t", type = 13 }):is_thread())
        assert.equals(15, enums.CHANNEL_TYPE.GUILD_FORUM)
        assert.equals(16, enums.CHANNEL_TYPE.GUILD_MEDIA)
    end)

    it("creates and edits threads with API v10 routes, tags and audit reasons", function()
        local calls = {}
        local http = {
            post = function(_, endpoint, payload, options)
                calls[#calls + 1] = { method = "POST", endpoint = endpoint, payload = payload, options = options }
                return { id = "t", type = payload.type or 11, thread_metadata = {} }
            end,
            patch = function(_, endpoint, payload, options)
                calls[#calls + 1] = { method = "PATCH", endpoint = endpoint, payload = payload, options = options }
                return { id = "t", type = 11, applied_tags = payload.applied_tags, thread_metadata = {} }
            end,
        }
        local channel = Channel.new({ id = "c", type = 0 }, nil, http)
        local thread = channel:create_thread({ name = "private", reason = "test" })
        assert.equals("/channels/c/threads", calls[1].endpoint)
        assert.equals(12, calls[1].payload.type)
        assert.equals("test", calls[1].options.reason)
        thread:edit({ applied_tags = { "tag" }, reason = "tag" })
        assert.same({ "tag" }, calls[2].payload.applied_tags)
        assert.equals("tag", calls[2].options.reason)
    end)

    it("parses, sets, changes and clears member timeouts with audit reason", function()
        local calls = {}
        local http = {
            patch = function(_, endpoint, payload, options)
                calls[#calls + 1] = { endpoint = endpoint, payload = payload, options = options }
                return { user = { id = "u" }, communication_disabled_until = payload.communication_disabled_until }
            end,
        }
        local member = Member.new({
            user = { id = "u" }, communication_disabled_until = "2026-01-01T00:00:00+00:00",
        }, { id = "g", http = http })
        assert.equals("2026-01-01T00:00:00+00:00", member.communication_disabled_until)
        member:timeout("2026-02-01T00:00:00Z", "moderation")
        assert.equals("/guilds/g/members/u", calls[1].endpoint)
        assert.equals("2026-02-01T00:00:00Z", calls[1].payload.communication_disabled_until)
        assert.equals("moderation", calls[1].options.reason)
        member:remove_timeout("forgiven")
        assert.is_nil(calls[2].payload.communication_disabled_until)
        assert.equals("forgiven", calls[2].options.reason)
    end)

    it("serializes, parses and syncs command permissions, contexts and localization", function()
        local command = ApplicationCommand.new("ping", "Ping", {
            {
                type = 3, name = "target", description = "Target",
                name_localizations = { uk = "ціль" },
                description_localizations = { uk = "Ціль" },
            },
        })
        command.name_localizations = { uk = "пінг" }
        command.description_localizations = { uk = "Перевірка" }
        command.default_member_permissions = 32
        command.integration_types = { 0, 1 }
        command.contexts = { 0, 1, 2 }
        local payload = command:to_dict()
        assert.equals("32", payload.default_member_permissions)
        assert.same({ 0, 1 }, payload.integration_types)
        assert.equals("ціль", payload.options[1].name_localizations.uk)
        local parsed = ApplicationCommand.from_dict(payload)
        assert.equals("пінг", parsed.name_localizations.uk)
        assert.same({ 0, 1, 2 }, parsed.contexts)

        local calls = {}
        local remote = { id = "1", name = "ping", description = "Ping", type = 1 }
        local http = {
            get = function() return { remote } end,
            patch = function(_, endpoint, body) calls[#calls + 1] = { endpoint = endpoint, body = body } end,
            post = function() end, delete = function() end,
        }
        local tree = CommandTree.new(http)
        tree:add(command)
        tree:sync("app")
        assert.equals("/applications/app/commands/1", calls[1].endpoint)
        assert.equals("пінг", calls[1].body.name_localizations.uk)

        calls = {}
        remote = command:to_dict()
        remote.id = "1"
        remote.options[2] = { type = 3, name = "stale", description = "Stale" }
        tree:sync("app")
        assert.equals("/applications/app/commands/1", calls[1].endpoint)
    end)

    it("parses, edits and creates forum/media posts including tags and first message", function()
        local calls = {}
        local http = {
            post = function(_, endpoint, payload, options)
                calls[#calls + 1] = { method = "POST", endpoint = endpoint, payload = payload, options = options }
                return { id = "post", type = 11, applied_tags = payload.applied_tags, message = { id = "m", channel_id = "post", content = payload.message.content }, thread_metadata = {} }
            end,
            patch = function(_, endpoint, payload, options)
                calls[#calls + 1] = { method = "PATCH", endpoint = endpoint, payload = payload, options = options }
                return { id = "forum", type = 15, available_tags = payload.available_tags, default_forum_layout = payload.default_forum_layout }
            end,
        }
        local forum = Channel.new({
            id = "forum", type = 15, available_tags = { { id = "tag", name = "Lua" } },
            default_reaction_emoji = { emoji_name = "🔥" }, default_sort_order = 0,
            default_forum_layout = 2, default_thread_rate_limit_per_user = 5,
        }, nil, http)
        assert.is_true(forum:is_forum())
        assert.equals("Lua", forum.available_tags[1].name)
        local post = forum:create_forum_post({ name = "Topic", content = "First", applied_tags = { "tag" }, reason = "post" })
        assert.equals("/channels/forum/threads", calls[1].endpoint)
        assert.equals("First", calls[1].payload.message.content)
        assert.same({ "tag" }, calls[1].payload.applied_tags)
        assert.equals("post", calls[1].options.reason)
        assert.equals("First", post.message.content)
        forum:edit({ available_tags = { { name = "Lua" } }, default_forum_layout = 1, reason = "edit" })
        assert.equals(1, calls[2].payload.default_forum_layout)
        assert.equals("edit", calls[2].options.reason)
    end)

    it("models forwarded snapshots and sends a FORWARD message reference", function()
        local source = Message.new({
            id = "source", channel_id = "origin", guild_id = "guild",
            message_reference = { type = 1, message_id = "origin", channel_id = "source" },
            message_snapshots = {
                { message = {
                    type = 0, content = "snapshot", attachments = { { id = "a" } },
                    embeds = { { title = "embed" } }, components = { { type = 1 } },
                    stickers = { { id = "s" } }, mentions = { { id = "u" } },
                } },
            },
        }, {
            post = function(_, endpoint, payload)
                assert.equals("/channels/target/messages", endpoint)
                assert.equals(1, payload.message_reference.type)
                assert.equals("source", payload.message_reference.message_id)
                assert.equals("origin", payload.message_reference.channel_id)
                return { id = "forwarded", channel_id = "target", message_reference = payload.message_reference }
            end,
        })
        local snapshot = source.message_snapshots[1].message
        assert.equals("snapshot", snapshot.content)
        assert.equals("a", snapshot.attachments[1].id)
        assert.equals("embed", snapshot.embeds[1].title)
        assert.equals("s", snapshot.stickers[1].id)
        source:_update({
            message_snapshots = { { message = { content = "updated", components = { { type = 1 } } } }, },
        })
        assert.equals("updated", source.message_snapshots[1].message.content)
        assert.equals(1, source.message_snapshots[1].message.components[1].type)
        local forwarded = source:forward("target", { content = "note" })
        assert.equals("forwarded", forwarded.id)
        assert.equals(1, forwarded.message_reference.type)
    end)
end)
