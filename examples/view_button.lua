-- examples/view_button.lua
-- Example: Buttons with a View.
--
-- Component callbacks receive a ComponentContext (ctx) with
-- respond/update/defer for answering the interaction.

local Bot = require("discord.lua")
local View = require("ui.view")
local Button = require("ui.button")

local bot = Bot("YOUR_BOT_TOKEN")

local votes = { up = 0, down = 0 }

local vote_view = View.new({ timeout = 30000 })

vote_view:add(Button.new({
    label = "Upvote",
    style = "success",
    custom_id = "vote_up",
}))

vote_view:add(Button.new({
    label = "Downvote",
    style = "danger",
    custom_id = "vote_down",
}))

bot:interaction("vote_up", function(ctx)
    votes.up = votes.up + 1
    ctx:update("Votes: +" .. votes.up .. " / -" .. votes.down)
end)

bot:interaction("vote_down", function(ctx)
    votes.down = votes.down + 1
    ctx:update("Votes: +" .. votes.up .. " / -" .. votes.down)
end)

bot:component(vote_view)

bot:register_application_command("poll", {
    description = "Starts a simple upvote/downvote poll",
    callback = function(ctx)
        ctx:respond("Votes: +0 / -0", { components = vote_view:to_components() })
    end,
})

bot:on("ready", function()
    print("Bot is ready!")
end)

bot:run()
