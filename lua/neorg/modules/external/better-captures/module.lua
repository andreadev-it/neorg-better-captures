local neorg = require('neorg.core')
local log = neorg.log
local module = neorg.modules.create('external.better-captures')
local luasnip_ok, luasnip = pcall(require, 'luasnip')
local _, luasnip_fmt = pcall(require, 'luasnip.extras.fmt') -- If luasnip is ok, then this will be too

---@alias CaptureType "file" | "text"
---@alias InsertPosition "top" | "bottom"
---@alias ComputableString string | function
---@alias ComputableTable table | function
---@alias LineRange { [1]: number, [2]: number }
---@alias Headline { [1]: LineRange, [2]: string } 

---@class Capture
---@field path ComputableString The name and path of the file, or a function that returns it
---@field content ComputableString The content of the file, that will be passed to luasnip
---@field use_luasnip boolean Whether to use luasnip for the content
---@field snippet any A luasnip snippet to execute once the file is created
---@field workspace string? An optional workspace in which to enable the capture
---@field type CaptureType Either create a new file or append the text to an existing one
---@field target ComputableString The linkable onto which the text will be appended (if type is "text")
---@field insert_position InsertPosition Decides wether to insert at the top or at the bottom of the target 
---@field data ComputableTable A custom set of text replacements

module.setup = function ()
    return {
        requires = {
            'core.neorgcmd',
            'core.dirman',
            'core.queries.native'
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
        path = module.private.replace_placeholders(
            path,
            module.private.get_placeholders(capture)
        )

        module.required['core.dirman'].create_file(path)

        local pos = 0

        -- If it is a text capture, add the necessary line and
        -- set the cursor position accordingly
        if capture.type == "text" then
            local pos_map = {
                top = 0,
                bottom = vim.api.nvim_buf_line_count(0) -- Get the total number of line, which is the last line
            }

            local headlines = module.private.get_buffer_headlines(0)

            if capture.target ~= nil then
                -- TODO
            end

            pos = pos_map[capture.insert_position]

            -- If the capture is using luasnip, and the
            -- capture is of type "text", we should prepare
            -- the line for the snippet expansion
            if capture.use_luasnip then
                vim.api.nvim_buf_set_lines(
                    0,
                    pos,
                    pos,
                    false,
                    { "" }
                )
            end
        end

        if capture.use_luasnip then
            local snippet = module.private.snippet_from_capture(capture)

            luasnip.snip_expand(snippet, { pos = { pos, 0 } })
        else
            -- Replace the placeholders, and then splits
            -- the text into lines for the neovim api
            local lines = vim.split(
                module.private.replace_placeholders(
                    module.private.get_or_execute(capture.content),
                    module.private.get_placeholders(capture)
                ),
                '\n'
            )

            vim.api.nvim_buf_set_lines(
                0,
                pos,
                pos,
                false,
                lines
            )
        end
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

    ---Get all the replacement strings
    ---@param capture Capture
    ---@return table<string, string>
    get_placeholders = function (capture)
        -- Get the username from the OS
        local username = os.getenv("USER") or
            os.getenv("username") or
            "Could not get your username"

        local placeholders = {
            -- generic
            name = username,
            -- date and time
            date = vim.fn.strftime('%D'),
            datetime = vim.fn.strftime('%c'),
            isodate = vim.fn.strftime('%F'),
            isodatetime = vim.fn.strftime('%FT%T%z')
        }

        return vim.tbl_extend(
            "force",
            placeholders,
            module.private.get_or_execute(capture.data)
        )
    end,

    ---Replace all placeholders in the string with the corresponding values.
    ---@param str string
    ---@return string
    replace_placeholders = function (str, placeholders)
        for name, value in pairs(placeholders) do
            str = str:gsub('{' .. name .. '}', value)
        end

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
                module.private.get_or_execute(capture.content),
                module.private.get_placeholders(capture)
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
        w_defaults.use_luasnip = module.private.should_use_luasnip(capture)
        w_defaults.snippet = capture.snippet

        w_defaults.workspace = capture.workspace -- default: nil
        w_defaults.type = capture.type or "file" -- default: new norg file
        w_defaults.target = capture.target -- default: nil
        w_defaults.insert_position = capture.insert_position or "bottom" --default: insert at the bottom of the file
        w_defaults.data = capture.data or {}

        return w_defaults
    end,

    ---Returns wether or not to use luasnip for a specific capture.
    ---Checks for the capture preferences, the module configuration
    ---and also looks to check if luasnip is installed or not
    ---@param capture Capture
    ---@return boolean
    should_use_luasnip = function (capture)
        -- If luasnip is not installed, just do plain text
        if not luasnip_ok then
            return false
        end

        if capture.use_luasnip ~= nil then
            return capture.use_luasnip
        end

        return module.config.public.use_luasnip
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
    end,

    ---Get all headlines from the current buffer
    ---comment
    ---@return table<Headline>
    get_buffer_headlines = function (buf)
        ---@type table<Headline> A table of line numbers related to a heading
        local headlines = {}

        local tree = {
            {
                query = { "first", "document_content" },
                subtree = {
                    {
                        query = { "all", "heading1"}
                    },
                    {
                        query = { "all", "heading2"}
                    },
                    {
                        query = { "all", "heading3"}
                    },
                    {
                        query = { "all", "heading4"}
                    },
                    {
                        query = { "all", "heading5"}
                    },
                    {
                        query = { "all", "heading6"}
                    },
                }
            }
        }

        local nodes_w_buf = module.required['core.queries.native'].query_nodes_from_buf(tree, 0)
        vim.print(nodes_w_buf)

        for i, node_details in ipairs(nodes_w_buf) do
            local node = node_details[1]

            local node_start = node:start()[1]
            local node_end = node:end_()[1]
            local ending = vim.api.nvim_buf_get_lines(buf, node_end, node_end + 1, true)
            local title = vim.api.nvim_buf_get_lines(buf, node_start, node_start + 1, true)

            if ending[1]:find("^%s*%-%-%-") then
                node_end = node_end - 1
            end

            table.insert(headlines, { { node_start, node_end }, title })
        end

        vim.print(headlines)

        return headlines
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

    -- Whether to use luasnip for the captures or not
    use_luasnip = true,

    -- The table of captures. The key is the name and the
    -- value is the capture details
    ---@type table<string, Capture>
    captures = {},
}


module.events.subscribed = {
    ['core.neorgcmd'] = {
        ['external.better-captures.start_capture'] = true
    }
}

return module
