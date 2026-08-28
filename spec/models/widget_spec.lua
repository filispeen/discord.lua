-- spec/models/widget_spec.lua
-- Tests for Widget, WidgetChannel, WidgetMember models

require("spec_helper")

local WidgetModule = require("./models/widget")
local Widget = WidgetModule.Widget
local WidgetChannel = WidgetModule.WidgetChannel
local WidgetMember = WidgetModule.WidgetMember

local function fake_http()
    local calls = {}
    return {
        calls = calls,
        get = function(_self, endpoint)
            table.insert(calls, { method = "GET", endpoint = endpoint })
            return {
                code = "abc123",
                guild = { id = "g1", name = "Test Guild" },
                channel = { id = "c1", name = "general" },
            }
        end,
    }
end

local function widget_payload()
    return {
        id = "g1",
        name = "Test Guild",
        instant_invite = "https://discord.gg/abc123",
        channels = {
            { id = "c1", name = "general", position = 0 },
            { id = "c2", name = "voice", position = 1 },
        },
        members = {
            {
                id = "u1",
                username = "Alice",
                discriminator = "0001",
                status = "online",
                channel_id = "c1",
            },
            {
                id = "u2",
                username = "Bob",
                discriminator = "0002",
                status = "idle",
                nick = "Bobby",
                bot = true,
                suppress = true,
                self_mute = true,
                game = { name = "Chess" },
            },
        },
    }
end

describe("WidgetChannel", function()
    it("creates a new widget channel", function()
        local channel = WidgetChannel.new("c1", "general", 0)

        assert.equals("c1", channel.id)
        assert.equals("general", channel.name)
        assert.equals(0, channel.position)
    end)

    it("builds a mention string", function()
        local channel = WidgetChannel.new("c1", "general", 0)
        assert.equals("<#c1>", channel:mention())
    end)
end)

describe("WidgetMember", function()
    it("creates a new widget member from a raw payload", function()
        local member = WidgetMember.new({
            id = "u1",
            username = "Alice",
            discriminator = "0001",
            avatar = "avatarhash",
            status = "online",
        })

        assert.equals("u1", member.id)
        assert.equals("Alice", member.username)
        assert.equals("0001", member.discriminator)
        assert.equals("avatarhash", member.avatar)
        assert.equals("online", member.status)
        assert.is_false(member.bot)
        assert.is_false(member.deafened)
        assert.is_false(member.muted)
        assert.is_false(member.suppress)
        assert.is_nil(member.activity)
    end)

    it("reads deaf/mute from either the plain or self_ prefixed fields", function()
        local plain = WidgetMember.new({ id = "u1", username = "A", deaf = true, mute = true })
        assert.is_true(plain.deafened)
        assert.is_true(plain.muted)

        local self_prefixed = WidgetMember.new({ id = "u2", username = "B", self_deaf = true, self_mute = true })
        assert.is_true(self_prefixed.deafened)
        assert.is_true(self_prefixed.muted)
    end)

    it("carries the raw game payload as activity", function()
        local member = WidgetMember.new({ id = "u1", username = "A", game = { name = "Chess" } })
        assert.equals("Chess", member.activity.name)
    end)

    it("stores the connected channel it was built with", function()
        local channel = WidgetChannel.new("c1", "general", 0)
        local member = WidgetMember.new({ id = "u1", username = "A" }, channel)
        assert.equals(channel, member.connected_channel)
    end)

    it("display_name falls back to username without a nick", function()
        local member = WidgetMember.new({ id = "u1", username = "Alice" })
        assert.equals("Alice", member:display_name())
    end)

    it("display_name prefers the nick when present", function()
        local member = WidgetMember.new({ id = "u1", username = "Alice", nick = "Al" })
        assert.equals("Al", member:display_name())
    end)
end)

describe("Widget", function()
    it("creates a new widget from API data", function()
        local widget = Widget.new(widget_payload())

        assert.equals("g1", widget.id)
        assert.equals("Test Guild", widget.name)
        assert.equals(2, #widget.channels)
        assert.equals("c1", widget.channels[1].id)
        assert.equals(2, #widget.members)
    end)

    it("resolves each member's connected_channel against the widget's own channels", function()
        local widget = Widget.new(widget_payload())

        assert.equals("c1", widget.members[1].connected_channel.id)
        assert.equals("general", widget.members[1].connected_channel.name)
    end)

    it("builds a synthetic connected_channel when the channel is not in the widget's channel list", function()
        local data = widget_payload()
        data.members[1].channel_id = "unknown-channel"

        local widget = Widget.new(data)

        assert.equals("unknown-channel", widget.members[1].connected_channel.id)
        assert.equals("", widget.members[1].connected_channel.name)
    end)

    it("leaves connected_channel nil when the member has no channel_id", function()
        local data = widget_payload()
        data.members[2].channel_id = nil

        local widget = Widget.new(data)

        assert.is_nil(widget.members[2].connected_channel)
    end)

    it("carries bot/nick/status/suppress/muted flags through onto members", function()
        local widget = Widget.new(widget_payload())
        local bob = widget.members[2]

        assert.is_true(bob.bot)
        assert.equals("Bobby", bob.nick)
        assert.equals("idle", bob.status)
        assert.is_true(bob.suppress)
        assert.is_true(bob.muted)
        assert.equals("Chess", bob.activity.name)
    end)

    it("builds the json_url from the guild id", function()
        local widget = Widget.new(widget_payload())
        assert.equals("https://discord.com/api/guilds/g1/widget.json", widget:json_url())
    end)

    it("returns the raw instant_invite as invite_url", function()
        local widget = Widget.new(widget_payload())
        assert.equals("https://discord.gg/abc123", widget:invite_url())
    end)

    it("handles a widget with no invite (invite_url nil)", function()
        local data = widget_payload()
        data.instant_invite = nil

        local widget = Widget.new(data)
        assert.is_nil(widget:invite_url())
    end)

    describe("Widget:fetch_invite", function()
        it("errors when no http client is attached", function()
            local widget = Widget.new(widget_payload())

            assert.has_error(function()
                widget:fetch_invite()
            end)
        end)

        it("errors when the widget has no invite_url", function()
            local data = widget_payload()
            data.instant_invite = nil
            local widget = Widget.new(data, fake_http())

            assert.has_error(function()
                widget:fetch_invite()
            end)
        end)

        it("GETs the invite endpoint with the code stripped of the discord.gg prefix", function()
            local http = fake_http()
            local widget = Widget.new(widget_payload(), http)

            local invite = widget:fetch_invite()

            assert.equals("GET", http.calls[1].method)
            assert.equals("/invites/abc123?with_counts=true", http.calls[1].endpoint)
            assert.equals("abc123", invite.code)
        end)

        it("defaults with_counts to true and allows overriding it to false", function()
            local http = fake_http()
            local widget = Widget.new(widget_payload(), http)

            widget:fetch_invite(false)

            assert.equals("/invites/abc123?with_counts=false", http.calls[1].endpoint)
        end)

        it("accepts a bare invite code with no discord.gg prefix", function()
            local data = widget_payload()
            data.instant_invite = "abc123"
            local http = fake_http()
            local widget = Widget.new(data, http)

            widget:fetch_invite()

            assert.equals("/invites/abc123?with_counts=true", http.calls[1].endpoint)
        end)
    end)
end)
