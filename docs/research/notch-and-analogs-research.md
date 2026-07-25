# Исследование: open-source аналоги + fluid-анимация для будущего модуля Notch

> **Статус: только исследование.** Ничего отсюда не подключено к сборке,
> зависимости не добавлены, код не скопирован. Это справочный материал на
> момент, когда будет проектироваться модуль `notch` (или модуль анализа
> диска / управления меню-баром). Проверено через GitHub API 2026-07-25 —
> звёзды и лицензии со временем меняются, перепроверяй перед использованием.

## Почему именно эти четыре

В задании — найти open-source аналоги четырёх коммерческих macOS-утилит
(DaisyDisk, Alcove, NotchNook, Bartender) плюс разобрать fluid-анимацию для
модуля Notch. Alcove и NotchNook сами по себе закрытые, поэтому ниже —
FOSS-проекты, решающие ту же задачу, а не клоны их кодовых баз.

---

## 1. Аналоги DaisyDisk (визуализация занятого места на диске)

| Проект | Репозиторий | Язык | Звёзды | Лицензия |
|---|---|---|---|---|
| **MacDirStat** | [phalladar/MacDirStat](https://github.com/phalladar/MacDirStat) | Swift/SwiftUI | 42 | MIT |
| **SquirrelDisk** | [adileo/squirreldisk](https://github.com/adileo/squirreldisk) | Rust + TS (Tauri) | 1 797 | AGPL-3.0 |
| **OpenDisk** | [137137137/OpenDisk](https://github.com/137137137/OpenDisk) | Swift | 0 (новый) | MIT |
| **GrandPerspective** | на GitHub только зеркала, канонический дом — [SourceForge](https://sourceforge.net/projects/grandperspectiv/); наиболее поддерживаемый форк: [amake/GrandPerspective](https://github.com/amake/GrandPerspective) | Obj-C | 4 (форк) | GPL-2.0 |

**MacDirStat** — самая релевантная референс-точка для Helm: нативный SwiftUI,
нулевые зависимости, скан через низкоуровневые BSD API (`getattrlistbulk`, а
не `FileManager`, ради скорости), squarified treemap реализован сам, без
сторонней библиотеки. Стоит почитать `Sources/` ради разделения
скан-движка и UI — оно повторяет собственный паттерн Helm «engine vs UI».

**SquirrelDisk** — единственная настоящая реализация sunburst-диаграммы
(фирменный визуал DaisyDisk), но Rust/Tauri, не Swift. Полезен только как
UX-референс (радиальный drill-down, навигация по «хлебным крошкам»), не для
переиспользования кода.

**GrandPerspective** — исходный treemap-инструмент, которому 20 лет, от него
пошла вся категория. На GitHub присутствие слабое (канон — SourceForge), UI
устаревший, но логика сканирования и правил исключения — хороший референс на
корректность.

**Релевантность для Helm:** низкий приоритет, пока модуль анализа диска
реально не запланирован — в текущем списке модулей его нет. Включено по
заданию; MacDirStat — единственный, кого стоит читать внимательно, если это
направление всё-таки возьмут.

---

## 2. Аналоги Alcove / NotchNook (чёлка → утилиты в стиле Dynamic Island)

Прямо релевантная категория для будущего модуля `notch` в Helm.

| Проект | Репозиторий | Язык | Звёзды | Лицензия | Что делает |
|---|---|---|---|---|---|
| **boring.notch** | [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) | Swift (SwiftUI+AppKit) | 10 146 | GPL-3.0 | Де-факто open-source замена NotchNook/Alcove. Now-playing с обложкой и аудио-визуализатором, файловая полка с AirDrop, календарь, зеркало камеры, анимация батареи/зарядки. |
| **Atoll** | [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) | Swift | 3 387 | GPL-3.0 | «Dynamic Island для macOS» — разворачивается из pill в панель медиа/системной инфы нативными SwiftUI spring-анимациями. |
| **NotchDrop** | [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) | Swift | 2 076 | MIT | Узкий скоуп: чёлка как временная файловая полка + зона AirDrop. Хороший референс минимального скоупа (в противовес «всё сразу» у boring.notch). |
| **DynamicNotch** | [jackson-storm/DynamicNotch](https://github.com/jackson-storm/DynamicNotch) | Swift (SwiftUI+AppKit) | 458 | GPL-3.0 | Сделан явно ради воспроизведения *физики* iOS Dynamic Island — spring-разворачивание/сворачивание, «желейный» морфинг, синхронная интерполяция контента. Лучший анимационный референс в подборке (см. §4). |
| **mew-notch** | [monuk7735/mew-notch](https://github.com/monuk7735/mew-notch) | Swift | 531 | GPL-3.0 | Простой подход — индикаторы камеры/батареи без тяжёлого набора фич. Хороший референс «насколько маленьким это может быть». |
| **ComfyNotch** | [AryanRogye/ComfyNotch](https://github.com/AryanRogye/ComfyNotch) | Swift | 146 | — (уточнить в репо) | Чёлка как HUD с виджетами (музыка, яркость/громкость, AI-чат). Проект моложе и меньше, но плагинная архитектура виджетов заслуживает взгляда. |

**Релевантность для Helm:** самый сильный кластер. `boring.notch` и `Atoll`
достаточно крупные (10k / 3.4k звёзд), чтобы доверять их обвязке на уровне
окон — notch-приложения вынуждены воевать со слоями NSWindow, определением
края экрана на маках с чёлкой и без, и с мульти-дисплейными странностями.
Это ровно тот класс граблей, о которых предупреждает `ARCHITECTURE.md`
самого Helm применительно к панели и status item. Почитать, как они
определяют геометрию чёлки (`NSScreen.safeAreaInsets` vs. захардкоженные
размеры pill), *до* проектирования notch-модуля — сэкономит цикл отладки.

`NotchDrop` и `mew-notch` — архитектурно более удобные референсы, чем
`boring.notch`, именно потому что они меньше: шов engine/UI виден без
продирания через приложение с полным набором фич.

---

## 3. Аналоги Bartender (управление иконками меню-бара)

| Проект | Репозиторий | Язык | Звёзды | Лицензия |
|---|---|---|---|---|
| **Ice** | [jordanbaird/Ice](https://github.com/jordanbaird/Ice) | Swift | 29 031 | GPL-3.0 |
| **SwiftBar** | [swiftbar/SwiftBar](https://github.com/swiftbar/SwiftBar) | Swift | 4 309 | MIT |
| **SaneBar** | [sane-apps/SaneBar](https://github.com/sane-apps/SaneBar) | Swift | 259 | MIT |

**Ice** — признанная сообществом замена Bartender (стал дефолтной
рекомендацией после смены владельца Bartender в 2024). Нативный Swift, без
Electron, умеет прятать/показывать элементы, управлять отступами и знает про
чёлку (пересечение с §2: ему приходится рассуждать о той же геометрии). При
29k звёзд это самый надёжный референс во всём документе на вопрос «как
корректно получать и задавать позиции меню-бар-элементов чужих приложений» —
печально недокументированная область, близкая к приватным API.

**SwiftBar** решает другую задачу (превращает shell-скрипты в плагины
меню-бара) — не совсем аналог Bartender, брать только как референс «как
построить надёжное host-приложение для меню-бара», если понадобится.

**SaneBar** маленький (259 звёзд), но полностью MIT и явно «privacy-first,
все фичи открыты» — стоит пролистать ради компактной однозадачной
реализации в противовес полнофункциональному Ice.

**Релевантность для Helm:** у Helm уже есть status item (см.
`ARCHITECTURE.md`/`CLAUDE.md`). Если когда-нибудь рассмотрят фичу в стиле
Bartender («управлять иконками чужих приложений»), Ice — единственный
референс, который стоит читать внимательно. Оговорка та же: в текущем
роадмапе Helm этого нет, включено по заданию.

---

## 4. Техники fluid-анимации для будущего модуля Notch

### Базовый инструментарий SwiftUI

- **`matchedGeometryEffect`** — штатный механизм морфинга frame/формы одной
  вью в другую (idle pill → развёрнутая панель). Лучшие разборы:
  - [SwiftUI Lab — MatchedGeometryEffect Part 1 (Hero Animations)](https://swiftui-lab.com/matchedgeometryeffect-part1/) — самый глубокий технический разбор того, как реально интерполируются фреймы.
  - [Hacking with Swift — how to synchronize animations with matchedGeometryEffect](https://www.hackingwithswift.com/quick-start/swiftui/how-to-synchronize-animations-from-one-view-to-another-with-matchedgeometryeffect)
  - [Better Programming — Replicating the Dynamic Island Animation in SwiftUI](https://betterprogramming.pub/dynamic-island-animation-5869fbce41e6) — ближе всего к нашему кейсу: проходит ровно паттерн pill→панель, включая заявленные размеры реального Dynamic Island (верхний отступ 11pt, idle pill 126×37.33pt) как отправную точку.
- **Spring-анимации** (`.animation(.spring(response:dampingFraction:blendDuration:))` /
  `.interactiveSpring()`) — именно это, а не `.easeInOut`, заставляет движение
  в стиле Dynamic Island читаться как «fluid», а не как «сглаженное». И
  `DynamicNotch`, и `Atoll` (см. §2) используют только spring-кривые для
  разворачивания/сворачивания — никакого linear/cubic easing в слое переходов.
- **Keyframe-анимации** (`KeyframeAnimator`, SwiftUI 4+) — для многостадийных
  переходов (pill → расширение по ширине → по высоте → появление контента),
  которые одной spring-кривой чисто не выразить.

### Уровни ниже SwiftUI (только если matchedGeometryEffect не даст нужной плавности)

- **Canvas + Metal-шейдеры** для настоящего liquid/blob-морфинга, а не только
  интерполяции фреймов:
  - [NakaokaRei/MetalCanvas](https://github.com/NakaokaRei/MetalCanvas) (11★, MIT) — Swift-обёртка для рендера сырых Metal-шейдеров на Canvas-подобной поверхности, вдохновлена glsl-canvas. Актуально, если панели чёлки когда-нибудь понадобится настоящий liquid-metal эффект, а не морфинг прямоугольника.
  - [ajagatobby/SwiftMotion](https://github.com/ajagatobby/SwiftMotion) — сборник эффектов на Metal-шейдерах (`LiquidText`, `MorphImage`), оформленных как SwiftUI-модификаторы. Полезен, чтобы увидеть паттерн интеграции шейдер↔SwiftUI, не строя его с нуля.
  - [Cindori/FluidGradient](https://github.com/Cindori/FluidGradient) (429★, MIT) — куда более лёгкий подход: анимированные фоновые градиенты из наложенных размытых «блобов» на CoreAnimation, вообще без Metal. Если цель — просто мягкий движущийся цветной фон под контентом чёлки, это сильно проще шейдерного пайплайна.
- **«Liquid Glass» из WWDC 2025** — реальный эффект искажения/преломления,
  который Apple раскатала системно; [lucasromerodb/liquid-glass-effect-macos](https://github.com/lucasromerodb/liquid-glass-effect-macos) — демо этого визуального стиля на macOS, написанное с нуля (не приватный API). Полезно, чтобы понять, как далеко можно уехать на публичных SwiftUI-материалах (`.glassEffect`, blur + specular-оверлеи) до перехода на кастомные шейдеры.

### Реальный исходник notch-приложения, отвечающий на вопрос «как они это делают»

Вместо того чтобы собирать хореографию разворачивания по статье в блоге,
**`DynamicNotch`** (§2) — самый прямой референс: в README прямо заявлено
«physics-based spring animations, jelly-like morphing transitions,
synchronized content interpolation», то есть ровно наш брифинг по fluid-чёлке.
`boring.notch` и `Atoll` — полезное второе мнение по той же задаче на большем
масштабе и зрелости.

---

## Что стоит позаимствовать для Helm

1. **Определение геометрии чёлки** — почитать, как `boring.notch`/`Atoll`/`Ice`
   получают настоящий bounding box чёлки (`NSScreen.safeAreaInsets`,
   `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`) вместо хардкода пикселей, и
   как деградируют на маках без чёлки. Самое ценное, что нужно проверить до
   написания любого кода notch-модуля — это ровно тот класс граблей
   «выстрадано отладкой», о котором говорит конвенция `ARCHITECTURE.md` в Helm.
2. **Дисциплина «только spring»** — подход `DynamicNotch` (spring-кривые
   везде, никаких ease-in/out) — самый дешёвый способ получить ощущение
   «fluid», не трогая Metal. Должно быть дефолтом для первой итерации модуля.
3. **`matchedGeometryEffect` для морфинга pill↔панель** — хорошо
   документировано, нативно, без новых зависимостей. Metal/Canvas
   (MetalCanvas, SwiftMotion, FluidGradient) — растяжимая цель, только если
   нативный SwiftUI-морфинг окажется визуально недостаточным. Не хвататься
   за него первым.
4. **Дисциплина скоупа от NotchDrop/mew-notch/SaneBar** — все три маленькие,
   однозадачные, читаются от начала до конца. Если notch-модуль Helm начнётся
   как узкий однофичёвый модуль (в паттерне Helm «дескриптор + engine, чистая
   логика в `Engine/Logic/`» из `CLAUDE.md`), эти три подходят по размеру
   лучше, чем полнофункциональный `boring.notch`.
5. **Позиционирование элементов меню-бара (`Ice`)** — актуально, только если
   когда-нибудь заскопят фичу в стиле Bartender; проект на 29k звёзд, считать
   самым надёжным референсом по этой конкретной недокументированной
   поверхности API.

Код ни из одного проекта выше не копировался. Лицензии, за которыми надо
следить, если код *всё же* будут адаптировать: GPL-3.0 (`boring.notch`,
`Atoll`, `DynamicNotch`, `mew-notch`, `Ice`) — копилефт, при переиспользовании
кода (не просто техники) обяжет открыть исходники Helm на тех же условиях.
MIT-проекты (`NotchDrop`, `SaneBar`, `MacDirStat`, `MetalCanvas`,
`FluidGradient`) — безопасны для реального заимствования сниппетов.
