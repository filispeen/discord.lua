require("spec_helper")

local Asset = require("./models/asset")
local Colour = require("./models/colour").Colour
local PartialEmoji = require("./models/partial_emoji")
local AllowedMentions = require("./models/allowed_mentions")
local Flags = require("./models/flags")
local Permission = require("./models/permission")
local Message = require("./models/message")
local Embed = require("./models/embed")
local User = require("./models/user")

describe("core utility models", function()
    it("builds and transforms CDN assets", function()
        local asset = Asset.from_avatar("u1", "a_hash")
        local resized = asset:with_size(128)
        local webp = resized:with_format("webp")

        assert.equals("https://cdn.discordapp.com/avatars/u1/a_hash.gif", asset.url)
        assert.equals("https://cdn.discordapp.com/avatars/u1/a_hash.gif?size=128", resized.url)
        assert.equals("https://cdn.discordapp.com/avatars/u1/a_hash.webp?size=128", webp.url)
        assert.has_error(function() asset:with_size(100) end)
    end)

    it("converts colours between integer, RGB and hex forms", function()
        local colour = Colour.from_rgb(88, 101, 242)

        assert.equals(0x5865F2, colour.value)
        assert.same({ 88, 101, 242 }, { colour:to_rgb() })
        assert.equals("#5865f2", colour:to_hex())
        assert.equals(0xE74C3C, Colour.from_hex("#e74c3c").value)
    end)

    it("models custom and unicode partial emojis", function()
        local custom = PartialEmoji.from_str("<a:party:123>")
        local unicode = PartialEmoji.from_str("🎉")

        assert.equals("123", custom.id)
        assert.is_true(custom.animated)
        assert.equals("party:123", custom:as_reaction())
        assert.equals("<a:party:123>", custom:to_string())
        assert.is_true(unicode:is_unicode_emoji())
        assert.equals("🎉", unicode:to_dict().name)
    end)

    it("serializes and merges allowed mentions", function()
        local base = AllowedMentions.none()
        local merged = base:merge(AllowedMentions.new({ users = { { id = "u1" } } }))
        local data = merged:to_dict()

        assert.same({ "u1" }, data.users)
        assert.same({}, data.parse)
        assert.is_nil(data.replied_user)
    end)

    it("passes AllowedMentions instances into message payloads", function()
        local sent
        local message = Message.new({ id = "m1", channel_id = "c1" }, {
            post = function(_, _, payload) sent = payload end,
        })

        message:reply("hello", { allowed_mentions = AllowedMentions.none() })

        assert.same({}, sent.allowed_mentions.parse)
        assert.is_nil(sent.allowed_mentions.replied_user)
    end)

    it("supports named flag sets and extended permissions", function()
        local flags = Flags.MessageFlags.new({ ephemeral = true, loading = true })
        local permissions = Permission.Permissions.new({ manage_threads = true, send_polls = true })

        assert.is_true(flags:has("ephemeral"))
        assert.is_true(flags:has("loading"))
        assert.equals(192, flags:to_number())
        assert.is_true(permissions:has("MANAGE_THREADS"))
        assert.is_true(permissions:has(Permission.SEND_POLLS))
        permissions:handle_overwrite(Permission.SEND_MESSAGES, Permission.MANAGE_THREADS)
        assert.is_false(permissions:has("manage_threads"))
        assert.is_true(permissions:has("send_messages"))
    end)

    it("keeps numeric embed colour fields while accepting Colour", function()
        local embed = Embed.new({}):with_color(Colour.blurple())
        local user = User.new({ id = "u1", username = "name", discriminator = "0", avatar = "hash" })

        assert.equals(0x5865F2, embed.color)
        assert.equals("https://cdn.discordapp.com/avatars/u1/hash.png", user.avatar_asset.url)
    end)
end)
