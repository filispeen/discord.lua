from __future__ import annotations

import gzip
import json
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urljoin

SEO = {
    "index.md": (
        "Discord Bot Library for Lua and Luvit",
        "Build Discord bots in Lua with discord.lua, a modern Luvit library for gateway events, slash commands, components, voice, sharding, and REST APIs.",
    ),
    "getting-started/installation.md": (
        "Install discord.lua for Lua and Luvit",
        "Install discord.lua with Lit and configure the Lua/Luvit runtime, including the native dependencies used for Discord voice playback and recording.",
    ),
    "getting-started/first-bot.md": (
        "Build Your First Discord Bot in Lua",
        "Create and run your first Discord bot in Lua with discord.lua and Luvit, including gateway events, prefix commands, tokens, and replies.",
    ),
    "getting-started/configuration.md": (
        "Configure a Discord Bot with discord.lua",
        "Configure Discord intents, command behavior, tokens, and client options for Lua bots built with discord.lua on the Luvit runtime.",
    ),
    "guides/events.md": (
        "Discord Gateway Events in Lua",
        "Handle Discord Gateway events in Lua with discord.lua, including ready, message, guild, member, reaction, and voice-state event flows.",
    ),
    "guides/prefix-commands.md": (
        "Discord Prefix Commands in Lua",
        "Create Discord prefix commands in Lua with discord.lua, including arguments, aliases, help text, checks, cooldowns, and command errors.",
    ),
    "guides/slash-commands.md": (
        "Discord Slash Commands in Lua",
        "Create Discord slash commands in Lua with discord.lua, including options, guild commands, autocomplete, deferred responses, and follow-ups.",
    ),
    "guides/command-groups-and-menus.md": (
        "Discord Command Groups and Context Menus in Lua",
        "Build Discord slash-command groups, user commands, and message context menus in Lua with discord.lua and Luvit.",
    ),
    "guides/hybrid-commands.md": (
        "Hybrid Discord Commands in Lua",
        "Use discord.lua hybrid commands to share Lua command logic between prefix commands and Discord application commands.",
    ),
    "guides/interactions-and-responses.md": (
        "Discord Interactions and Responses in Lua",
        "Handle Discord interactions in Lua with discord.lua, including replies, deferred responses, edits, follow-ups, and interaction contexts.",
    ),
    "guides/components-and-views.md": (
        "Discord Buttons, Components, Views, and Modals in Lua",
        "Build interactive Discord UIs in Lua with buttons, selects, views, modals, and Components v2 using discord.lua.",
    ),
    "guides/embeds-and-files.md": (
        "Discord Embeds and File Uploads in Lua",
        "Send Discord embeds, attachments, and files from Lua bots with discord.lua, including message and interaction response examples.",
    ),
    "guides/voice.md": (
        "Discord Voice Guide for Lua",
        "Build Discord voice bots in Lua with discord.lua, including voice connections, audio playback, recording, FFmpeg, Opus, libsodium, and libdave.",
    ),
    "guides/sharding.md": (
        "Discord Gateway Sharding in Lua",
        "Scale Lua Discord bots with automatic gateway sharding in discord.lua and configure shard counts, IDs, and connection behavior.",
    ),
    "guides/errors-checks-and-cooldowns.md": (
        "Discord Command Errors, Checks, and Cooldowns in Lua",
        "Add checks, cooldowns, and structured command error handling to Lua Discord bots built with discord.lua.",
    ),
    "guides/extensions-cogs-and-tasks.md": (
        "Discord Bot Extensions, Cogs, and Tasks in Lua",
        "Organize larger Lua Discord bots with discord.lua extensions, cogs, reusable modules, and scheduled background tasks.",
    ),
    "api/bot.md": (
        "Bot API Reference",
        "API reference for the discord.lua Bot class, including lifecycle, events, commands, interactions, extensions, presence, and helper methods.",
    ),
    "api/client-and-gateway.md": (
        "Discord Client and Gateway API Reference",
        "API reference for discord.lua client and Discord Gateway behavior, including sessions, events, connection state, and gateway data.",
    ),
    "api/command-api.md": (
        "Command API Reference",
        "API reference for prefix, slash, context-menu, group, hybrid, and autocomplete command interfaces in discord.lua.",
    ),
    "api/interaction-contexts.md": (
        "Interaction Context API Reference",
        "API reference for discord.lua interaction contexts, responses, arguments, defer/edit flows, autocomplete, and component interactions.",
    ),
    "api/ui-components.md": (
        "Discord UI Components API Reference",
        "API reference for discord.lua buttons, selects, views, modals, thumbnails, sections, media galleries, and Components v2 types.",
    ),
    "api/messages-and-channels.md": (
        "Messages and Channels API Reference",
        "API reference for Discord messages, channels, replies, edits, attachments, and channel operations in discord.lua.",
    ),
    "api/guilds-members-users-roles.md": (
        "Guilds, Members, Users, and Roles API Reference",
        "API reference for Discord guilds, members, users, roles, permissions, and related models in discord.lua.",
    ),
    "api/embeds-assets-and-mentions.md": (
        "Embeds, Assets, and Mentions API Reference",
        "API reference for discord.lua embeds, assets, colors, emojis, mentions, attachments, and message presentation helpers.",
    ),
    "api/additional-models.md": (
        "Additional Discord Models API Reference",
        "API reference for additional Discord models exposed by discord.lua, including activities, stickers, invites, webhooks, and related objects.",
    ),
    "api/voice.md": (
        "Discord Voice API Reference",
        "API reference for discord.lua voice connections, playback, recording, audio sources, native dependencies, and voice-state handling.",
    ),
    "api/enums-errors-and-utilities.md": (
        "Enums, Errors, and Utilities API Reference",
        "API reference for discord.lua enums, error types, flags, permissions, utility helpers, and shared constants.",
    ),
    "api/rate-limits.md": (
        "Discord Rate Limits API Reference",
        "API reference for discord.lua REST rate-limit handling, buckets, retry behavior, and request coordination.",
    ),
    "examples/basic-bot.md": (
        "Basic Discord Bot Example in Lua",
        "A minimal Discord bot example in Lua using discord.lua and Luvit, with connection setup, events, and a simple command.",
    ),
    "examples/commands.md": (
        "Discord Command Examples in Lua",
        "Practical Lua examples for prefix commands, slash commands, arguments, groups, and command responses with discord.lua.",
    ),
    "examples/interactions.md": (
        "Discord Interaction Examples in Lua",
        "Practical Lua examples for Discord interactions, buttons, selects, modals, responses, and follow-ups with discord.lua.",
    ),
    "examples/voice.md": (
        "Discord Voice Bot Example in Lua",
        "A practical Discord voice bot example in Lua using discord.lua for joining voice, playing audio, and handling voice connections.",
    ),
}

