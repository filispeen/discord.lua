-- lib/models/poll.lua
-- Poll model for Discord API
--
-- Public Contract:
--   PollMedia.new(text, emoji?) -> PollMedia
--     text: question/answer text. emoji: unicode emoji string, or a
--     table with .name/.id (as found on Reaction.emoji/gateway emoji
--     payloads), or nil.
--
--   PollMedia:to_dict() -> table
--     Raw payload form ({text, emoji?}) for sending to Discord.
--
--   PollMedia.from_dict(data) -> PollMedia
--
--   PollAnswer.new(text, emoji?) -> PollAnswer
--     Wraps a PollMedia as self.media, also exposes .text/.emoji
--     directly for convenience. .id is nil until the answer has been
--     returned by Discord (existing polls have sequential answer ids).
--
--   PollAnswer:count() -> number or nil
--     This answer's vote count, from its parent poll's .results. nil
--     if the answer has no id yet (not sent) or the parent poll has no
--     results (nil is "unknown", distinct from 0 votes).
--
--   PollAnswer:to_dict() -> table
--     {poll_media = self.media:to_dict(), answer_id = self.id?}
--
--   PollAnswer.from_dict(data, poll?) -> PollAnswer
--
--   PollAnswerCount.new(data) -> PollAnswerCount
--     {id, count, me} from a raw answer_counts entry.
--
--   PollAnswerCount:to_dict() -> table
--
--   PollResults.new(data) -> PollResults
--     {is_finalized, answer_counts (array of PollAnswerCount)} from a
--     raw poll results payload.
--
--   PollResults:total_votes() -> number
--     Sum of every answer's count. May be imprecise while
--     is_finalized is false.
--
--   PollResults:to_dict() -> table
--
--   Poll.new(question, opts?) -> Poll
--     question: string or PollMedia. opts.answers: array of PollAnswer
--     (default {}). opts.duration: hours until expiry, default 24.
--     opts.allow_multiselect: default false. opts.layout_type: default 1.
--
--   Poll:add_answer(text, emoji?) -> Poll (self, for chaining)
--     Errors if the poll already has 10 answers, text is over 55
--     characters, or the poll already came from Discord (has an
--     expiry or attached message).
--
--   Poll:get_answer(id) -> PollAnswer or nil
--
--   Poll:has_ended() -> boolean or nil
--     Shortcut for self.results.is_finalized. nil if results are
--     unknown (poll not sent, or not yet returned with results).
--
--   Poll:total_votes() -> number or nil
--     Shortcut for self.results:total_votes(). nil if results are
--     unknown.
--
--   Poll:to_dict() -> table
--     Raw payload form for sending via Message:reply({poll = ...})
--     and similar send calls.
--
--   Poll.from_dict(data, message?) -> Poll
--     message: the owning Message instance, if any, stored as
--     self.message and used by Poll:end_poll().
--
--   Poll:end_poll() -> table
--     Shortcut for self.message:end_poll(). Errors if this poll was
--     not received from a message.

local class = require("../core/class")

local PollMedia = class("PollMedia")
local PollAnswer = class("PollAnswer")
local PollAnswerCount = class("PollAnswerCount")
local PollResults = class("PollResults")
local Poll = class("Poll")

function PollMedia.new(text, emoji)
    local self = {}
    setmetatable(self, { __index = PollMedia })
    self.text = text
    self.emoji = emoji
    return self
end

function PollMedia:to_dict()
    local dict = { text = self.text }
    if self.emoji then
        if type(self.emoji) == "string" then
            dict.emoji = { name = self.emoji }
        elseif self.emoji.id then
            dict.emoji = { id = self.emoji.id }
        else
            dict.emoji = { name = self.emoji.name }
        end
    end
    return dict
end

function PollMedia.from_dict(data)
    return PollMedia.new(data.text, data.emoji)
end

function PollAnswer.new(text, emoji)
    local self = {}
    setmetatable(self, { __index = PollAnswer })
    self.media = PollMedia.new(text, emoji)
    self.text = text
    self.emoji = emoji
    self.id = nil
    self.poll = nil
    return self
end

function PollAnswer:count()
    if not (self.poll and self.id) then
        return nil
    end
    if not self.poll.results then
        return nil
    end
    for _, answer_count in ipairs(self.poll.results.answer_counts) do
        if answer_count.id == self.id then
            return answer_count.count
        end
    end
    return 0
