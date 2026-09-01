# UI components

UI modules are currently loaded from `discord.lua/lib/ui/...`; they are not all re-exported from `require("discord.lua")`.

## `View`

### `View.new([opts])`

Creates a view. `opts.timeout` is a timeout in milliseconds.

### `view:add(item)` / `view:remove(item_or_custom_id)` / `view:clear()`

Manage view items and return the view.

### `view:find_item(custom_id)`

Returns an item with the matching custom ID, or `nil`.

### `view:timeout(milliseconds)` / `view:stop()`

Sets the timeout or stops the view. Stopped views are not searched by the Bot dispatcher.

### `view:to_components()`

Returns an array suitable for an interaction response's `components` option.

## Standard items

| Module | Constructor | Payload method |
|---|---|---|
| `ui/button` | `Button.new(opts)` | `to_component()` |
| `ui/select` | `Select.new(opts)` | `add_option`, `to_component()` |
| `ui/input_text` | `InputText.new(opts)` | `refresh_state`, `to_component()` |
| `ui/modal` | `Modal.new(opts)` | `add_item`, `to_component`, `stop` |
| `ui/action_row` | `ActionRow.new(opts)` | `add_item`, `remove`, `get_item`, `to_component` |

`Button` and other interactive items may have `custom_id` and `callback` in their options. The dispatcher invokes the item's callback when it finds a matching active view item.

## Components v2 and form helpers

The repository also implements `Container`, `Section`, `TextDisplay`, `MediaGallery`, `Separator`, `Thumbnail`, `Label`, `FileUpload`, `Checkbox`, `CheckboxGroup`, and `RadioGroup`. Each constructor takes an options table unless noted otherwise; each has `to_component()`. Groups support option management and state refresh methods shown in their respective modules.

Use this API for messages and modal payload construction only after checking Discord component compatibility. Library-side constructors serialize values but do not replace Discord's server validation.
