# Модуль VPN — design spec

**Дата:** 2026-07-24
**Статус:** одобрено, на реализацию
**Зависит от:** [архитектура](2026-07-20-helm-architecture-design.md), паттерн модуля из
[Keep Awake](2026-07-20-keep-awake-design.md)

## Цель

Второй модуль Helm: подключение системных VPN (`scutil --nc`) с **автоматизацией по приложению**
(запущено приложение из правила → подключить VPN; закрылось последнее → отключить). Полный порт
рабочей реализации из форка `vorssaint-utils` (`Sources/HelmUtility/Services/VPN/*`, ~678 строк) в
модуль-архитектуру Helm (Engine headless + UI, порты, TDD на чистой логике).

## Что переносим из форка (карта)

| Форк | Новый модуль | Тип |
|---|---|---|
| `VPNSupport` (parseList/parseStatus/defaultConnection) | `Logic/VPNListParser` | pure, TDD |
| `VPNAutoConnectCore` (reference-counting per-app) | `Logic/VPNAutoConnectCore` | pure, TDD (as-is) |
| `VPNRulesSupport` + `VPNAppRule` | `Logic/VPNRules` | pure, TDD |
| `VPNService` (connect/disconnect/toggle/refresh, injected runner+secretProvider) | `VPNEngine` + ports | engine |
| `VPNService+System` (Shell scutil + keychain cred cache) | `SystemPorts` (VPNRunner+Credentials) | боевое |
| `VPNAutoConnectService` (NSWorkspace KVO → core) | вшито в `VPNEngine.activate()` + `AppObserverPort` | engine |
| `VPNSection` (панель), `VPNSettings` (настройки) | `VPNPanelTile`, `VPNSettingsPage`, `VPNDescriptor` | UI |

## Модуль

- id `vpn`, `.inProcess`, **новая категория `.network`** (добавить в `ModuleCategory`, HelmUI).
- Split `Module_VPN_Engine` (без SwiftUI) + `Module_VPN_UI`.
- Permissions: **[]** — `scutil`/`security` не требуют TCC. (L2TP/IPSec secret из System.keychain
  вызывает системный промпт **один раз**; дальше кэш в login-keychain — см. ниже.)

## Engine (`Module_VPN_Engine`, headless)

### Pure-логика (TDD, прямой порт)
- `VPNStatus {connected,connecting,disconnected,disconnecting,unknown}`, `VPNConnection {id,name,status,kind}`.
- `VPNListParser`: `parseStatus`, `parseList(scutil --nc list output)`, `defaultConnection(from:lastUsedName:)`
  (единственный → last-used → первый).
- `VPNAppRule {vpnName, connectOnLaunch=true, disconnectOnQuit=true}` (Codable); `VPNRules`:
  encode/decode (+ legacy `[bundleID:vpnName]` миграция) / `valid(_:against:)` (дропает правила с VPN
  вне живых connections).
- `VPNAutoConnectCore {rules:[bundleID:VPNAppRule]}`: `appLaunched`/`appTerminated` с reference-counting
  (VPN name → set запущенных mapped bundleID), connect на 0→1 если `connectOnLaunch`, disconnect на 1→0
  если `disconnectOnQuit`; `activeVPNs`.

### Порты (протоколы побочек)
- `VPNRunnerPort`: `func run(_ args: [String]) -> String` (запуск `scutil` с аргументами → stdout).
- `VPNCredentialsPort`: `func credentials(for name: String) -> VPNCredentials?` (user/password/secret
  для L2TP/IPSec; nil для IKEv2). Инъекция → тесты keychain-free.
- `AppObserverPort`: `func runningBundleIDs() -> Set<String>`, `func startObserving(_ onChange: @escaping @Sendable () -> Void)`
  (модуль сам считает диффы launched/quit — свой порт, не тащим из KeepAwake; модули независимы).

### `VPNEngine` (ModuleEngine)
- Состояние: `connections`, `autoConnected: Set<String>` (только VPN, поднятые автоматикой — их же и
  опускаем, ручные не трогаем), `runState`.
- Команды через транспорт: `toggle` (дефолтный VPN), `connect {name}`, `disconnect {name}`, `refresh`,
  `reloadRules` (после смены настроек).
