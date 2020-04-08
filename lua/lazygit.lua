local api = vim.api
local fn = vim.fn

local file_buffer = nil
local border_buffer = nil
local file_window = nil
local border_window = nil
local previous_file_buffer = nil

local OPTIONS = {
    lazygit_floating_window_scaling_factor = 0.9,
    lazygit_floating_window_winblend = 0,
}

local function execute(cmd, ...)
  cmd = cmd:format(...)
  vim.cmd(cmd)
end

local function is_lazygit_available()
    return fn.executable("lazygit") == 1
end

local function project_root_dir()
    return fn.system('cd ' .. fn.fnamemodify(fn.resolve(fn.expand('%:p')), ':h') .. ' && git rev-parse --show-toplevel 2> /dev/null')
end

local function exec_lazygit_command(root_dir)
    local cmd = "lazygit " .. "-p " .. root_dir
    -- ensure that the buffer is closed on exit
    execute([[
        call termopen('%s', {'on_exit': {job_id, code, event-> luaeval("require('lazygit').on_exit(" . job_id . "," . code . "," . event . ")")}})
    ]], cmd)
    vim.cmd "startinsert"
end

local function open_floating_window()
    previous_file_buffer = fn.bufnr('%')
    -- create a unlisted scratch buffer
    file_buffer = api.nvim_create_buf(false, true)
    -- create a unlisted scratch buffer for the border
    border_buffer = api.nvim_create_buf(false, true)

    vim.bo[file_buffer].bufhidden = 'wipe'
    vim.bo[file_buffer].filetype = 'lazygit'

    local height = math.ceil(vim.o.lines * OPTIONS.lazygit_floating_window_scaling_factor) - 1
    local width = math.ceil(vim.o.columns * OPTIONS.lazygit_floating_window_scaling_factor)

    local row = math.ceil(vim.o.lines - height) / 2
    local col = math.ceil(vim.o.columns - width) / 2

    local border_opts = {
        style = "minimal",
        relative = "editor",
        row = row - 1,
        col = col - 1,
        width = width + 2,
        height = height + 2,
    }

    local opts = {
        style = "minimal",
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
    }

    local border_lines = {'╭' .. string.rep('─', width) .. '╮'}
    local middle_line = '│' .. string.rep(' ', width) .. '│'
    for i = 1, height do
        table.insert(border_lines, middle_line)
    end
    table.insert(border_lines, '╰' .. string.rep('─', width) .. '╯')
    -- set border_lines in the border buffer from start 0 to end -1 and strict_indexing false
    api.nvim_buf_set_lines(border_buffer, 0, -1, false, border_lines)

    border_window = api.nvim_open_win(border_buffer, true, border_opts)
    vim.cmd 'set winhl=Normal:Floating'
    file_window = api.nvim_open_win(file_buffer, true, opts)

    vim.cmd('set winblend=' .. OPTIONS.lazygit_floating_window_winblend)

    -- use autocommand to ensure that the border_buffer closes at the same time as the main buffer
    vim.cmd('autocmd BufWipeout <buffer> silent! execute "silent bwipeout!"' .. border_buffer)
end

local function on_exit(job_id, code, event)
    if code == 0 then
        -- delete terminal buffer
        vim.cmd("silent! bwipeout! " .. file_buffer)
        file_buffer = nil
        border_buffer = nil
        file_window = nil
        border_window = nil
    end
end

local function lazygit()
    if is_lazygit_available() ~= true then
        print("Please install lazygit. Check documentation for more information")
        return
    end
    -- TODO: ensure that it is a valid git directory
    local root_dir = project_root_dir()
    open_floating_window()
    exec_lazygit_command(root_dir)
end

local function setup()
    OPTIONS.lazygit_floating_window_winblend = api.nvim_get_var("lazygit_floating_window_winblend")
    -- api.nvim_get_var("lazygit_floating_window_scaling_factor") returns a table, with keys true and false.
    -- the value in corresponding to the false key appears to be what we want.
    OPTIONS.lazygit_floating_window_scaling_factor = api.nvim_get_var("lazygit_floating_window_scaling_factor")[false]
end

local function lazygitconfig()
    local os = fn.substitute(fn.system('uname'), '\n', '', '')
    local config_file = ""
    if os == "Darwin" then
        config_file = "~/Library/Application Support/jesseduffield/lazygit/config.yml"
    else
        config_file = "~/.config/jesseduffield/lazygit/config.yml"
    end
    if fn.empty(fn.glob(config_file)) then
        -- file does not exist
        -- check if user wants to create it
        local answer = fn.confirm("File " .. config_file .. " does not exist.\nDo you want to create the file and populate it with the default configuration?", "&Yes\n&No")
        if answer == 2 then
            return nil
        end
        if fn.isdirectory(fn.fnamemodify(config_file, ":h")) == false then
            -- directory does not exist
            fn.mkdir(fn.fnamemodify(config_file, ":h"))
        end
        vim.cmd("edit " .. config_file)
        vim.cmd([[execute "silent! 0read !lazygit -c"]])
        vim.cmd([[execute "normal 1G"]])
    else
        vim.cmd("edit " .. config_file)
    end
end

return {
    setup = setup,
    lazygit = lazygit,
    lazygitconfig = lazygitconfig,
    on_exit = on_exit,
    on_buf_leave = on_buf_leave,
}
