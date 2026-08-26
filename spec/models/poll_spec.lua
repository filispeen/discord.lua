-- spec/models/poll_spec.lua
-- Tests for poll model

require("spec_helper")

local poll_module = require("./models/poll")
local Poll = poll_module.Poll
local PollMedia = poll_module.PollMedia
local PollAnswer = poll_module.PollAnswer
local PollResults = poll_module.PollResults

describe("PollMedia", function()
    it("builds a raw dict without an emoji", function()
        local media = PollMedia.new("Favorite color?")
        assert.same({ text = "Favorite color?" }, media:to_dict())
    end)

    it("builds a raw dict with a unicode emoji string", function()
        local media = PollMedia.new("Red", "❤")
        assert.equals("❤", media:to_dict().emoji.name)
    end)

    it("builds a raw dict with a custom emoji table", function()
        local media = PollMedia.new("Pog", { id = "9", name = "pog" })
        assert.equals("9", media:to_dict().emoji.id)
    end)

    it("parses from a raw dict", function()
        local media = PollMedia.from_dict({ text = "Blue", emoji = { name = "💙" } })
        assert.equals("Blue", media.text)
        assert.equals("💙", media.emoji.name)
    end)
end)

describe("PollAnswer", function()
    it("exposes text and emoji directly", function()
        local answer = PollAnswer.new("Red", "❤")
        assert.equals("Red", answer.text)
        assert.equals("❤", answer.emoji)
    end)

    it("has no count before it belongs to a poll with results", function()
        local answer = PollAnswer.new("Red")
        assert.is_nil(answer:count())
    end)

    it("returns 0 votes when missing from results.answer_counts", function()
        local poll = Poll.new("Q")
        poll:add_answer("Red")
        poll.results = PollResults.new({ is_finalized = false, answer_counts = {} })
        poll.answers[1].id = 1

        assert.equals(0, poll.answers[1]:count())
    end)

    it("returns its vote count from the poll's results", function()
        local poll = Poll.new("Q")
        poll:add_answer("Red")
        poll.answers[1].id = 1
        poll.results = PollResults.new({
            is_finalized = true,
            answer_counts = { { id = 1, count = 5, me_voted = true } },
        })

        assert.equals(5, poll.answers[1]:count())
    end)

    it("round-trips through to_dict/from_dict", function()
        local answer = PollAnswer.new("Red", { name = "❤" })
        answer.id = 3
        local dict = answer:to_dict()

        assert.equals(3, dict.answer_id)
        assert.equals("Red", dict.poll_media.text)

        local parsed = PollAnswer.from_dict(dict)
        assert.equals("Red", parsed.text)
        assert.equals(3, parsed.id)
    end)
end)

describe("PollResults", function()
    it("sums votes across answers", function()
        local results = PollResults.new({
            is_finalized = true,
            answer_counts = {
                { id = 1, count = 3 },
                { id = 2, count = 7 },
            },
        })

        assert.equals(10, results:total_votes())
    end)

    it("defaults to zero total votes with no answers", function()
        local results = PollResults.new({})
        assert.equals(0, results:total_votes())
    end)
end)

describe("Poll", function()
    it("wraps a plain string question in PollMedia", function()
        local poll = Poll.new("Favorite color?")
        assert.equals("Favorite color?", poll.question.text)
    end)

    it("defaults duration/allow_multiselect/layout_type", function()
        local poll = Poll.new("Q")
        assert.equals(24, poll.duration)
        assert.is_false(poll.allow_multiselect)
        assert.equals(1, poll.layout_type)
    end)

    it("adds answers fluently", function()
        local poll = Poll.new("Q"):add_answer("Red"):add_answer("Blue")
        assert.equals(2, #poll.answers)
        assert.equals("Blue", poll.answers[2].text)
    end)

    it("errors when adding an 11th answer", function()
        local poll = Poll.new("Q")
        for i = 1, 10 do
            poll:add_answer("Answer " .. i)
        end
        assert.has_error(function()
            poll:add_answer("One too many")
        end)
    end)

    it("errors when answer text exceeds 55 characters", function()
        local poll = Poll.new("Q")
        assert.has_error(function()
            poll:add_answer(string.rep("x", 56))
        end)
    end)

    it("errors when adding an answer to an existing poll", function()
        local poll = Poll.new("Q")
        poll.expiry = "2026-01-01T00:00:00Z"
        assert.has_error(function()
            poll:add_answer("Too late")
        end)
    end)

    it("finds an answer by id", function()
        local poll = Poll.new("Q")
        poll:add_answer("Red")
        poll.answers[1].id = 7
        assert.equals(poll.answers[1], poll:get_answer(7))
        assert.is_nil(poll:get_answer(99))
    end)

    it("has_ended and total_votes are nil without results", function()
        local poll = Poll.new("Q")
        assert.is_nil(poll:has_ended())
        assert.is_nil(poll:total_votes())
    end)

    it("reflects results once attached", function()
        local poll = Poll.new("Q")
        poll.results = PollResults.new({ is_finalized = true, answer_counts = { { id = 1, count = 4 } } })
        assert.is_true(poll:has_ended())
        assert.equals(4, poll:total_votes())
    end)

    it("round-trips through to_dict/from_dict", function()
        local poll = Poll.new("Favorite color?", { allow_multiselect = true })
        poll:add_answer("Red"):add_answer("Blue")

        local dict = poll:to_dict()
        assert.equals("Favorite color?", dict.question.text)
        assert.equals(2, #dict.answers)
        assert.is_true(dict.allow_multiselect)

        local parsed = Poll.from_dict(dict)
        assert.equals("Favorite color?", parsed.question.text)
        assert.equals(2, #parsed.answers)
        assert.equals(poll, poll.answers[1].poll)
    end)

    it("wires answer.poll back-references on from_dict", function()
        local dict = {
            question = { text = "Q" },
            answers = { { poll_media = { text = "Red" }, answer_id = 1 } },
            duration = 24,
            allow_multiselect = false,
            layout_type = 1,
        }

        local poll = Poll.from_dict(dict)
        assert.equals(poll, poll.answers[1].poll)
    end)

    it("errors on end_poll without an attached message", function()
        local poll = Poll.new("Q")
        assert.has_error(function()
            poll:end_poll()
        end)
    end)

    it("delegates end_poll to its attached message", function()
        local calls = {}
        local fake_message = {
            end_poll = function()
                table.insert(calls, true)
                return { id = "1" }
            end,
        }
        local poll = Poll.from_dict({
            question = { text = "Q" },
            answers = {},
            duration = 24,
            allow_multiselect = false,
            layout_type = 1,
        }, fake_message)

        poll:end_poll()
        assert.equals(1, #calls)
    end)
end)
