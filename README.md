# ET.nvim

> Human-First Neovim AI Agent — a stateless tool-calling agent with vimdiff review.

Designed for [oMLX](https://github.com/jundot/omlx) and any OpenAI-compatible endpoint.

---

## Features

- **Stateless agent** — fresh context per invocation, no stale conversations
- **Agent Tool-calling loop** — `find_files`, `read_file`, `edit_file`, `web_fetch`, `done`
- **Vimdiff review** — inspect every change side-by-side before it's written to disk
- **Brave Search** — web, news, images, videos with result trees
- **Context7** — library documentation lookup with dual-panel UI
- **Per-project System Prompt** — persistent system prompt additions scoped to working directory
- **Vim motion** — `:w<CR>` to submit, `q` to close, `h/l` to switch tabs, `<C-w>h/j/k/l` to focus between components

---

## Requirements

| Type | Dependency | Purpose |
|------|-----------|---------|
| Neovim | >= 0.9 | Lua APIs, floating windows |
| Plugin | [nui.nvim](https://github.com/MunifTanjim/nui.nvim) | Popup, Menu, Input, Layout, Tree |
| Plugin | [fzf-lua](https://github.com/ibhagwan/fzf-lua) | File picker (`:ETFilePicker`) |
| External | `bx` | Brave Search CLI |
| External | `ctx7` | Context7 documentation CLI |
| External | `lynx` | HTML-to-text for web_fetch (optional on Windows) |
| External | `jq` | JSON filtering for Brave Search results |
| External | `fixjson` | JSON formatting for config |

Run `:ETInstallTools` to install all external tools in one command.

---

## Installation

### lazy.nvim

```lua
{
  'user/ET.nvim',
  dependencies = {
    'MunifTanjim/nui.nvim',
    'ibhagwan/fzf-lua',
  },
  opts = {
    -- All fields optional — omit to configure later via :ETEditSettings
    endpoint = 'http://localhost:8000/v1',
    model = 'llama3',          -- omit to auto-pick first available model
    -- api_key = 'sk-...',      -- or set $ET_API_KEY
  },
}
```

With custom keymaps:

```lua
{
  'user/ET.nvim',
  dependencies = {
    'MunifTanjim/nui.nvim',
    'ibhagwan/fzf-lua',
  },
  keys = {
    { '<leader>ea', ':ET<CR>',             desc = 'ET Chat' },
    { '<leader>eb', ':ETBraveSearch<CR>',  desc = 'ET Brave Search' },
    { '<leader>ec', ':ETContext7<CR>',     desc = 'ET Context7' },
    { '<leader>er', ':ETWebFetchResults<CR>', desc = 'ET Web Fetch Results' },
  },
  opts = { endpoint = 'http://localhost:8000/v1' },
}
```

Or explicit `config` function:

```lua
{
  'user/ET.nvim',
  dependencies = { 'MunifTanjim/nui.nvim', 'ibhagwan/fzf-lua' },
  config = function()
    require('ET').setup({
      endpoint = 'http://localhost:8000/v1',
      api_key = 'sk-...',
    })
  end,
}
```

### Config options

All fields passed via `opts` or `setup({...})` are deep-merged into the
config file (`~/.config/nvim/.et/config.json`) and can be changed later
with `:ETEditSettings`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `endpoint` | string | `http://localhost:8000/v1` | OpenAI-compatible API base URL |
| `api_key` | string | `""` | API key (Bearer token). Falls back to `$ET_API_KEY`. |
| `model` | string | auto | Model ID — omit to auto-pick first available |
| `system_prompt` | string | tools-only prompt | Custom system prompt |
| `sampling_params` | table | `{}` | Pass-through to `/chat/completions` |

`sampling_params` supports all standard fields:

```lua
sampling_params = {
  temperature = 0.7,
  max_tokens = 4096,
  top_p = 0.9,
  -- top_k, repetition_penalty, presence_penalty, etc.
  chat_template_kwargs = {
    enable_thinking = true,
    -- reasoning_effort = 'medium',
  },
}
```

Any field set to `nil` is omitted from the API request (falls back to the
server's defaults).

---

## First Run

1. `:ETEditSettings` — review or edit the endpoint and API key
2. `:ETSwitchModel` — pick a model from the available list
3. `:ET` — open the chat popup, type a prompt, press `:w<CR>` to send

On first load, ET.nvim checks that `bx`, `ctx7`, `jq`, and `lynx` are
installed. If any are missing, a notification shows with instructions
to run `:ETInstallTools`.

---

## Commands

| Command | Description |
|---------|-------------|
| `:ET [range]` | Open chat popup. Visual range pre-fills the selection with file path and line anchor. `:w<CR>` to send. |
| `:ETSwitchModel` | Menu to pick from available models on the configured endpoint |
| `:ETEditSettings` | Edit `config.json` in a popup. `:w<CR>` to save. |
| `:ETFilePicker` | fzf-lua file picker. Selected paths are inserted into the current buffer. |
| `:ETBraveSearch` | Brave Search UI — type selector (web/news/images/videos), query input, result tree |
| `:ETContext7` | Context7 dual-panel — search libraries on the left, query docs on the right |
| `:ETContext7AddToDocs` | Copy selected library result to the docs library input |
| `:ETWebFetchResults` | Paginated view of web pages cached during the last agent run |
| `:ETAddToSystemPrompt [range]` | Add selection or focused tree result to persistent system prompt |
| `:ETAddToPrompt [range]` | Add selection or focused tree result to the next prompt (one-shot) |
| `:ETSystemPrompt` | View and edit the full system prompt. `:w<CR>` to save. |
| `:ETInstallTools` | Install missing external tools (bx, ctx7, jq, lynx) |

---

## How It Works

```
  :ET → type prompt → :w<CR>
    │
    ▼
  ┌──────────────────────────┐
  │  LLM (streaming)         │
  │  system: tools-only      │
  │  user: your prompt       │
  └──────────┬───────────────┘
             │ tool calls
             ▼
  ┌──────────────────────────┐
  │  Dispatch each tool:     │
  │  find_files / read_file  │
  │  edit_file (staged)      │
  │  web_fetch (cached)      │
  └──────────┬───────────────┘
             │ results
             ▼
  ┌──────────────────────────┐
  │  Loop until "done" tool  │
  └──────────┬───────────────┘
             │
             ▼
  ┌──────────────────────────┐
  │  Vimdiff review          │
  │  Enter = accept          │
  │  q     = decline         │
  │  :q<CR> = decline all    │
  └──────────┬───────────────┘
             │
             ▼
  Edits written to disk
```

---

## Keybindings

### All popups

| Key | Action |
|-----|--------|
| `:w<CR>` | Submit / save / run search |
| `:wq<CR>` | Submit and close |
| `q`, `:q<CR>` | Close without saving |
| `<C-w>h` | Focus component to the left |
| `<C-w>j` | Focus component below |
| `<C-w>k` | Focus component above |
| `<C-w>l` | Focus component to the right |

### Tree components (search results)

| Key | Action |
|-----|--------|
| `l`, `<CR>` | Expand node / open URL (on leaf) |
| `h` | Collapse node |
| `j` | Next item |
| `k` | Previous item |

### Web Fetch Results

| Key | Action |
|-----|--------|
| `l` | Next page |
| `h` | Previous page |
| `a` | Add current page to prompt context |
| `A` | Add current page to system prompt |

### Edit Review (vimdiff)

| Key | Action |
|-----|--------|
| `<CR>` | Accept this edit |
| `q` | Decline this edit |
| `:q<CR>` | Decline all remaining edits |
| `l` | Next edit |
| `h` | Previous undecided edit |

---

## License

MIT — see [LICENSE](./LICENSE)

For full documentation, see `:help ET` inside Neovim.