- `activate()`: `refresh()` → `reloadRules` (valid против connections) → seed уже запущенных апп
  (`appLaunched` с connect, без disconnect) → `AppObserverPort.startObserving` (диффы → core.appLaunched/
  appTerminated с connect=`{connect($0, auto:true)}` / disconnect=`{disconnect($0)}`).
- `deactivate()`: стоп observe; авто-отключение поднятых автоматикой VPN (autoConnected) — опционально,
  как в форке auto-слой рвёт только свои.
- `connect(name, auto:)`: если creds есть (secret непустой) → `--user/--password/--secret`, запуск в
  фоне (может блокировать); иначе прямой `scutil --nc start name`. `refresh` через ~0.6с.
- `defaultConnection`: сперва подключённый/подключающийся (чтобы строка панели отражала реальность),
  иначе `VPNListParser.defaultConnection` (last-used из `module.vpn.lastUsedName`).
- Эмитит event `state {connections, autoConnected, runState, defaultName}`.

### SystemPorts (боевое)
- `ScutilRunner`: `Shell`-обёртка над `/usr/sbin/scutil` (Process → stdout).
- `KeychainCredentials`: порт трюка форка. `scutil --nc show name` → `AuthPassword`(uuid)/`AuthName`.
  Кэш Helm в login-keychain (service `com.helm.vpn`, `security add-generic-password -U -T /usr/bin/security`):
  читаем кэш без промпта; если пусто — читаем System.keychain (`security ... /Library/Keychains/System.keychain`,
  промпт 1 раз) и кэшируем. nil для VPN без shared secret (IKEv2). Секреты — только в памяти/keychain,
  не логируем.

## UI (`Module_VPN_UI`)

- `VPNDescriptor`: id `vpn`, имя «VPN», symbol `lock.shield` (или `network`), permissions [], category
  `.network`. `makeEngine(store:)` = `VPNEngine` + `VPNSystemPorts` + `VPNSettings(store)`.
- **Своя `VPNViewModel`** (состояние VPN богаче generic): подписка на `state` event → `@Published
  connections/autoConnected/runState/defaultName`. **Требует твик HelmUI: открыть `transport` в
  `ModuleViewModel`** (`public let transport`), чтобы дескриптор строил `VPNViewModel(transport: vm.transport)`.
- `VPNPanelTile`: дефолтный VPN + toggle (индикатор статуса точкой цвета). Если connections > 1 —
  разворачивается в список (тап по строке = connect/disconnect). Порт `VPNSection`.
- `VPNSettingsPage`: (1) список connections со статусом; (2) редактор per-app правил — app-picker
  (NSOpenPanel, как в KeepAwake) + на каждое правило: выбор VPN (Picker из connections) + тумблеры
  connectOnLaunch/disconnectOnQuit + удаление. Пишет `module.vpn.vpnAppRules` (JSON) → `vm.send("reloadRules")`.

## Настройки (namespace `module.vpn.*`)

| Ключ | Тип | Смысл |
|---|---|---|
| `vpnAppRules` | String(JSON) | `[bundleID: VPNAppRule]` |
| `lastUsedName` | String | последний VPN для `toggle` |

## Решения

- VPN **не** красит host-иконку меню-бара (тинтом владеет Keep Awake) — статус VPN виден в тайле.
- Без admin/рута (в отличие от clamshell).
- L2TP/IPSec keychain-кэш переносим (кейс NBCom VPN пользователя).

## Тестирование (headless, чистая логика)

XCTest на: `VPNListParser` (парсинг реального `scutil --nc list`, статусы, defaultConnection),
`VPNRules` (encode/decode + legacy-миграция + valid), `VPNAutoConnectCore` (0↔1 переходы, флаги,
несколько апп на один VPN, activeVPNs). Порты в тестах — фейки; `VPNEngine` — с фейк-раннером,
проверка выданных команд (как форк тестировал VPNService).

## Non-goals (v1)

- Создание/редактирование самих VPN-конфигов (только connect/disconnect существующих системных).
- VPN-типы кроме тех, что видит `scutil --nc` (системные конфиги).
- Тинт host-иконки от VPN.

## Следующий шаг

writing-plans → план (скелет таргетов Module_VPN_{Engine,UI} + HelmUI category/transport твик), TDD,
subagent-driven как Keep Awake.
