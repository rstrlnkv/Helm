# Helm — Модульная архитектура (design spec)

**Дата:** 2026-07-20
**Статус:** черновик на ревью
**Автор диалога:** пользователь + Claude (brainstorming)

## Цель

Каркас нового macOS-приложения «PowerToys для macOS» — набор независимых утилит-модулей.
С ростом числа фич приложение должно оставаться **быстрым и стабильным**. Первый модуль —
запрет ухода в сон (keep awake). Форк `vorssaint-utils` закрыт; его опыт (assertions,
clamshell, автоматизация, CC-сетка, Liquid Glass, NSPanel) переносится как знание, не как код.

## Платформенные решения (зафиксировано)

- **Сборка:** SwiftPM + `xcodebuild`, XCTest. Никакого самопального `build.sh`.
- **UI-оболочка:** menu-bar панель + отдельное окно-хаб настроек (стиль PowerToys Settings).
- **Минимальная macOS:** 26+ (нативный Liquid Glass без фолбэков).
- **Репозиторий:** новый чистый (`~/Documents/Claude/Helm`).
- **Дистрибуция:** Developer ID + нотаризация (НЕ App Store — sandbox запретит внешние модули).
- **Рабочее имя:** Helm (не «PowerThings» — клэш с Things от Cultured Code).

## Требования к модульности (приоритеты пользователя)

Все три одновременно:
1. **Изоляция крашей** — сбой одного модуля не роняет остальные.
2. **Нулевая цена выключенных** — выключенный модуль не грузится в память, не ест CPU.
3. **Чистые границы** — модуль самодостаточен, не врастает в другие (главная боль форка: 92k LOC связанного кода).

**Ключевой факт macOS/Swift:** краш Swift (force-unwrap, index-out-of-range, `fatalError`)
нельзя поймать внутри процесса — он убивает весь процесс. Значит пункт 1 физически требует
**разных процессов**. Много процессов бьёт по скорости → выбран гибрид (ниже).

## Выбранный подход: C — гибрид (реестр in-process + XPC по требованию)

Отвергнутые альтернативы:
- **A. Чисто in-process** — быстро/просто, но нет изоляции крашей (один `fatalError` роняет всё).
- **B. Полная многопроцессность (PowerToys буквально)** — максимум изоляции, но N процессов ×
  память, IPC на каждый чих UI, подпись на каждый хелпер; для тумблера — оверкилл, скорость хуже.

**C:** протокол-реестр модулей в хост-процессе + ленивая активация (даёт пункты 2 и 3 полностью),
плюс опциональный уход рискованного модуля в XPC-процесс (даёт пункт 1 там, где он реально нужен).
Лёгкие модули (keep-awake, clipboard, mic mute, rename) — in-process (быстро, дёшево). Опасные
(приватные API, DDC/i2c мониторов, SMC-батарея, парсинг чужих процессов) — в XPC (краш изолирован,
авто-рестарт). Не платим процессом за каждый тумблер.

---

## Секция 1 — Абстракция модуля (descriptor + engine, location transparency)

SwiftUI не ходит через XPC → модуль расщеплён надвое:
- **Descriptor** — метаданные + настройки-вью + вклад в UI. Всегда в хосте.
- **Engine** — логика. Может жить in-process ИЛИ в XPC. Хост дёргает через протокол и не знает где
  (location transparency).

```swift
// Метаданные + UI-часть. Всегда в хост-процессе.
protocol ModuleDescriptor {
    static var id: ModuleID { get }                // "keep-awake" — стабильный
    static var metadata: ModuleMetadata { get }    // имя, иконка, категория, permissions
    static var isolation: ModuleIsolation { get }  // .inProcess | .xpc
    static var category: ModuleCategory { get }     // группа в сайдбаре хаба

    func makeEngine() -> any ModuleEngine          // фабрика логики
    func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution?
    func settingsPage(_ vm: ModuleViewModel) -> AnyView
}

// Логика. За протоколом — либо прямой объект, либо XPC-прокси.
protocol ModuleEngine: AnyObject {
    func activate()
    func deactivate()
    // module-specific команды — через типизированный фасад поверх транспорта (Секция 3)
}
```

Engine всегда за протоколом: in-process → хост держит сам объект; XPC → хост держит прокси с тем же
протоколом. UI/настройки пишутся одинаково. **XPC-модуль проектируется под XPC-контракт с первого
дня** (задним числом не переносится бесплатно).

---

## Секция 2 — Реестр + жизненный цикл