end

function PollAnswer:to_dict()
    local dict = { poll_media = self.media:to_dict() }
    if self.id ~= nil then
        dict.answer_id = self.id
    end
    return dict
end

function PollAnswer.from_dict(data, poll)
    local media = PollMedia.from_dict(data.poll_media)
    local answer = PollAnswer.new(media.text, media.emoji)
    answer.id = data.answer_id
    answer.poll = poll
    return answer
end

function PollAnswerCount.new(data)
    local self = {}
    setmetatable(self, { __index = PollAnswerCount })
    self.id = data.id
    self.count = data.count or 0
    self.me = data.me_voted or false
    return self
end

function PollAnswerCount:to_dict()
    return { id = self.id, count = self.count, me_voted = self.me }
end

function PollResults.new(data)
    local self = {}
    setmetatable(self, { __index = PollResults })
    self.is_finalized = data.is_finalized or false
    self.answer_counts = {}
    for _, entry in ipairs(data.answer_counts or {}) do
        table.insert(self.answer_counts, PollAnswerCount.new(entry))
    end
    return self
end

function PollResults:total_votes()
    local total = 0
    for _, answer_count in ipairs(self.answer_counts) do
        total = total + answer_count.count
    end
    return total
end

function PollResults:to_dict()
    local counts = {}
    for _, answer_count in ipairs(self.answer_counts) do
        table.insert(counts, answer_count:to_dict())
    end
    return { is_finalized = self.is_finalized, answer_counts = counts }
end

function Poll.new(question, opts)
    opts = opts or {}
    local self = {}
    setmetatable(self, { __index = Poll })

    if type(question) == "table" then
        self.question = question
    else
        self.question = PollMedia.new(question)
    end

    self.answers = opts.answers or {}
    self.duration = opts.duration or 24
    self.allow_multiselect = opts.allow_multiselect or false
    self.layout_type = opts.layout_type or 1
    self.results = nil
    self.expiry = nil
    self.message = nil

    return self
end

function Poll:add_answer(text, emoji)
    if #self.answers >= 10 then
        error("Polls may only have up to 10 answers.", 0)
    end
    if #text > 55 then
        error("text length must be between 1 and 55 characters.", 0)
    end
    if self.expiry or self.message then
        error("You cannot add answers to an existing poll.", 0)
    end

    local answer = PollAnswer.new(text, emoji)
    answer.poll = self
    table.insert(self.answers, answer)
    return self
end

function Poll:get_answer(id)
    for _, answer in ipairs(self.answers) do
        if answer.id == id then
            return answer
        end
    end
    return nil
end

function Poll:has_ended()
    if not self.results then
        return nil
    end
    return self.results.is_finalized
end

function Poll:total_votes()
    if not self.results then
        return nil
    end
    return self.results:total_votes()
end

function Poll:to_dict()
    local answers = {}
    for _, answer in ipairs(self.answers) do
        table.insert(answers, answer:to_dict())
    end

    local dict = {
        question = self.question:to_dict(),
        answers = answers,
        duration = self.duration,
        allow_multiselect = self.allow_multiselect,
        layout_type = self.layout_type,
    }
    if self.results then
        dict.results = self.results:to_dict()
    end
    if self.expiry then
        dict.expiry = self.expiry
    end
    return dict
end

function Poll.from_dict(data, message)
    if not data then
        return nil
    end

    local answers = {}
    for _, entry in ipairs(data.answers or {}) do
        table.insert(answers, PollAnswer.from_dict(entry))
    end

    local poll = Poll.new(PollMedia.from_dict(data.question), {
        answers = answers,
        duration = data.duration,
        allow_multiselect = data.allow_multiselect,
        layout_type = data.layout_type or 1,
    })

    if data.results then
        poll.results = PollResults.new(data.results)
    end
    poll.expiry = data.expiry
    poll.message = message

    for _, answer in ipairs(poll.answers) do
        answer.poll = poll
    end

    return poll
end

function Poll:end_poll()
    if not self.message then
        error("You can only end a poll received from a message.", 0)
    end
    return self.message:end_poll()
end

return {
    Poll = Poll,
    PollMedia = PollMedia,
    PollAnswer = PollAnswer,
    PollAnswerCount = PollAnswerCount,
    PollResults = PollResults,
}
