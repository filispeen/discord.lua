-- lib/voice/sinks/sink.lua
-- Base Sink class for voice recording, contract mirrors pycord's
-- discord.sinks.core.Sink.
--
-- IMPORTANT LIMITATION: this codebase has no RTP receive loop yet.
-- lib/voice/udp.lua only sends packets; there is no
-- decrypt-incoming-RTP -> per-SSRC Opus decode -> PCM pipeline wired to
-- the voice gateway's client_connect/speaking events. Sink:write(user_id,
-- opus_data) is the intended entry point for that pipeline once it
-- exists; for now it must be called manually (or from a future RTP
-- receive handler) rather than firing automatically during a real call.
--
-- Public Contract:
--   Sink.new(opts) -> sink
--     opts.filters: table or nil - reserved for pycord-style user/time
--     filters, not enforced yet.
--
--   sink.audio_data -> table
--     user_id (string) -> { file = table (in-memory byte buffer),
--     packets = number }. Populated as write() is called per user.
--
--   sink.encoding -> string
--     File extension this sink produces (e.g. "wav", "mp3"), mirrors
--     pycord's Sink.encoding used to name output files.
--
--   sink.vc -> VoiceClient or nil
--     Set by VoiceClient:start_recording, so a finished_callback can call
--     sink.vc:disconnect() the same way pycord's example does.
--
--   sink:write(user_id, opus_data) -> nil
--     Feeds one Opus-encoded RTP payload for user_id into the sink.
--     Subclasses override this (or :init/:format, see WaveSink) to decode
--     and encode into their target container/codec.
--
--   sink:cleanup() -> nil
--     Called by VoiceClient:stop_recording. Finalizes each user's file
--     (e.g. writes container headers/trailers). Base implementation is a
--     no-op; subclasses override as needed.
--
--   sink:get_all_audio() -> table
--     Returns sink.audio_data, mirrors pycord's Sink.get_all_audio().
--
--   sink:get_user_audio(user_id) -> table or nil
--     Returns sink.audio_data[user_id], mirrors pycord's
--     Sink.get_user_audio(user_id).

local class = require("core.class")

local Sink = class("Sink")

function Sink.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Sink)

    self.filters = opts.filters or {}
    self.audio_data = {}
    self.encoding = "raw"
    self.vc = nil

    return self
end

-- Ensures audio_data[user_id] exists, returns it. Subclasses call this
-- from write() before appending data.
function Sink:_get_or_create_user_data(user_id)
    local entry = self.audio_data[user_id]
    if not entry then
        entry = { file = {}, packets = 0 }
        self.audio_data[user_id] = entry
    end
    return entry
end

function Sink:write(user_id, opus_data)
    local entry = self:_get_or_create_user_data(user_id)
    table.insert(entry.file, opus_data)
    entry.packets = entry.packets + 1
end

function Sink:cleanup()
end

function Sink:get_all_audio()
    return self.audio_data
end

function Sink:get_user_audio(user_id)
    return self.audio_data[user_id]
end

return Sink
