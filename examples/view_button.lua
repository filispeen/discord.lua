-- examples/view_button.lua
-- Example: Button with View timeout
--
-- Demonstrates using Buttons with a View that auto-removes after timeout.

local Bot = require("discord.lua")
local BotClass = Bot

local view = require("ui.view")
local button = require("ui.button")

local client = BotClass("YOUR_BOT_TOKEN")

-- Create a view with a button
local vote_view = view:new()

vote_view:add(button:new({
    label = "Upvote",
    style = "success",
    custom_id = "vote_up",
    disabled = false,
}))

vote_view:add(button:new({
    label = "Downvote",
    style = "danger",
    custom_id = "vote_down",
    disabled = false,
}))

-- Set timeout (30 seconds)
vote_view:timeout(30000)

-- Register the view with the client
client:component(vote_view)

-- Handle button interactions
local _ = client:interaction("vote_up", function(interaction)
    local original = interaction:original_message()
    original.content = original.content:gsub("([+])", function()
        return "+" .. string.rep("+", 2)
    end)
    interaction:edit_message(original)
    vote_view:remove(interaction)
end)

local _ = client:interaction("vote_down", function(interaction)
    local original = interaction:original_message()
    original.content = original.content:gsub("(-)", function()
        return "-" .. string.rep("-", 2)
    end)
    interaction:edit_message(original)
    vote_view:remove(interaction)
end)

client:on("ready", function()
    print("Bot is ready!")

    local guild_id = "123456789"
    local channel_id = "987654321"
    local message_id = "111222333"

    client:edit_message(guild_id, channel_id, message_id, {
        content = "Vote on this!",
        embeds = {
            client:embed({
                title = "My Poll",
                description = "What do you think?",
            }),
        },
        components = {
            {
                type = "ACTION_ROW",
                components = {
                    {
                        type = "BUTTON",
                        style = "SUCCESS",
                        label = "Upvote",
                        custom_id = "vote_up",
                        disabled = false,
                    },
                    {
                        type = "BUTTON",
                        style = "DANGER",
                        label = "Downvote",
                        custom_id = "vote_down",
                        disabled = false,
                    },
                },
            },
        },
    })
end)

client:run()
