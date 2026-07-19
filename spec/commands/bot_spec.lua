-- spec/commands/bot_spec.lua
-- Tests for bot class

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

-- Mock json so Bot:connect() -> Client:_create_http() -> http.client can
-- load without a real luvit environment; nothing in this spec's tests
-- actually sends a request, so encode/decode are never exercised.
package.loaded["json"] = {
    encode = function(value) return "" end,
    decode = function(value) return {} end,
}

-- Clear module cache to ensure fresh load
-- Don't clear core.class - checks_spec loads it first
package.loaded["commands.bot"] = nil

local Bot = require("commands.bot")

local function table_count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

describe("Bot", function()
    it("creates a new bot", function()
        local bot = Bot.new("token", {})

        assert.equals("token", bot.token)
        assert.same({}, bot.ratelimiter)
        assert.equals(0, table_count(bot.commands))
        assert.equals(0, table_count(bot.cogs))
        assert.equals("!", bot.prefix)
    end)

    it("registers a command", function()
        local bot = Bot.new("token")
        local handler = function(ctx, args) return "test" end
        bot:register_command("test", handler, "!")

        assert.equals(handler, bot.commands["test"])
        assert.equals("!", bot.prefixes["test"])
    end)

    it("registers an application command", function()
        local bot = Bot.new("token")
        bot:register_application_command("test", {name = "test", description = "A test command"})

        assert.equals(1, table_count(bot.application_commands))
        assert.equals("test", bot.application_commands["test"].name)
    end)

    it("unregisters a command", function()
        local bot = Bot.new("token")
        bot:register_command("test", function(ctx, args) return "test" end, "!")
        bot:unregister_command("test")

        assert.equals(nil, bot.commands["test"])
        assert.equals(nil, bot.prefixes["test"])
    end)

    it("subscribes to an event", function()
        local bot = Bot.new("token")
        local callback_called = false

        bot:on("ready", function() callback_called = true end)

        assert.equals(1, #bot.listeners["ready"])
    end)

    it("emits an event", function()
        local bot = Bot.new("token")
        local callback_called = false

        bot:on("ready", function() callback_called = true end)
        bot:emit("ready")

        assert.is_true(callback_called)
    end)

    it("adds a cog", function()
        local bot = Bot.new("token")
        local cog = { name = "test", commands = {}, listeners = {} }

        bot:add_cog(cog)

        assert.equals(1, table_count(bot.cogs))
        assert.equals(cog, bot.cogs["test"])
    end)

    it("removes a cog", function()
        local bot = Bot.new("token")
        local cog = { name = "test", commands = {}, listeners = {} }

        bot:add_cog(cog)
        bot:remove_cog(cog)

        assert.equals(nil, bot.cogs["test"])
    end)

    it("gets a command", function()
        local bot = Bot.new("token")
        local handler = function(ctx, args) return "test" end
        bot:register_command("test", handler, "!")

        local command = bot:get_command("test")

        assert.is_not_nil(command)
        assert.equals(handler, command)
        assert.equals("test", command())
    end)

    it("gets all commands", function()
        local bot = Bot.new("token")
        bot:register_command("test1", function(ctx, args) return "test1" end, "!")
        bot:register_command("test2", function(ctx, args) return "test2" end, "!")

        local commands = bot:get_commands()

        assert.equals(2, table_count(commands))
    end)

    it("emits an event with multiple listeners", function()
        local bot = Bot.new("token")
        local call_count = 0

        bot:on("test", function() call_count = call_count + 1 end)
        bot:on("test", function() call_count = call_count + 1 end)
        bot:on("test", function() call_count = call_count + 1 end)

        bot:emit("test")

        assert.equals(3, call_count)
    end)

    it("registers a command through the command shorthand", function()
        local bot = Bot.new("token")
        local handler = function(msg) return "pong" end

        bot:command("ping", handler)

        assert.equals(handler, bot.commands["ping"])
        assert.equals("!", bot.prefixes["ping"])
    end)

    it("builds an embed", function()
        local bot = Bot.new("token")
        local embed = bot:embed({ title = "hello" })

        assert.equals("hello", embed.title)
    end)

    it("registers a view through component", function()
        local bot = Bot.new("token")
        local view = { items = {} }

        bot:component(view)

        assert.equals(1, #bot.components)
        assert.equals(view, bot.components[1])
    end)

    it("registers and dispatches an interaction callback by custom_id", function()
        local bot = Bot.new("token")
        local received = nil

        bot:interaction("confirm", function(interaction) received = interaction.custom_id end)
        local handled = bot:dispatch_interaction({ custom_id = "confirm" })

        assert.is_true(handled)
        assert.equals("confirm", received)
    end)

    it("returns false when dispatching an interaction with no matching callback", function()
        local bot = Bot.new("token")

        local handled = bot:dispatch_interaction({ custom_id = "unknown" })

        assert.is_false(handled)
    end)

    it("dispatches a prefix command from an incoming message", function()
        local bot = Bot.new("token")
        local received_content = nil

        bot:command("ping", function(msg) received_content = msg.content end)
        local handled = bot:dispatch_message({ content = "!ping" })

        assert.is_true(handled)
        assert.equals("!ping", received_content)
    end)

    it("does not dispatch a message without the command prefix", function()
        local bot = Bot.new("token")
        bot:command("ping", function(msg) end)

        local handled = bot:dispatch_message({ content = "ping" })

        assert.is_false(handled)
    end)

    it("does not dispatch a message with an unregistered command name", function()
        local bot = Bot.new("token")
        bot:command("ping", function(msg) end)

        local handled = bot:dispatch_message({ content = "!unknown" })

        assert.is_false(handled)
    end)

    it("runs registered checks before invoking a prefix command's callback", function()
        local bot = Bot.new("token")
        local invoked = false
        local passing_check = { name = "always", func = function() return true end }

        bot:register_command("ping", function() invoked = true end, "!", "", { passing_check })
        bot:dispatch_message({ content = "!ping" })

        assert.is_true(invoked)
    end)

    it("blocks a prefix command's callback when a check fails", function()
        local bot = Bot.new("token")
        local invoked = false
        local failing_check = { name = "blocked", func = function() return false end }

        bot:register_command("ping", function() invoked = true end, "!", "", { failing_check })
        bot:dispatch_message({ content = "!ping" })

        assert.is_false(invoked)
    end)

    it("enforces cooldown checks on a prefix command and emits command_error", function()
        local cooldown = require("commands.cooldown")
        local bot = Bot.new("token")
        local invoke_count = 0
        local error_received = nil

        bot:on("command_error", function(_msg, err) error_received = err end)
        bot:register_command("ping", function() invoke_count = invoke_count + 1 end, "!", "", {
            cooldown.cooldown(1, 5, cooldown.BucketType.user),
        })

        local message = { content = "!ping", author = { id = "1" } }
        bot:dispatch_message(message)
        bot:dispatch_message(message)

        assert.are.equal(1, invoke_count)
        assert.is_not_nil(error_received)
        assert.are.equal("CommandOnCooldown", error_received._name)
    end)

    it("routes a component interaction to a registered View's item callback", function()
        local View = require("ui.view")
        local Button = require("ui.button")

        local bot = Bot.new("token")
        local view = View.new()
        local clicked = false
        view:add(Button.new({
            label = "Click me",
            custom_id = "click",
            callback = function() clicked = true end,
        }))
        bot:component(view)

        local handled = bot:dispatch_interaction({ custom_id = "click" })

        assert.is_true(handled)
        assert.is_true(clicked)
    end)

    it("does not route a component interaction through a stopped View", function()
        local View = require("ui.view")
        local Button = require("ui.button")

        local bot = Bot.new("token")
        local view = View.new()
        local clicked = false
        view:add(Button.new({
            label = "Click me",
            custom_id = "click",
            callback = function() clicked = true end,
        }))
        view:stop()
        bot:component(view)

        local handled = bot:dispatch_interaction({ custom_id = "click" })

        assert.is_false(handled)
        assert.is_false(clicked)
    end)

    it("falls back to Bot:interaction when no View claims the custom_id", function()
        local View = require("ui.view")
        local Button = require("ui.button")

        local bot = Bot.new("token")
        local view = View.new()
        view:add(Button.new({ label = "Other", custom_id = "other" }))
        bot:component(view)

        local received = nil
        bot:interaction("confirm", function(interaction) received = interaction.custom_id end)

        local handled = bot:dispatch_interaction({ custom_id = "confirm" })

        assert.is_true(handled)
        assert.equals("confirm", received)
    end)

    it("dispatches an autocomplete interaction through the command tree", function()
        local bot = Bot.new("token")
        local received_value = nil

        local cmd = bot:register_application_command("search", {
            description = "Search",
            options = { { name = "query", type = 3 } },
        })
        cmd:set_autocomplete("query", function(ctx)
            received_value = ctx.value
        end)

        local handled = bot:dispatch_interaction({
            type = 4,
            data = {
                name = "search",
                options = { { name = "query", value = "abc", focused = true } },
            },
        })

        assert.is_true(handled)
        assert.equals("abc", received_value)
    end)

    it("gives the autocomplete callback access to other options via ctx.options", function()
        local bot = Bot.new("token")
        local received_color = nil

        local cmd = bot:register_application_command("ac_example", {
            description = "Autocomplete example",
            options = {
                { name = "color", type = 3 },
                { name = "animal", type = 3 },
            },
        })
        cmd:set_autocomplete("animal", function(ctx)
            received_color = ctx.options["color"]
        end)

        local handled = bot:dispatch_interaction({
            type = 4,
            data = {
                name = "ac_example",
                options = {
                    { name = "color", value = "red" },
                    { name = "animal", value = "car", focused = true },
                },
            },
        })

        assert.is_true(handled)
        assert.equals("red", received_color)
    end)

    it("generate_help_text lists every registered command", function()
        local bot = Bot.new("token")
        bot:command("ping", function() end, "Replies with pong")
        bot:command("echo", function() end, "Echoes your message")

        local text = bot:generate_help_text()

        assert.is_not_nil(text:find("!ping"))
        assert.is_not_nil(text:find("Replies with pong"))
        assert.is_not_nil(text:find("!echo"))
    end)

    it("generate_help_text describes a single command by name", function()
        local bot = Bot.new("token")
        bot:command("ping", function() end, "Replies with pong")

        local text = bot:generate_help_text("ping")

        assert.is_not_nil(text:find("!ping"))
        assert.is_not_nil(text:find("Replies with pong"))
    end)

    it("generate_help_text reports an unknown command by name", function()
        local bot = Bot.new("token")

        local text = bot:generate_help_text("missing")

        assert.is_not_nil(text:find("No command"))
    end)

    it("register_help_command is opt-in and does not run at Bot.new", function()
        local bot = Bot.new("token")

        assert.is_nil(bot.commands["help"])

        bot:register_help_command()

        assert.is_not_nil(bot.commands["help"])
    end)

    it("forwards shard_ready from the client to bot's own listeners", function()
        local bot = Bot.new("token")
        bot:connect()

        local received = nil
        bot:on("shard_ready", function(payload) received = payload end)

        bot.client:emit("shard_ready", { shard_id = 0 })

        assert.is_not_nil(received)
        assert.equals(0, received.shard_id)
    end)

    it("forwards shard_error and shard_disconnect from the client", function()
        local bot = Bot.new("token")
        bot:connect()

        local error_received, disconnect_received = false, false
        bot:on("shard_error", function() error_received = true end)
        bot:on("shard_disconnect", function() disconnect_received = true end)

        bot.client:emit("shard_error", { shard_id = 0, error = "boom" })
        bot.client:emit("shard_disconnect", { shard_id = 0 })

        assert.is_true(error_received)
        assert.is_true(disconnect_received)
    end)

    it("bot.user is nil before the client has received READY", function()
        local bot = Bot.new("token")
        bot:connect()

        assert.is_nil(bot.user)
    end)

    it("bot.user reads live from the client once populated, mirrors pycord's Bot.user", function()
        local bot = Bot.new("token")
        bot:connect()

        bot.client.user = { id = "1", username = "TestBot" }

        assert.equals("TestBot", bot.user.username)
    end)

    it("bot.user is nil when the bot has never connected", function()
        local bot = Bot.new("token")

        assert.is_nil(bot.user)
    end)

    it("forwards voice_state_update from the client to bot's own listeners", function()
        local bot = Bot.new("token")
        bot:connect()

        local received = nil
        bot:on("voice_state_update", function(payload) received = payload end)

        bot.client:emit("voice_state_update", { guild_id = "1", channel_id = "2" })

        assert.is_not_nil(received)
        assert.equals("1", received.guild_id)
    end)

    it("forwards voice_server_update from the client to bot's own listeners", function()
        local bot = Bot.new("token")
        bot:connect()

        local received = nil
        bot:on("voice_server_update", function(payload) received = payload end)

        bot.client:emit("voice_server_update", { guild_id = "1", endpoint = "example.discord.media" })

        assert.is_not_nil(received)
        assert.equals("example.discord.media", received.endpoint)
    end)

    it("get_voice_channel_id returns nil before connect", function()
        local bot = Bot.new("token")
        assert.is_nil(bot:get_voice_channel_id("guild1", "user1"))
    end)

    it("get_voice_channel_id reads from the real VOICE_STATE_UPDATE dispatch path", function()
        local bot = Bot.new("token")
        bot:connect()

        -- Route through the client's real dispatch handler (registered in
        -- start_gateway), not bot.client:emit, so this exercises the same
        -- code path a live gateway would use to populate voice_states.
        bot.client.voice_states:update({
            guild_id = "guild1",
            user_id = "user1",
            channel_id = "channel1",
        })

        assert.equals("channel1", bot:get_voice_channel_id("guild1", "user1"))
    end)

    it("get_author_voice_channel_id resolves from a message's author and guild_id", function()
        local bot = Bot.new("token")
        bot:connect()

        bot.client.voice_states:update({
            guild_id = "guild1",
            user_id = "user1",
            channel_id = "channel1",
        })

        local message = { guild_id = "guild1", author = { id = "user1" } }
        assert.equals("channel1", bot:get_author_voice_channel_id(message))
    end)

    it("get_author_voice_channel_id returns nil for a DM message (no guild_id)", function()
        local bot = Bot.new("token")
        bot:connect()

        local message = { guild_id = nil, author = { id = "user1" } }
        assert.is_nil(bot:get_author_voice_channel_id(message))
    end)

    it("get_author_voice_channel_id returns nil when the author is not in voice", function()
        local bot = Bot.new("token")
        bot:connect()

        local message = { guild_id = "guild1", author = { id = "user_not_in_voice" } }
        assert.is_nil(bot:get_author_voice_channel_id(message))
    end)
end)