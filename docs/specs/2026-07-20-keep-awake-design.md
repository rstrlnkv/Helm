# Модуль Keep Awake — design spec

**Дата:** 2026-07-20
**Статус:** черновик на ревью
**Зависит от:** [архитектура](2026-07-20-helm-architecture-design.md) (подход C, модуль = descriptor + engine)

## Цель

Первый модуль Helm: запрет ухода Mac в сон. Обкатывает in-process путь архитектуры (LocalTransport,
descriptor/engine split, вклад в общую панель + хаб настроек + тинт host-иконки).

## ТЗ пользователя (дословно)

Keep Awake:
1. При подключённом внешнем мониторе
2. При подключённой зарядке
3. При открытых приложениях (список в настройках)
4. По таймеру
5. Двигать указателем раз в N минут (выбор в настройках), чтобы не включалась заставка
6. Иконка в меню-баре окрашивается в выбранный в настройках цвет
7. Иконка приложения в меню-баре — кольцо (выбор формы в настройках)

## Решения (из brainstorming)

- **Clamshell (закрытая крышка) — в v1.** Без него «не спать при мониторе» не работает в доке.
- **Клик по иконке → общая панель Helm** (не своё меню модуля).
- **Защита батареи — опция** (default off).
- **Изоляция:** `.inProcess` (краш-риск ~ноль; обкатка in-process пути).

## Механика движка (`KeepAwakeEngine`, headless, без SwiftUI)

### Ядро сна
- IOKit `IOPMAssertionCreateWithName("PreventUserIdleSystemSleep")` — система не засыпает.
- Опция «держать дисплей включённым» → доп. `PreventUserIdleDisplaySleep` (default OFF — экономия;
  jiggle закрывает заставку без форса дисплея).
- `deactivate` → `IOPMAssertionRelease` обеих.

### Активация и комбинирование условий (OR)
Не спим, если истинно ЛЮБОЕ:
- ручной вкл (тумблер / пресет таймера),
- активен таймер,
- подключён внешний монитор (если опция вкл),
- подключена зарядка (если опция вкл),
- запущено приложение из списка (если список непуст).

Все условия сняты И нет ручного/таймера → `deactivate`. Ручной вкл держит независимо от условий.
Ручной выкл при активном автоусловии → подавляем автоматику пока условие не снимется-и-вернётся
(поведение из форка: `automationSuppressedUntilConditionsClear`).

### Мониторинг условий
- **Монитор:** `NSApplication.didChangeScreenParametersNotification` → пересчёт;
  `CGGetOnlineDisplayList` + `CGDisplayIsBuiltin` (внешний = есть не-builtin).
- **Питание:** `IOPSNotificationCreateRunLoopSource` → пересчёт; `IOPSCopyPowerSourcesInfo`,
  state `"AC Power"` = на зарядке.
- **Приложения:** KVO на `NSWorkspace.shared.runningApplications` (диффы bundleID; надёжнее
  `didLaunch/didTerminate` — ловит Catalyst-апы). Список bundleID в настройках.
- Пересчёт debounce'ится (0.1–0.35с), чтобы всплеск нотификаций не дёргал assertions.

### Clamshell (закрытая крышка)
- Опция «не спать с закрытой крышкой». Когда вкл — любая активная сессия дополнительно ставит
  `pmset disablesleep 1` (IOKit-assertion при закрытой крышке игнорируется macOS — единственный способ).
- Требует беспарольного sudoers-правила `NOPASSWD: /usr/bin/pmset disablesleep 1, .../pmset disablesleep 0`.
  Первый вкл → одноразовый ввод пароля админа для установки правила. Дальше молча.
- **Безопасность/восстановление (критично):** перед `disablesleep 1` пишем guard-флаг в
  namespaced store; на `deactivate`/quit/сбое возвращаем `disablesleep 0`. На старте модуля —
  `recoverIfNeeded`: если флаг стоит и `pmset -g` показывает disabled → вернуть 0 (защита от «остался
  бодрым навсегда» после краша).
- Установка sudoers-правила и все `pmset` — на фоновой очереди, не блокируют UI.

### Предохранитель батареи (опция)
- На батарее (`isOnBattery`) и заряд ≤ X% (настраиваемо, default 20) → `deactivate` с причиной battery.
- Таймер проверки ~30с пока активны.

### Jiggle указателя (опция)
- Раз в N минут (настраиваемо) сдвинуть указатель на ±1px и вернуть (`CGEvent` mouseMoved,
  `.cghidEventTap`). Против заставки/локскрина/сна дисплея без форс-assertion.
- Только пока сессия активна.

### Таймер
- Пресеты: 15м / 1ч / 2ч / бессрочно + свой интервал. `minutes<=0` = бессрочно.
- По истечении → `deactivate` (если нет активного автоусловия, иначе продолжаем как авто-сессия).

