# Additional models

This page groups public model families that are returned by `Client`, `Guild`, `Channel`, message payloads, or REST helpers. They are backed by the current Discord route implementation; they do not all have package-level constructors.

## REST resource models

| Family | Main model(s) | Where used |
|---|---|---|
| Invites and webhooks | `Invite`, `Webhook` | Channel/guild REST operations. |
| Threads and forum data | `Thread` | Channel creation and gateway thread events. |
| Emoji and stickers | `Emoji`, `PartialEmoji`, `Sticker` | Guild/application emoji and guild sticker routes. |
| Polls | `Poll`, `PollAnswer` | `Message.poll` and poll vote gateway updates. |
| Events and moderation | `ScheduledEvent`, `AutoModRule`, audit-log models | Guild REST APIs and gateway events. |
| Community configuration | `Onboarding`, `WelcomeScreen`, `Widget`, `Template`, `StageInstance` | Guild configuration routes. |
| Soundboard | `Sound` | `Bot:fetch_default_sounds`, guild sound routes, voice-channel playback. |
| Applications and monetization | Application info, role-connection metadata, SKU, Entitlement, Subscription | `Client` application methods and gateway events. |

## Polls

`Message.poll` is populated when a message payload contains a poll. `PollAnswer:count()` returns the recorded count, `0` when results exist but the answer is absent, and `nil` when no poll/result data exists. Poll vote gateway handlers update cached messages when possible.

## Scheduled events

Use [`Guild:fetch_scheduled_event`](guilds-members-users-roles.md#guildfetch_scheduled_eventevent_id-with_user_count) and [`Guild:create_scheduled_event`](guilds-members-users-roles.md#guildcreate_scheduled_eventopts) rather than constructing request tables manually.

## Route coverage

The library has direct HTTP route support for many Discord resources. A model is only useful with an attached HTTP client for mutation/fetch methods; models built from raw gateway data may deliberately have no HTTP reference. Catch or avoid calls that require HTTP before the bot has connected.

For REST endpoints not wrapped by a documented model, use the official [Discord API documentation](https://discord.com/developers/docs/reference). This reference intentionally does not claim generic endpoint support beyond code present in this repository.
