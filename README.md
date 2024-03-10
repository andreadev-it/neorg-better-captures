# Better captures for Neorg
This [Neorg](https://github.com/nvim-neorg/neorg) plugin adds a way to quickly create new files that
follow a specific structure. You can set a variable path
and a text that will be automatically inserted.

It also allows you to save the captured text inside 
of an existing file, either at the top or bottom, or 
(in the future) under a specific heading.

## Table of contents
- [Installation](#installation)
- [Settings](#settings)
- [Capture definition](#capture-definition)
- [Placeholders](#placeholders)
- [Examples](#examples)
- [Known issues](#known-issues)
- [Next steps](#next-steps)

# Installation
In the Neorg install configuration, add this plugin as
a dependency and set up the configuration table to include
the configuration for `external.better-captures`. The following
code shows how to set it up on [Lazy.nvim](https://github.com/folke/lazy.nvim):

``` lua
{ -- Neorg config
  'nvim-neorg/neorg',
  -- ...
  opts = {
    load = {
      -- ...
      ['external.better-captures'] = {
        config = {
          captures = {
            ["my_capture"] = {
              -- capture definition (see below)
            }
          }
        }
      }
    }
  },
  dependencies = {
    -- ...
    'andreadev-it/neorg-better-captures'
  }
}
```

# Settings
This plugin accept the following settings:
|Field|Type|Description|
|-----|----|-----------|
|`auto_switch`|boolean|Automatically switch workspace if a capture that is being executed requires a specific one (default: `false`)|
|`use_luasnip`|boolean|Whether to use luasnip if available or not (default: `true`)|
|`captures`|table<string, Capture>|This is the table that will contain all your custom captures. It's a table that relates the name with the capture definition.|

## Capture definition
Each capture can have different fields to customize how
it works:
|Field|Type|Description|
|-----|----|-----------|
|`path`|string / function|*(required)* The location of the file in which the captured text will be appended. It might be a new file if the capture type is "file", or an existing one if the type is set to "text". In the second option, the text will be appended at a specific position in the file. The path will always be relative to the workspace root. You can pass either a string, or a function that will return a string.|
|`content`|string / function|*(either this or `snippet` are required)* The content to insert into the file. You can use some placeholder strings that will be substituted when the capture gets executed, or pass a function that generates the text. Moreover, this string will be passed to Luasnip, and every `{}` will become a jumping point (a place where you can move to by just pressing Tab).
|`use_luasnip`|boolean|Wether to use luasnip if available or not. If not set, it will default to the module configuration value, which itself defaults to `true`.
|`snippet`|Luasnip snippet|A snippet that will be inserted instead of the `content`. This is here just to allow even further customization.
|`workspace`|string|The workspace required for this capture to work. This is an optional field. When it is set, and the `auto_switch` option is turned off, an error message will appear if you are not inside the correct workspace. If the `auto_switch` option is turned on, you will be automatically switched to the workspace defined here. By default, no workspace is required.
|`type`|"file" / "text"|This indicates what kind of capture you're creating. The type "file" means that you want to create a new file. The type "text" means that you want to insert a text within an already existing file (which path is defined in the `path` field). It will default to "file".
|`target`|string / function|*Currently unused*. It will specify under which heading you want your text to go. It will be defined as a norg heading, with the ability to also use the `#` character. If no target is passed, then the text will be appended either at the top or at the bottom of the file
|`insert_position`|"top" / "bottom"|It indicates wether you want your text capture to be placed at the top of the file/heading, or at the bottom. It defaults to "bottom".

## Placeholders
|Placeholder|Substitution|
|-----------|------------|
|`{name}`|The user name (taken from the `$USER` variable)|
|`{date}`|The date expressed based on your current locale (something like mm/dd/yyyy). It comes from `vim.fn.strftime('%D')`|
|`{datetime}`|The date and time expressed based on your current locale. It comes from `vim.fn.strftime('%c')`|
|`{isodate}`|The date expressed in ISO format|
|`{isodatetime}`|The date and time expressed in ISO format|
# Examples
Here you can find some examples of capture configurations.

## Diary
Here an example of how you might use this plugin to quickly capture
a diary entry (probably useless, since there already is a journal
functionality in Neorg, but at least it gives you an idea)

```lua
{
  path = 'diary/{isodate}.norg',
  content = [[
  @document.meta
  title: Diary for {datetime}
  author: John Smith
  created: {isodatetime}
  updated: {isodatetime}
  @end

  * What happened today
  {}

  * Things I want to do tomorrow
  {}
  ]],
  workspace = 'diary'
}
```

## Project creation
This might be useful in some sort of GTD-like workflow.
Be aware that the `text` type captures are not supported yet.

```lua
{
  path = 'gtd/projects.norg',
  type = 'text'
  content = [[
  * {}
  - ( ) {}
  ]],
  workspace = 'work'
}
```

## Zettelkasten
Here an example that might give you an idea of how this can be used
for building a zettelkasten-like experience:
```lua
function id_from_datetime()
  return vim.fn.strftime('%Y%m%d%H%M%S')
end
-- ...
{
  path = function()
    return 'notes/' .. id_from_datetime() .. '.norg'
  end,
  content = function()
    return [[
    @document.meta
    title: {}
    authors: John Smith
    id: ]] .. id_from_datetime() .. [[
    created: {isodatetime}
    updated: {isodatetime}
    @end
    
    ]]
  end,
  workspace = "zettelkasten"
}
```

# Known issues
## Neovim hangs on text capture when the same file is opened
This situation would require that you have a capture of type "file"
and you execute it while having the file in the "target" field already
opened and in the same buffer. In such a situation, you could see neovim
just hanging completely.

To solve this issue, simply update neovim. It looks like it was an
issue up to version 0.9.4. See [this issue](https://github.com/nvim-neorg/neorg/issues/1258)
for more info.

# Next steps
- [x] Avoid always having to use Luasnip
- [x] Enable the `text` type captures for whole files
- [ ] Enable the `target` field for capturing under specific headings
- [ ] Allow custom placeholders by passing a `data` field for each capture, or maybe even for the whole plugin