### События движка (в UI через ModuleViewModel)
`active: Bool`, `endDate: Date?`, `activeConditions: Set<Condition>`, `clamshellActive: Bool`,
`lifecycle`. Плюс `statusAppearance` (тинт для host-иконки, см. ниже).

## Настройки (namespace `module.keep-awake.*`)

| Ключ | Тип | Default | Смысл |
|---|---|---|---|
| `autoExternalDisplay` | Bool | false | Не спать при внешнем мониторе |
| `autoPower` | Bool | false | Не спать при зарядке |
| `autoApps` | [String] | [] | bundleID приложений-триггеров |
| `defaultDurationMinutes` | Int | 0 | Пресет таймера по умолчанию (0=∞) |
| `keepDisplayOn` | Bool | false | Держать дисплей включённым |
| `jiggleEnabled` | Bool | false | Двигать указатель |
| `jiggleIntervalMinutes` | Int | 5 | Интервал jiggle |
| `clamshellEnabled` | Bool | false | Не спать с закрытой крышкой (pmset) |
| `batteryGuardEnabled` | Bool | false | Авто-выкл на низком заряде |
| `batteryGuardPercent` | Int | 20 | Порог % |
| `activeTintColor` | String | (accent) | Цвет host-иконки пока активно |

Форма host-иконки (кольцо и т.п.) — **app-level** настройка (не модульная), см. ниже.

## UI

### panelTile (в общей панели Helm)
- Тумблер вкл/выкл.
- Ряд пресетов таймера: 15м / 1ч / 2ч / ∞.
- Индикатор активных условий текстом («монитор + зарядка») когда сессия авто.

### settingsPage (хаб)
- Секция «Автоматизация»: тумблеры monitor/charger; список приложений (пикер установленных).
- Секция «Поведение»: keep-display-on; jiggle + интервал; таймер по умолчанию.
- Секция «Закрытая крышка»: clamshell-тумблер (при вкл — поток установки sudoers, статус правила).
- Секция «Батарея»: battery-guard + порог %.
- Секция «Вид»: цвет иконки при активности.

### Меню-бар (host-level)
- Одна иконка Helm. Форма по умолчанию **кольцо**, выбор формы — app-level настройка.
- Клик → общая панель Helm.
- **Тинт:** модуль публикует `statusAppearance` (цвет `activeTintColor`) пока активен → host красит
  иконку; неактивен → обычный template ring. Контракт получает точку `statusAppearance` — модуль
  может просить тинт/бейдж у host-иконки (при многих модулях host выбирает по приоритету).

## Влияние на контракт (HelmContract/HelmUI)

Keep Awake — первый модуль, поэтому вводит минимальные точки контракта, нужные ему:
- `ModuleDescriptor` (id/metadata/isolation/category/makeEngine/menuBar/settingsPage).
- `ModuleEngine` + LocalTransport (in-process).
- `MenuBarContribution.panelTile`.
- **Новое:** `statusAppearance` — опциональный тинт/бейдж host-иконки от модуля.
- `ModuleViewModel` (подписка на события engine).
- Namespaced store (HelmRuntime).
- App-level настройка формы host-иконки (в HelmApp, не в контракте).

XPC-транспорт и `MenuBarContribution.statusItem` (своя иконка модуля) — контракт закладывает, но
Keep Awake их не использует (обкатает будущий модуль).

## Тестирование (headless, чистая логика)

Движок разбивается на чистые функции для XCTest без железа:
- `CombineConditions` — OR-логика активации из набора флагов + suppression.
- `ExternalDisplaySupport.hasExternal(builtInFlags:)`.
- `PowerSupport` — маппинг power-source state → onPower.
- `ClamshellRecovery` — решение «восстановить сон» из (флаг, pmset-вывод).
- `BatteryGuard` — решение deactivate из (isOnBattery, percent, threshold, enabled).
- `TimerPolicy` — что делать по истечении (continue как авто vs deactivate).
- `JiggleTarget` — вычисление точки сдвига в границах дисплея.
Побочки (IOKit, CGEvent, pmset, sudoers) — за инъектируемыми интерфейсами, в тестах — фейки.

## Non-goals (v1)

- Свой status-item модуля (клик = общая панель).
- Скриптовые/иные триггеры сверх ТЗ.
- SMC (лимит заряда 80% — отдельный будущий модуль, не Keep Awake).
- Глобальный хоткей вкл/выкл (можно добавить позже; не в ТЗ).

## Открытые вопросы

1. Дефолтный `activeTintColor` — брать системный accent или зафиксировать (напр. оранжевый как в форке)?
2. Список форм host-иконки для v1: только кольцо, или кольцо + 1-2 (диск/кольцо-с-точкой)?
   (не блокирует; можно начать с кольца.)

## Следующий шаг

writing-plans → план реализации: скелет пакета (HelmContract/HelmRuntime/HelmUI/HelmApp) + модуль
Keep Awake, TDD на чистую логику, subagent-driven исполнение.