_PAGES: list[tuple[str, str]] = []


def _site_url(config, page) -> str:
    return urljoin(config.site_url.rstrip("/") + "/", page.url)


def _jsonld(page, config, title: str, description: str) -> str:
    url = _site_url(config, page)
    graph: list[dict] = [
        {
            "@type": "WebPage" if page.file.src_uri != "index.md" else "WebSite",
            "@id": url,
            "url": url,
            "name": title,
            "description": description,
            "inLanguage": "en",
        }
    ]

    if page.file.src_uri == "index.md":
        graph.append(
            {
                "@type": "SoftwareSourceCode",
                "name": "discord.lua",
                "description": description,
                "url": url,
                "codeRepository": "https://github.com/filispeen/discord.lua",
                "programmingLanguage": "Lua",
                "runtimePlatform": "Luvit",
                "license": "https://github.com/filispeen/discord.lua/blob/master/LICENSE",
            }
        )
    else:
        graph.append(
            {
                "@type": "BreadcrumbList",
                "itemListElement": [
                    {
                        "@type": "ListItem",
                        "position": 1,
                        "name": "discord.lua",
                        "item": config.site_url,
                    },
                    {
                        "@type": "ListItem",
                        "position": 2,
                        "name": title,
                        "item": url,
                    },
                ],
            }
        )
        graph.append(
            {
                "@type": "TechArticle",
                "headline": title,
                "description": description,
                "url": url,
                "isPartOf": {"@id": config.site_url},
                "inLanguage": "en",
            }
        )

    return json.dumps({"@context": "https://schema.org", "@graph": graph}, ensure_ascii=False)


def on_page_context(context, page, config, nav):
    title, description = SEO.get(
        page.file.src_uri,
        (page.title, config.site_description),
    )
    page.meta["title"] = title
    page.meta["description"] = description
    page.meta["seo_jsonld"] = _jsonld(page, config, title, description)
    _PAGES.append((page.url, page.file.src_uri))
    return context


def _git_lastmod(src_uri: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", "log", "-1", "--format=%cs", "--", f"docs/{src_uri}"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    value = result.stdout.strip()
    return value or None


def on_post_build(config):
    sitemap = Path(config.site_dir) / "sitemap.xml"
    if not sitemap.exists():
        return

    namespace = "http://www.sitemaps.org/schemas/sitemap/0.9"
    ET.register_namespace("", namespace)
    tree = ET.parse(sitemap)
    root = tree.getroot()
    lastmods = {urljoin(config.site_url.rstrip("/") + "/", url): _git_lastmod(src) for url, src in _PAGES}

    for entry in root.findall(f"{{{namespace}}}url"):
        loc = entry.find(f"{{{namespace}}}loc")
        lastmod = entry.find(f"{{{namespace}}}lastmod")
        if loc is None or lastmod is None or not loc.text:
            continue
        value = lastmods.get(loc.text)
        if value:
            lastmod.text = value

    tree.write(sitemap, encoding="utf-8", xml_declaration=True)
    with sitemap.open("rb") as source, gzip.open(str(sitemap) + ".gz", "wb") as target:
        target.write(source.read())
