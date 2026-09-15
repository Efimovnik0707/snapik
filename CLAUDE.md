# Snapik

Памятка для агентов обеих версий (Windows и macOS): [AGENTS.md](AGENTS.md). Правила синхронизации порта: [macos/SYNC.md](macos/SYNC.md).

## Граф связей кода (codebase-memory)

Перед любым изменением кода и перед ответом «как у нас устроено X» — сначала граф, потом grep. В основной сессии это MCP `codebase-memory` (`.mcp.json` в корне; инструменты `search_graph`, `trace_call_path`, `query_graph`, `detect_changes`, `get_code_snippet`). У субагентов MCP нет, они зовут тот же граф из Bash:

```
"C:/Users/tomat/.local/bin/codebase-memory-mcp.exe" cli trace_call_path '{"function_name": "ShowStackWithoutActivation", "direction": "inbound", "depth": 3}'
"C:/Users/tomat/.local/bin/codebase-memory-mcp.exe" cli search_graph '{"name_pattern": ".*Refresh.*", "label": "Method", "file_pattern": "**/src/**"}'
"C:/Users/tomat/.local/bin/codebase-memory-mcp.exe" cli detect_changes '{"scope": "branch", "base_branch": "master", "depth": 3}'
```

Зачем: в раунде ТЗ №3 правки в одном окне ломали уже работавшее в другом (скролл, порядок карточек), потому что связи искали grep'ом и не видели всех вызывающих. Правило для исполнителя: перед правкой метода/свойства/ресурса — `trace_call_path` inbound по нему, все callers в список задачи; перед коммитом — `detect_changes` по своей ветке, blast radius сверить с тем, что тестировал. Индекс обновлять после слияния в master: `cli index_repository '{"repo_path": "<корень репо>"}'`.

## Lab Notes
<!-- lab-note: [2026-09-15] `git worktree remove --force` на Windows прошёл сквозь junction `.dotnet` и стёр SDK в основном репо (cmd rmdir из bash не сработал, а проверки не было) -> перед remove снимать junction только PowerShell `[IO.Directory]::Delete($p,$false)` и проверять `Test-Path` = False; восстановление `scripts/bootstrap-dotnet.ps1`. -->
<!-- lab-note: [2026-09-14] junction .dotnet для worktree через bash-строку с `\$T` ушёл в папку `snapik-wt$T` -> переменные bash без слэша, PowerShell-скрипт в одинарных кавычках, проверять LinkType. См. [[Knowledge Base/agent-workflow/bash-to-powershell-dollar-escape]] -->
<!-- lab-note: [2026-09-14] rtk искажает `git log -1` после merge (показывает tip ветки) -> проверять rev-parse HEAD + cat-file -p HEAD + reflog. См. [[Knowledge Base/agent-workflow/rtk-git-log-hides-merge-state]] -->
