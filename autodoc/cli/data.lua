local data = {}

data.header = [[
---
#
#  WARNING: this file was auto-generated by a script.
#  DO NOT edit this file directly. Instead, send a pull request to change
#  the files in https://github.com/Kong/kong/tree/master/autodoc/cli
#
title: CLI Reference
source_url: https://github.com/Kong/kong/tree/master/autodoc/cli
---

The provided CLI (*Command Line Interface*) allows you to start, stop, and
manage your Kong instances. The CLI manages your local node (as in, on the
current machine).

If you haven't yet, we recommend you read the [configuration reference][configuration-reference].

## Global flags

All commands take a set of special, optional flags as arguments:

* `--help`: print the command's help message
* `--v`: enable verbose mode
* `--vv`: enable debug mode (noisy)

## Available commands

]]

data.command_intro = {
  ["prepare"] = [[
    This command prepares the Kong prefix folder, with its sub-folders and files.
  ]],
}

data.footer = [[

[configuration-reference]: /gateway/{{page.kong_version}}/reference/configuration/
]]

return data
