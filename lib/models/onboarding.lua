local class = require("../core/class")

local PromptOption = class("PromptOption")
function PromptOption.new(data)
    data = data or {}
    local self = {
        id = data.id,
        title = data.title,
        description = data.description,
        channel_ids = data.channel_ids or {},
        role_ids = data.role_ids or {},
        emoji = data.emoji,
    }
    setmetatable(self, { __index = PromptOption })
    return self
end

function PromptOption:to_dict()
    return {
        id = self.id,
        title = self.title,
        description = self.description,
        channel_ids = self.channel_ids,
        role_ids = self.role_ids,
        emoji = self.emoji,
    }
end

local OnboardingPrompt = class("OnboardingPrompt")
function OnboardingPrompt.new(data)
    data = data or {}
    local self = {
        id = data.id,
        type = data.type,
        title = data.title,
        single_select = data.single_select or false,
        required = data.required or false,
        in_onboarding = data.in_onboarding or false,
        options = {},
    }
    setmetatable(self, { __index = OnboardingPrompt })
    for index, option in ipairs(data.options or {}) do self.options[index] = PromptOption.new(option) end
    return self
end

function OnboardingPrompt:to_dict()
    local options = {}
    for index, option in ipairs(self.options) do options[index] = option:to_dict() end
    return {
        id = self.id,
        type = self.type,
        title = self.title,
        single_select = self.single_select,
        required = self.required,
        in_onboarding = self.in_onboarding,
        options = options,
    }
end

local Onboarding = class("Onboarding")
function Onboarding.new(data, guild, http)
    data = data or {}
    local self = {
        guild = guild,
        guild_id = data.guild_id or (guild and guild.id),
        enabled = data.enabled or false,
        mode = data.mode,
        default_channel_ids = data.default_channel_ids or {},
        prompts = {},
        http = http or (guild and guild.http),
    }
    setmetatable(self, { __index = Onboarding })
    for index, prompt in ipairs(data.prompts or {}) do self.prompts[index] = OnboardingPrompt.new(prompt) end
    return self
end

function Onboarding:edit(opts)
    if not self.http then error("Onboarding has no http client attached, cannot edit", 0) end
    opts = opts or {}
    local payload = {}
    if opts.prompts ~= nil then
        payload.prompts = {}
        for index, prompt in ipairs(opts.prompts) do
            payload.prompts[index] = type(prompt.to_dict) == "function" and prompt:to_dict() or prompt
        end
    end
    if opts.default_channel_ids ~= nil then payload.default_channel_ids = opts.default_channel_ids end
    if opts.enabled ~= nil then payload.enabled = opts.enabled end
    if opts.mode ~= nil then payload.mode = opts.mode end
    local Route = require("../http/route")
    return Onboarding.new(Route.new(self.http):edit_onboarding(self.guild_id, payload, opts.reason), self.guild, self.http)
end

return { Onboarding = Onboarding, OnboardingPrompt = OnboardingPrompt, PromptOption = PromptOption }