```swift
enum ModuleLifecycle { case disabled, activating, active, failed(reason: String) }

final class ModuleHost {
    static let shared = ModuleHost()
    private let descriptors: [ModuleID: any ModuleDescriptor]  // ВСЕ, compile-time
    private var engines: [ModuleID: any ModuleEngine]          // только активные
    private var connections: [ModuleID: NSXPCConnection]       // только активные xpc
    private let store: ModuleStateStore                        // вкл/выкл persistence

    func bootstrap()
    func setEnabled(_ id: ModuleID, _ on: Bool)
    func engine(for id: ModuleID) -> (any ModuleEngine)?
    func lifecycle(_ id: ModuleID) -> ModuleLifecycle
}
```

- **Реестр:** все дескрипторы — compile-time. Дескриптор лёгкий (метаданные), ~ноль памяти.
- **Ленивость:** `enable` → in-proc `makeEngine()+activate()`, xpc → открыть connection + activate.
  `disable` → `deactivate()` + выкинуть engine / invalidate connection. Выключенный = только дескриптор.
- **Хранение (чистые границы):** неймспейс по id — `module.<id>.enabled`, настройки `module.<id>.*`.
  Модули не могут наступить на чужие ключи. Нет общего свалочного Defaults.
- **Супервизия XPC (изоляция):** `interruptionHandler` → если enabled, переоткрыть + re-activate
  (авто-рестарт). Хост и соседи целы.
- **Crash-budget:** >3 падений за 60с → `lifecycle=.failed`, ретраи стоп, в хабе красный бейдж.
  Защита от краш-петли (иначе рестарт-луп сожрёт CPU).
- **Bootstrap:** поднять только enabled. 40 выключено / 3 включено → стартует 3.

---

## Секция 3 — Транспорт: нейтральный канал + три реализации

Внешние модули: **оба типа позже** (нативные подписанные + скриптовые) → контракт транспортно-нейтрален.
Нижний общий знаменатель = обмен сообщениями (скрипт не отдаёт Swift-методы).

```swift
struct EngineCommand: Codable { let name: String; let payload: Data }   // запрос → ответ
struct EngineEvent:   Codable { let name: String; let payload: Data }   // async push

protocol EngineTransport {
    func send(_ cmd: EngineCommand) async throws -> Data
    var events: AsyncStream<EngineEvent> { get }
}
```

Три транспорта, один контракт:
- **LocalTransport** — in-process, прямой диспатч в объект, без сериализации (fast path).
- **XPCTransport** — нативный отдельный процесс, `NSXPCConnection` под капотом.
- **ScriptTransport** (позже) — JSON-канал в песочный раннер (JavaScriptCore/shell).

Модуль наверху видит типизированный фасад (`func activate(minutes:)`), заворачивающий в `EngineCommand`.
Цена: модуль объявляет имена команд + Codable-payload (позже упростим макросом).

### 3b — XPC-хост, подпись, безопасность

- **Внутренние xpc-модули:** общий XPC-service `HelmModuleHostXPC` в бандле, подписан с app,
  hardened runtime + Developer ID. Хостит нативные engine'ы, супервизия рестартит.
- **Внешние нативные:** бинарь вне бандла. Перед запуском ОБЯЗАТЕЛЬНО:
  1. `SecStaticCodeCheckValidity` — валидная подпись + проверка нотаризации (иначе не запускаем).
  2. Явное подтверждение установки плагина пользователем.
  3. Пермишены декларируются в манифесте; на опасные (Accessibility, Screen Recording) —
     отдельное согласие с предупреждением «сторонний код». Пермишены брокерятся хостом.
  4. Свой sandbox-профиль под декларированные права.
- **App Store несовместим** (sandbox запретит запуск внешних бинарей) → только Developer ID.

---

## Секция 4 — UI-вклад модуля

UI всегда в хосте. Descriptor строит вью → вью говорит с engine через фасад → состояние приходит
событиями. Между вью и engine — `ModuleViewModel` (подписан на `transport.events`, репаблишит в
`@Published`; отражает `lifecycle`: спиннер/ошибка при рестарте).

```swift
struct MenuBarContribution {
    var panelTile: AnyView?          // тайл в общей панели Helm
    var statusItem: StatusItemSpec?  // опц. своя иконка в меню-баре
}
```

**Два режима меню-бара:**
- **Общая панель Helm** (дефолт) — одна иконка, клик → панель с `panelTile` всех включённых модулей
  (CC-сетка/список из опыта форка).
- **Своя иконка модуля** (опц., по желанию юзера) — постоянный индикатор (keep-awake активен, mic
  заглушён). Иначе 20 модулей = 20 иконок = помойка.

