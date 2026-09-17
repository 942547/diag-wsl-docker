# diag-wsl-docker

Диагностический PowerShell-скрипт для машин, где **WSL2 / Docker Desktop / OpenCode CLI** не устанавливаются или не работают (частый сценарий: Windows 10, доменная машина, ограниченные права).

**Скрипт полностью read-only — ничего не меняет на системе.**

## Зачем

Вместо долгих попыток наугад (которые сжигают лимиты OpenCode) скрипт за один запуск собирает полную картину и отдаёт в `diag-report.txt`, который можно целиком вставить в OpenCode/LLM — тот увидит все данные и сможет предложить точечное решение.

## Запуск

От имени Администратора (важно для раздела Optional Features):

```powershell
powershell -ExecutionPolicy Bypass -File .\diag-wsl-docker.ps1
```

Результат: файл `diag-report.txt` рядом со скриптом.

## Что проверяет

| # | Раздел | Данные |
|---|--------|--------|
| 1 | Система | Версия/сборка Windows, издание, `systeminfo` |
| 2 | Виртуализация | VT-x/AMD-V, HypervisorPresent, требования Hyper-V |
| 3 | Optional Features | VirtualMachinePlatform, WSL, Hyper-V (нужен admin) |
| 4 | WSL | `wsl -l -v` (VERSION=1/2!), distros, статус, kernel, .wslconfig, службы |
| 5 | Docker Desktop | Наличие, версия, settings (WslEngineEnabled), логи |
| 6 | OpenCode CLI | node/npm/bun/winget/opencode, ExecutionPolicy |
| 7 | Домен/политики/сеть | Прокси, доступность github.com/npmjs/nodejs, DNS |
| 8 | Гипотезы | Скрипт формирует подсказки (проверить по RAW) |

Вместе с разделами пишется RAW-вывод команд (без обрезки) — чтобы LLM видел исходные данные, а не только интерпретацию.

## Сценарий использования

1. Запустить скрипт на проблемной машине (админ).
2. Взять `diag-report.txt` (полностью).
3. Вставить в OpenCode с вопросом «что делать дальше».
4. OpenCode на основе RAW-данных предложит решение (включить features, переключить WSL-версию, обновить Windows/поставить другую версию Docker и т.д.).

## Лицензия

MIT