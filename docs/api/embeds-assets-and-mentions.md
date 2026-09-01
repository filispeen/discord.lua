# Embeds, assets, and mentions

## `Embed`

### `Embed.new([data])` / `Embed.create()`

Create an embed. `data` can include `title`, `url`, `description`, `color`, `timestamp`, `footer`, `image`, `thumbnail`, `author`, and `fields`.

### Builder methods

| Method | Return |
|---|---|
| `with_author(name[, url, icon_url, color])` | embed |
| `with_thumbnail(url[, color])` | embed |
| `with_image(url[, color])` | embed |
| `with_video(url[, color])` | embed |
| `with_provider(name[, url, image_url, color])` | embed |
| `with_footer(text[, icon_url, color])` | embed |
| `with_timestamp()` | embed |
| `with_field(name, value[, inline])` | embed |
| `with_fields(fields)` | embed |
| `with_color(color)` | embed |
| `title(title[, url, color])` | embed |
| `description(text[, color])` | embed |

`to_json()` encodes the embed table. `color` may be a number or a `Colour` object with a `value` field.

!!! note
    `title` and `description` are both methods and instance data fields. Call a builder before assigning the same named field directly.

## `Colour` / `Color`

The package exports both spellings for the same class.

### `Colour.new(value)`

Creates a colour from an integer between `0` and `0xFFFFFF`; raises outside that range.

### `Colour.from_rgb(r, g, b)` / `Colour.from_hex(value)`

Create a colour from byte RGB values or exactly six hexadecimal digits. Named methods such as `green`, `blue`, `purple`, and `default` return preset values.

## Other exported helpers

`Asset`, `PartialEmoji`, `AllowedMentions`, and `Flags` are package exports. They model payload portions used by messages and embeds. `AllowedMentions` should be converted with `to_dict()` when used in a raw payload; `Message` does this conversion automatically for an object supplied as `allowed_mentions`.

For uploads, use `File.new(path[, opts])` or `File.from_bytes(data, name[, opts])` from `discord.lua/lib/models/file`. Upload files provide `attachment(index)` for multipart message payloads; they are distinct from `discord.ui.File`, which serializes a Components v2 file display item.