**Хаб настроек:** хост рисует хром (сайдбар по `category` + тумблер вкл/выкл на строку); модуль отдаёт
только контент страницы (`settingsPage`). Выключенный модуль: строка есть, страница не строится пока
не открыта.

**Развязка:** модуль наружу торчит четырьмя точками — `metadata`, `makeEngine`, `menuBar`,
`settingsPage`. Хост не знает внутренностей, модуль не знает соседей и хост.

---

## Секция 5 — Раскладка SwiftPM

Правило: зависимости текут ВНИЗ, на хост не указывает никто.

```
Helm/
  Package.swift
  Sources/
    HelmContract/          ← ЯДРО-ABI. Foundation-only. Заморозится для внешних плагинов.
    HelmRuntime/           ← Foundation. Инфра headless-логики (NamespacedStore, Log, PermissionDeclaration).
    HelmUI/                ← SwiftUI. UI-часть контракта (ModuleDescriptor/ViewModel) + дизайн-система.
    Modules/
      KeepAwake/
        Engine/            ← Module_KeepAwake_Engine  (deps: HelmContract, HelmRuntime) — БЕЗ SwiftUI
        UI/                ← Module_KeepAwake_UI       (deps: HelmContract, HelmUI, Engine)
      ...
    HelmModuleHostXPC/     ← executable/xpc. Хостит внутренние xpc-engine'ы. Подписан с app.
    HelmApp/               ← executable. ModuleHost, реестр, панель, хаб, кросс-сервисы.
  Tests/
    HelmContractTests/, HelmRuntimeTests/
    Modules/KeepAwake/EngineTests/   ← headless XCTest на чистую логику
```

| Таргет | Тип | SwiftUI | Роль |
|---|---|---|---|
| HelmContract | lib | нет | Протоколы engine/транспорт/метаданные. Замороженный ABI. Крошечный. |
| HelmRuntime | lib | нет | Неймспейс-хранилище, лог, декларация пермишенов. |
| HelmUI | lib | да | UI-часть контракта + дизайн-система (glass, CC-плитки). |
| Module_X_Engine | lib | **нет** | Чистая логика. Headless-тесты, хост in-proc или XPC. |
| Module_X_UI | lib | да | Descriptor, страница настроек, тайл. |
| HelmModuleHostXPC | exe/xpc | нет | Хост внутренних изолированных engine'ов. |
| HelmApp | exe | да | ModuleHost, реестр, панель, хаб. |

**Split Engine/UI обязателен:** engine-таргет физически не линкует SwiftUI → гарантия headless-запуска
в отдельном процессе. Цена — два таргета на модуль — покупает изоляцию + тестируемость + чистую границу.

**Встроенные vs настоящие плагины:** внутренние модули слинкованы в бинарь (SwiftPM не грузит таргеты
динамически). «Не загружен» = engine не создан. Настоящая динамика — только внешние бинари (отдельные
процессы, скан папки + манифест). Это граница v1 (встроенные) → пост-v1 (внешний SDK); контракт один.

---

## Что закрывает три пункта (сводка)

| Требование | Механизм |
|---|---|
| Изоляция крашей | XPC-процессы (`HelmModuleHostXPC` + внешние бинари) + супервизия + crash-budget |
| Нулевая цена выключенных | Ленивый `makeEngine`, неактивный engine не создан, xpc/внешний = не запущенный процесс |
| Чистые границы | Модуль = папка/1-2 таргета, наружу только контракт; неймспейс-хранилище; нет ссылок между модулями |

## Non-goals (v1)

- Публичный plugin-SDK и загрузка внешних бинарей — **пост-v1** (сначала заморозить контракт на
  встроенных модулях, потом freeze ABI и открыть).
- App Store дистрибуция.
- ScriptTransport (скриптовые плагины) — после нативных.
- Модули pillar 2/3 (Bartender-аналог, Dynamic Notch) — отдельные спеки.
- Key remapper / лаунчер / hosts-редактор — не лезем (Karabiner/Raycast/Alfred доминируют).

## Открытые вопросы (в план)

1. Финальное имя/бренд (Helm по умолчанию) + bundle id для нового репо.
2. Первый набор модулей после Keep Awake (кандидаты: Clipboard History, Always on Top, Mic Mute, PowerRename).
3. Формат манифеста внешнего модуля (проектируем контракт с учётом, строим позже).
4. Нужен ли макрос для генерации Command/Event Codable-обвязки (упрощение фасада) — оценить после 2-3 модулей.

## Следующий шаг

Отдельный spec на **модуль Keep Awake** (по ТЗ пользователя), затем writing-plans → реализация
скелета (HelmContract/Runtime/UI/App + Keep Awake) через subagent-driven-development.
