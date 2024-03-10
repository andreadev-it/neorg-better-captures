local neorg = require('neorg.core')
local log = neorg.log
local module = neorg.modules.create('external.better-captures')
local luasnip = require('luasnip')
local luasnip_fmt = require('luasnip.extras.fmt')

---@alias CaptureType "file" | "text"
---@alias InsertPosition "top" | "bottom"

---@class Capture
---@field path string | function The name and path of the file, or a function that returns it
---@field content string | function The content of the file, that will be passed to luasnip
---@field snippet any A luasnip snippet to execute once the file is created
---@field workspace string | nil An optional workspace in which to enable the capture
---@field type CaptureType Either create a new file or append the text to an existing one
---@field target string The linkable onto which the text will be appended (if type is "text")
---@field insert_position InsertPosition Decides wether to insert at the top or at the bottom of the target 

module.setup = function ()
    return {
        requires = {
            'core.neorgcmd',
            'core.dirman'
        }
    }
end


module.load = function ()
    -- Get all configured capture names
    local capture_names = {}
    for k, _ in pairs(module.config.public.captures) do
        table.insert(capture_names, k)
    end

    -- Add them to the autocompletion for the command
    module.required['core.neorgcmd'].add_commands_from_table({
        capture = {
            args = 1,
            name = 'external.better-captures.start_capture',
            complete = { capture_names }
        }
    })
end

module.public = {
    ---@param name string The name of the capture to execute
    start_capture = function (name)
        local capture = module.private.get_capture_by_name(name)
        if capture == nil then
            return
        end

        local cur_workspace = module.required['core.dirman'].get_current_workspace()[1]

        if capture.workspace ~= nil and module.config.public.auto_switch then
            local success = module.required['core.dirman'].set_workspace(capture.workspace)
            if not success then
                return
            end

            cur_workspace = capture.workspace
        end

        if capture.workspace ~= nil and capture.workspace ~= cur_workspace then
            log.error("Cannot execute this capture outside of the workspace: " .. capture.workspace)
            return
        end

        -- either get the value or execute the function and
        -- save the result
        local path = module.private.get_or_execute(capture.path)
        path = module.private.replace_placeholders(path)

        module.required['core.dirman'].create_file(path)

        local pos = 0

        -- If it is a text capture, add the necessary line and
        -- set the cursor position accordingly
        if capture.type == "text" then
            local pos_map = {
                top = 0,
                bottom = vim.api.nvim_buf_line_count(0) -- Get the total number of line, which is the last line
            }

            pos = pos_map[capture.insert_position]

            vim.api.nvim_buf_set_lines(
                0,
                pos,
                pos,
                false,
                { "" }
            )

            vim.api.nvim_win_set_cursor(0, { pos + 1, 0 })
        end

        local snippet = module.private.snippet_from_capture(capture)

        luasnip.snip_expand(snippet, { pos = { pos, 0 } })
    end,
}

module.private = {
    ---Get all captures related to a specific workspace, or all
    ---the generic ones
    ---@param name string The workspace name
    ---@return Capture[]
    get_captures_by_workspace = function (name)
        local captures = {}
        for cap_name, capture in pairs(module.config.public.captures) do
            if capture.workspace == name or capture.workspace == nil then
                captures[cap_name] = module.private.fill_capture_defaults(capture)
            end
        end

        return captures
    end,

    ---Get a capture by name, initializing all necessary fields
    ---@param name string
    ---@return Capture | nil
    get_capture_by_name = function (name)
        local capture = module.config.public.captures[name]
        if capture == nil then
            log.error("No capture called '" .. name .. "' found.")
            return
        end

        return module.private.fill_capture_defaults(capture)
    end,

    ---If the value is a function, execute it and return the result,
    ---otherwise just return the value.
    ---@param value any
    ---@return any
    get_or_execute = function (value)
        if type(value) == 'function' then
            return value()
        end

        return value
    end,

    ---Replace all placeholders in the string with the corresponding values.
    ---@param str string
    replace_placeholders = function (str)
        -- generic
        str = str:gsub('{name}', vim.fn.expand("$USER"))
        -- date and time
        str = str:gsub('{date}', vim.fn.strftime('%D'))
        str = str:gsub('{datetime}', vim.fn.strftime('%c'))
        str = str:gsub('{isodate}', vim.fn.strftime('%F'))
        str = str:gsub('{isodatetime}', vim.fn.strftime('%FT%T%z'))

        return str
    end,

    ---Get the snippet from the capture
    ---@param capture Capture
    ---@return any
    snippet_from_capture = function (capture)
        if capture.snippet ~= nil then
            return capture.snippet
        else
            local content = module.private.replace_placeholders(
                module.private.get_or_execute(capture.content)
            )
            return module.private.snippet_from_content(content)
        end
    end,

    ---Get a luasnip snippet from the capture content.
    ---This means adding the necessary nodes for inserting text.
    ---@param content any
    snippet_from_content = function (content)
        local insert = luasnip.insert_node
        local fmt = luasnip_fmt.fmt
        local i = 1
        local nodes = {}
        for _ in content:gmatch('{}') do
            table.insert(nodes, insert(i))
            i = i + 1
        end

        return luasnip.snippet('_', fmt(content, nodes))
    end,

    ---Fills a capture default fields if not initialized.
    ---It will return a new table.
    ---@param capture Capture
    ---@return Capture | nil
    fill_capture_defaults = function (capture)
        ---@type Capture
        local w_defaults = {}

        if capture.path == nil then
            log.error("Every capture requires a path.")
            return
        end
        w_defaults.path = capture.path

        if capture.content == nil and capture.snippet == nil then
            log.error("Every capture requires either a content or a snippet field.")
            return
        end
        w_defaults.content = capture.content
        w_defaults.snippet = capture.snippet

        w_defaults.workspace = capture.workspace -- default: nil
        w_defaults.type = capture.type or "file" -- default: new norg file
        w_defaults.target = capture.target -- default: nil
        w_defaults.insert_position = capture.insert_position or "bottom" --default: insert at the bottom of the file

        return w_defaults
    end,

    ---Split a string into lines
    ---@param str string
    ---@return table<string>
    split_lines = function (str)
        local result = {}
        for line in str:gmatch '[^\n]+' do
            table.insert(result, line)
        end
        return result
    end
}


module.on_event = function (event)
    if event.split_type[2] == 'external.better-captures.start_capture' then
        module.public.start_capture(event.content[1])
    end
end


module.config.public = {
    -- Automatically switch workspace when a capture gets
    -- executed outside of the workspace it requires.
    ---@type boolean
    auto_switch = false,

    -- The table of captures. The key is the name and the
    -- value is the capture details
    ---@type table<string, Capture>
    captures = {}
}


module.events.subscribed = {
    ['core.neorgcmd'] = {
        ['external.better-captures.start_capture'] = true
    }
}

return module
