# Иконки игроков — план реализации

Статус: **реализовано в `0.4.0`**, кроме самих DDS-ассетов — манифест
`core/iconpacks.lua` пуст до поставки библиотеки. Итоговые отличия от плана
перечислены в §1.1.

Смежные документы: `DEVELOPMENT.md` (архитектура аддона, EN), `README.md` / `README.ru.md` (для игрока).

---

## 1.1 Что вышло иначе, чем в плане

* Рамка цели умеет рисовать только иконку: если имя не пересобирается
  (`replaceTargetName` выключен) или игрок ещё не известен базе, иконка
  дописывается перед текстом игры. Иначе игнорируемый незнакомец — самый частый
  случай — остался бы без метки. Подробности в `DEVELOPMENT.md` §7.6.
* Строка списка в браузере зажимает размер иконки в 24 px (высота строки 26 px),
  социальные строки — в `IRY.ICON.socialMax`.
* Проверка игнор-листа сначала спрашивает игровой `IsIgnored(name)` и только
  потом кеш; порядок аргументов `GetIgnoredInfo` не считается фиксированным.
* Регистрация событий пропускает константы, которых нет в клиенте, вместо того
  чтобы падать в `Initialize`.
* Единственный путь в 3D — группа через мост OSI. Цели под прицелом 3D-иконки
  нет и быть не может: ESO не отдаёт позицию не-группового юнита
  (`GetUnitRawWorldPosition("reticleover")` и `GetUnitWorldPosition` отвечают
  `0,0,0`), поэтому привязывать позиционную иконку не к чему. В рамке цели
  остаётся 2D-иконка, она работает для любого игрока.
* Библиотека поставляется в `icons/base`: 75 файлов 128×128 DXT5 с мип-уровнями
  (1.6 МБ), а не 64×64 из плана — UI всё равно масштабирует, размер в мире задаёт
  OSI. Метка blacklist по умолчанию — `rooster.dds` (`IRY.ICON.blacklistDefault`);
  первая иконка манифеста используется только если встроенной метки в нём нет.

---

## 1. Зафиксированные решения

| Вопрос | Решение |
|---|---|
| Сколько иконок на игрока | **одна**, поле `player.icon` |
| Где показывается | target frame, друзья, ростер, Ignored, наше окно, мир |
| Размер в UI | 28 px (слайдер 16–40, в соцсписках жёсткий потолок 28) |
| Размер в мире | задаёт OSI (`iconsize`, по умолчанию 128) |
| Набор иконок | один на все поверхности, 64×64 DDS, курируемый |
| Приоритет | ручная иконка > иконка blacklist > нет иконки |
| Blacklist | встроенный игровой Ignore list (`GetNumIgnored` / `GetIgnoredInfo` / `IsIgnored`) |
| Иконка blacklist | отдельная настройка, по умолчанию **включена**; метка по умолчанию — `rooster.dds` |
| Мастер-тумблер | `showIcons`, выключает **все** картинки, по умолчанию включён |
| Мир (3D) | рендерит **OSI** через публичный API, только над группой; своего рендера нет |
| Чат | не трогаем (если OSI сам рисует — его дело) |
| Анимации | не поддерживаем (в 2D их нечем показать) |
| LibCustomIcons | только читаем через OSI, записывать не можем и не будем |
| Документ | этот файл — dev-only, в релизный zip не попадает |

---

## 2. Архитектура

Три слоя, каждый следующий не знает о предыдущем:

```
данные          player.icon (SV) + настройки + кеш Ignore list
   ↓
правило         IRY.Icons:Effective(id, name)  ->  путь к текстуре | nil
   ↓
поверхности     2D: target frame, соцсписки, наше окно
                3D: мост в OSI (только группа)
```

Правило одно на все поверхности. Если оно вернуло `nil` — поверхность просто ничего не рисует, без «заглушек».

---

## 3. Модель данных

### 3.1 Запись игрока (`core/store.lua`)

```lua
player.icon       = nil   -- "IRememberYou/icons/ody/skull.dds" | nil
player.iconCopied = nil   -- true, если иконка пришла из поглощённой записи
```

`iconCopied` нужен только для честного undo merge: если при слиянии мы забрали иконку у `src`, то при откате её надо снять с `dst` и оставить у `src`. Если иконка была у `dst` своя — не трогаем.

Новые методы:

```lua
Store:GetIconPath(id)      -- resolveFinal + nil-safe
Store:SetIcon(id, path)    -- валидация (префикс "IRememberYou/icons/", суффикс ".dds")
Store:ClearIcon(id)
```

Изменения в существующих:

* `Store:Merge(src, dst)`: `if not dst.icon and src.icon then dst.icon = src.icon; src.iconCopied = true end`
* `Store:UndoMerge(src)`: `if src.iconCopied then dst.icon = nil; src.iconCopied = nil end`
* `Store:Dump(id)`: строка `  icon: <path>` (нужна для отладки без UI)
* `Store:Forget` / `Purge` / `Wipe`: ничего не меняется, иконка уходит вместе с записью

### 3.2 Настройки (`core/constants.lua`)

```lua
-- icons
showIcons      = true,
iconSize2d     = 28,
blacklistIcons = true,
blacklistIcon  = "IRememberYou/icons/ody/skull.dds",
```

Плюс константы:

```lua
IRY.ICON = { min = 16, max = 40, socialMax = 28, default = 28 }
IRY.ICON_FOLDER = "IRememberYou/icons/"
```

Схему SV **не поднимаем**: новые поля необязательные, `EnsureSchema` ничего не ломает.

### 3.3 Кеш Ignore list (`core/blacklist.lua`, новый)

В памяти, в SV не пишется:

```lua
local set = {}   -- [lower(character name)] = true

function Blacklist:Rebuild()          -- O(n), n <= 100
function Blacklist:IsIgnored(name)    -- O(1)
```

События: `EVENT_IGNORE_ADDED`, `EVENT_IGNORE_REMOVED`, `EVENT_IGNORE_NOTE_UPDATED`, плюс `EVENT_PLAYER_ACTIVATED` (на случай поздней загрузки списка).

Нормализация: `string.lower(IRY.Util.NormalizeCharacter(name))`. В Ignore list хранятся имена персонажей, не @аккаунты.

Отдельно: `Blacklist:AnyIgnored(player)` — для нашего окна, где у записи может быть несколько персонажей. Проверяет все известные имена; используется только в UI, не в мире.

---

## 4. Файлы

| Файл | Статус | Что делаем | ~строк |
|---|---|---|---|
| `IRememberYou.txt` | правка | 4 новых файла в порядке загрузки | 4 |
| `core/constants.lua` | правка | настройки + константы | 12 |
| `core/store.lua` | правка | поле, 3 метода, merge/undo/dump | 45 |
| `core/blacklist.lua` | **новый** | кеш Ignore list + события | 70 |
| `core/iconpacks.lua` | **новый** | манифест наборов (пути) | 20 + N |
| `core/icons.lua` | **новый** | правило и мост OSI | 150 |
| `ui/social.lua` | правка | иконка в 3 списках + подавление дублей | 55 |
| `ui/targetframe.lua` | правка | иконка в строке имени | 20 |
| `ui/browser.lua` | правка | строка, блок в панели, пикер | 130 |
| `ui/browser.xml` | правка | блок иконки в панели деталей | 20 |
| `ui/iconpicker.xml` | **новый** | окно выбора + виртуальная плитка | 70 |
| `ui/iconpicker.lua` | **новый** | сетка, страницы, выбор | 140 |
| `ui/reticlemarker.lua` | **новый** | экранная метка над прицелом (необязательная) | 100 |
| `ui/settings.lua` | правка | секция «Icons» + метка прицела | 60 |
| `ui/commands.lua` | правка | `/pa icons`, `/pa icon` | 35 |
| `core/print.lua` | правка | `RefreshUI` → `Icons:Apply()` | 6 |
| `lang/en.lua`, `lang/ru.lua` | правка | ~20 ключей в каждый | 40 |
| `icons/` | **новый** | DDS + `CREDITS.md` | — |
| `DEVELOPMENT.md`, `CHANGELOG.md`, README | правка | документация | 60 |

Итого кода ≈ **900 строк** без ассетов.

---

## 5. Детали по файлам

### 5.1 `core/icons.lua` — сердце

```lua
local Icons = {}
IRY.Icons = Icons

local osiReady = false
local pushed   = {}   -- [lowerName] = true          — что записали мы
local saved    = {}   -- [lowerName] = {texture, color} | false — что было до нас
```

**Правило:**

```lua
function Icons:Effective(id, name)
    local s = settings()
    if not s.showIcons then return nil end
    if id then
        local path = IRY.Store:GetIconPath(id)
        if path then return path end
    end
    if s.blacklistIcons and name and IRY.Blacklist:IsIgnored(name) then
        return s.blacklistIcon
    end
    return nil
end
```

**Определение OSI.** `IRememberYou` грузится раньше `OdySupportIcons` по алфавиту, поэтому `_G.OSI` на старте почти всегда `nil`. Ждём `EVENT_ADD_ON_LOADED` с именем `OdySupportIcons`, затем `zo_callLater(Apply, 0)`, чтобы не обогнать его собственный init. Плюс перепроверка на `EVENT_PLAYER_ACTIVATED`.

Все обращения к чужому аддону — через `pcall`-обёртку: если m00nyONE переименует метод, мы не упадём.

**Группа:**

```lua
function Icons:Apply()
    local o = osi(); if not o then return end
    for i = 1, GROUP_SIZE_MAX or 24 do
        local unit = "group" .. i
        local name = GetUnitDisplayName(unit)
        if name and name ~= "" then
            local key  = string.lower(name)
            local path = self:Effective(IRY.Resolver:ForUnit(unit), name)
            if path then
                if not pushed[key] then
                    saved[key]  = o.special and o.special[key] or nil
                    pushed[key] = true
                end
                o.SetCustomIconForUnit(key, path, { 1, 1, 1 })
            elseif pushed[key] then
                o.RemoveCustomIconFromUnit(key)
                if saved[key] then
                    o.SetCustomIconForUnit(key, saved[key].texture, saved[key].color or { 1, 1, 1 })
                end
                pushed[key], saved[key] = nil, nil
            end
        end
    end
end
```

Три правила, которые здесь зашиты:

1. ключ всегда `lower(displayName)` — OSI ищет только так;
2. чужую иконку не трогаем, если у нас своей нет;
3. чужую иконку сохраняем и возвращаем при снятии.

**Reticleover — почему 3D-иконки нет.** `special` работает только для группы, а
позиционная иконка требует world-координат, которых клиент для цели под прицелом
не отдаёт: `GetUnitRawWorldPosition("reticleover")` (и `GetUnitWorldPosition`)
возвращают `0,0,0` для любого юнита вне группы, кроме питомцев и манекенов. Точка
`0,0,0` — начало координат мира, то есть иконка оказалась бы за камерой или
настолько далеко, что затухание OSI её погасило бы: внешне это выглядит как
«ничего не нарисовалось». API-обхода нет — позиции не-групповых игроков закрыты
для всех аддонов, поэтому путь `CreatePositionIcon` из плана удалён вместе с
отладочной командой; цель под прицелом получает 2D-иконку в рамке. Если ZOS
когда-нибудь откроет позицию, вернуть путь можно по истории git.

**Подавление 2D-дублей.** OSI рисует наш `special` ещё и в друзьях/ростере/чате:

```lua
local OSI_2D = { friends = "fluse", guild = "gruse", chat = "cwuse" }

function Icons:OsiHandles2D(surface)
    if not self:OsiReady() or not settings().showIcons then return false end
    return safeGetOption(OSI_2D[surface]) == true
end
```

**События:** `EVENT_GROUP_MEMBER_JOINED`, `EVENT_GROUP_MEMBER_LEFT`, `EVENT_GROUP_MEMBER_CONNECTED`, `EVENT_GROUP_MEMBER_DISCONNECTED`, `EVENT_GROUP_MEMBER_ACCOUNT_NAME_UPDATED`, `EVENT_UNIT_CHARACTER_NAME_CHANGED` (игрок переименовался в группе — перепушить под новым ключом), `EVENT_ADD_ON_LOADED`, `EVENT_PLAYER_ACTIVATED`.

**Мастер-тумблер:** `Icons:RemoveAll()` → снять всё, что в `pushed`, и вернуть `saved`.

### 5.2 `core/iconpacks.lua` — манифест

ESO не умеет перечислять файлы, поэтому список — это данные:

```lua
IRY.IconPacks = {
    {
        id    = "ody",
        title = "ODY",
        icons = {
            "IRememberYou/icons/ody/skull.dds",
            "IRememberYou/icons/ody/wolf.dds",
            -- ...
        },
    },
}

function IRY.Icons:AllPaths()   -- плоский кешированный список
```

Проверка при загрузке (только в debug): каждый путь начинается с `IRY.ICON_FOLDER` и кончается `.dds`. Опечатку в манифесте иначе не поймать — ESO молча рисует пустоту.

### 5.3 `ui/social.lua`

Иконка ставится **текстовой разметкой в начало `DisplayName`**, без новых контролов и без сдвига вёрстки:

```lua
local ICON_MARK = "^|t%d+:%d+:[^|]+|t ?"   -- для идемпотентности

local function stripIcon(text) return (text:gsub(ICON_MARK, "")) end

function Social:DecorateRow(control, data)
    ...
    local text = stripIcon(label:GetText() or "")
    local path = IRY.Icons:EffectiveForSocial(data)   -- см. ниже
    if path then
        text = string.format("|t%d:%d:%s|t ", size, size, path) .. text
    end
    -- дальше существующая логика суффикса, но от `text`
end
```

`plain()` (функция измерения ширины) расширяется: вырезать и `|t…|t`, иначе `GetTextWidth` посчитает разметку как текст.

`EffectiveForSocial(data)`:

```lua
local account   = IRY.Util.NormalizeAccount(data.displayName)
local character = IRY.Util.NormalizeCharacter(data.characterName)
local id = IRY.Store:FindByAccount(account) or IRY.Store:FindByCharacter(character)
return IRY.Icons:Effective(id and IRY.Store:ResolveFinal(id) or nil, character or account)
```

Для друзей `displayName` — это `@аккаунт`, `characterName` — персонаж; для Ignored наоборот, только имя персонажа. Проверяем blacklist по имени персонажа.

Хуки:

```lua
Social:Install()  -- + hookManager(IGNORE_LIST_MANAGER)
```

Подавление: в начале `DecorateRow` — `if IRY.Icons:OsiHandles2D("friends") then return end` (соответственно `guild`). У Ignored аналога нет: OSI его не хукает.

### 5.4 `ui/targetframe.lua`

```lua
local function withIcon(unitTag, text)
    local path = IRY.Icons:ForUnit(unitTag)
    if not path then return text end
    local size = settings().iconSize2d or 28
    return string.format("|t%d:%d:%s|t ", size, size, path) .. text
end
```

В `ApplyName`:

```lua
local text = withIcon(unitTag, name)
text = withDifficultyIcon(unitTag, text)   -- существующие обёртки
text = withTargetMarker(frame, unitTag, text)
```

Порядок даёт: маркер, сложность, наша иконка, имя. Больше ничего не меняется.

### 5.5 `ui/browser.xml` + `ui/browser.lua`

**Строка списка.** Тоже разметкой, XML не трогаем: `nameLabel:SetText(prefix .. player.displayName)`, `prefix` — `|t24:24:path|t `.

**Панель деталей.** Новый фиксированный блок под заголовком (ширина панели 328):

* `IRY_BrowserDetailIcon` — `Texture` 64×64, `(10, 38)`;
* `IRY_BrowserDetailIconName` — подпись под ним (`ZoFontGameSmall`, 64 px, ELLIPSIS);
* `IRY_BrowserDetailIconPick` — кнопка 120×24, `(84, 38)`;
* `IRY_BrowserDetailIconClear` — кнопка 120×24, `(84, 66)`;
* `IRY_BrowserDetailPanelLines` — сдвинуть с `y=40` на `y=112`.

В `browser.lua`: фолбэк `linesHeight = panelHeight - 68` → `- 140`; в `RenderDetailPanel` выставлять текстуру/подпись/доступность кнопок, с учётом «иконка из blacklist» (тогда подпись серая и Clear неактивна).

**Пикер** (`ui/iconpicker.lua` + `.xml`) — отдельное `TopLevelControl` по центру экрана:

* заголовок, кнопка закрытия, кнопки страниц `◀ ▶`;
* сетка `CreateControlFromVirtual("IRY_IconTile", container, "IRY_IconTile")`;
* плитка: `Button` 64×64, внутри `Texture` 64×64 и подсветка выбранной;
* 8 × 5 = 40 плиток на страницу, размер окна ≈ 640×470;
* клик → `Icons:Assign(id, path)` → закрыть → `Browser:Refresh()`;
* ESC/повторное открытие не плодят контролы (сетка строится один раз).

Кнопка «выбрать» открывает пикер только для текущей записи; состояние (`pickerPlayerId`) хранится в `browser` state.

### 5.6 `ui/settings.lua`

Секция `OPT_SEC_ICONS`:

| контрол | ключ | заметка |
|---|---|---|
| checkbox «Show player icons» | `showIcons` | после — `IRY:RefreshUI()`, гасит и метку прицела |
| slider 16–40 | `iconSize2d` | подпись «UI only, world size is set in OSI» |
| checkbox «Marker above the reticle» | `reticleMarker` | по умолчанию выключена; сама метка живёт в `ui/reticlemarker.lua` |
| slider 16–128, шаг 2 | `reticleMarkerSize` | собственный размер метки, не связан с иконками списков |
| checkbox «Move the marker» | `reticleMarkerLocked == false` | галочка = режим перемещения; установка разблокирует и включает метку, снятие закрепляет позицию и пишет строку в чат |
| checkbox «Hide on dead targets» | `markerSkipDead` | |
| checkbox «Only on hostile targets» | `markerHostileOnly` | `IsUnitAttackable("reticleover")` |
| checkbox «Only in PvP areas» | `markerPvPOnly` | `IsPlayerInAvAWorld()` или `IsActiveWorldBattleground()` |
| checkbox «Mark ignored players» | `blacklistIcons` | |
| button «Choose blacklist icon» | — | открывает пикер в режиме `blacklist`; по умолчанию `IRY.ICON.blacklistDefault` (`rooster.dds`) |
| description | — | статус OSI: найден/нет, `customuse` вкл/выкл, `fluse/gruse` вкл/выкл |

Описание — единственное место, где игрок узнает, почему над головами пусто. Без него фича выглядит сломанной.

Метку прицела рисует `ui/reticlemarker.lua`: top-level окно, внутри — `CT_TEXTURE` (как фоны панели настроек) и `CT_LABEL` с подсказкой `MARKER_HINT`, видимой только в режиме перемещения. Позиция — `reticleMarkerX, reticleMarkerY` от центра экрана, путь из `Icons:ForUnit("reticleover")`, размер из `reticleMarkerSize`. Она скрыта при `showIcons == false`, `reticleMarker ~= true`, `IsReticleHidden()`, включённых фильтрах, когда пути нет, и когда участник группы уже получил нашу иконку через OSI (`Icons:HasGroupIcon`) — иначе он видел бы две одинаковые картинки; обновляется событиями прицела, `EVENT_UNIT_CHARACTER_NAME_CHANGED` для `reticleover`, `IRY:RefreshUI()` и раз в секунду.

Позиция задаётся перетаскиванием: кнопка снимает `reticleMarkerLocked`, метка включает мышь, `StartMoving()`/`StopMovingOrResizing()` двигают контрол, а `SavePosition()` переводит результат в смещения от центра, зажимает по границам экрана и сохраняет в SavedVariables. Начинает перетаскивание только левая кнопка; `OnMouseUp` и `OnMoveStop` вызывают один идемпотентный `finishDrag`, поэтому позиция сохраняется, даже если ESO завершила перемещение без `OnMouseUp`. Пока метка разблокирована, фильтры и `IsReticleHidden()` игнорируются, а без цели рисуется заглушка `IRY.ICON.markerPlaceholder` (`green_arrow.dds`) — иначе её негде было бы взять. Это экранная накладка, а не 3D: она не следует за дистанцией, и функции расстояния до юнита в API нет, поэтому позицию подбирает сам игрок.

### 5.7 `ui/commands.lua`

```
/pa icons on|off          мастер-тумблер
/pa icon <id>             показать текущую иконку и её источник (manual/blacklist/none)
/pa icon <id> <path>      назначить вручную (для отладки)
/pa icon <id> clear       снять
/pa marker                отчёт о метке прицела (настройки, контрол, цель)
/pa marker test           три тестовые картинки для диагностики
/pa purge [days] [confirm]  очистка только со словом подтверждения
/pa debug ignore          вывести кеш Ignore list
```

### 5.8 `core/print.lua`

```lua
function IRY:RefreshUI()
    self:RefreshTargets()
    if IRY.ReticleMarker then IRY.ReticleMarker:Refresh() end
    if IRY.Icons then IRY.Icons:Apply() end
    if IRY.Browser then IRY.Browser:RefreshIfShown() end
end
```

Соцсписки намеренно не обновляем: при смене иконки наше окно открыто, социальное — нет; строки пересоберутся при следующем открытии. Если понадобится — добавить `Social:Refresh()` с проверкой `*_SCENE:IsShowing()`.

### 5.9 Локализация

Новые ключи (EN + RU, симметрично):

```
OPT_SEC_ICONS, OPT_ICONS_SHOW, OPT_ICONS_SHOW_TIP, OPT_ICONS_SIZE, OPT_ICONS_SIZE_TIP,
OPT_BLACKLIST_ICONS, OPT_BLACKLIST_ICONS_TIP, OPT_BLACKLIST_PICK,
OPT_OSI_FOUND, OPT_OSI_MISSING, OPT_OSI_DISABLED, OPT_OSI_2D_ON,
DETAIL_ICON_HEADER, DETAIL_ICON_NONE, DETAIL_ICON_BLACKLIST,
BTN_ICON_PICK, BTN_ICON_CLEAR, PICKER_TITLE, PICKER_PAGE,
ICON_SET, ICON_CLEARED, ICON_INVALID,
CMD_ICONS_ON, CMD_ICONS_OFF,
```

---

## 6. Этапы

### Этап 0 — ассеты (можно параллельно)

Собрать набор, разложить, заполнить манифест. Критерии — раздел 10. Без этого этапа этапы 2+ не проверить визуально.

### Этап 1 — данные

`constants`, `store`, `blacklist`, `iconpacks`, `icons` (только `Effective`), строки в манифесте, команды.

**DoD:** `/pa icon 5 IRememberYou/icons/ody/skull.dds` сохраняется и виден в `/pa debug dump 5`; после `/reloadui` остаётся; ignore-игрок определяется (`/pa debug ignore`); merge/undo не теряет иконку.

### Этап 2 — наше окно

`browser.xml` (блок иконки), `browser.lua` (строка + панель), `iconpicker.xml/.lua`.

**DoD:** иконка выбирается мышью из сетки, сбрасывается, видна в строке списка; после релога на месте; пикер не плодит контролы при повторном открытии.

### Этап 3 — 2D в игре

`targetframe.lua`, `social.lua` (3 списка).

**DoD:** иконка в target frame; в друзьях, ростере и Ignored; длинные имена по-прежнему обрезаются, суффикс не ломается; при выключенном мастере исчезает везде.

### Этап 4 — мир (мост OSI)

`icons.lua`: детект OSI, `Apply`, подавление 2D, `RemoveAll`.

**DoD:** в группе иконка над головой появляется в пределах секунды; пропадает при выходе из группы; у цели вне группы есть 2D-иконка в рамке, а 3D там не делается по ограничению API; при снятии вручную возвращается прежняя иконка OSI; при выключенном мастере не остаётся ничего; без OSI всё работает в 2D.

### Этап 5 — настройки, язык, документация, релиз

`settings.lua`, `commands.lua`, `lang/*`, `DEVELOPMENT.md` §, `CHANGELOG.md`, README, версия `0.4.0` (манифест + `IRY.version` + `AddOnVersion: 400`).

---

## 7. Ассеты: что нужно

| Параметр | Значение |
|---|---|
| Формат | DDS, DXT5 (допустим DXT3), альфа-канал |
| Размер | 64×64, квадрат, 1 mipmap |
| Имя файла | `[a-z0-9_-]+\.dds`, без пробелов и кириллицы |
| Путь | `IRememberYou/icons/<pack>/<name>.dds` |
| Количество | 40–80 на старте |
| Заливка | ~90% кадра, чтобы в мире не выглядело мелко |
| Читаемость | силуэт должен читаться в 28 px |
| Анимация | нет |
| Лицензия | автор пака указан в `icons/CREDITS.md` + в README |

Иконки кладутся в репозиторий аддона, а не берутся по путям OSI: иначе без OSI наши 2D-иконки молча исчезнут.

---

## 8. Чек-лист живой проверки

1. `/script local z,x,y,zz = GetUnitRawWorldPosition("reticleover") d(z and "ok" or "nil")` — проверено: для цели вне группы приходит `0,0,0`, поэтому 3D над прицелом не делаем.
2. Иконка над членом группы: появляется, двигается с ним, масштабируется.
3. Цель вне группы: 2D-иконка в рамке есть, 3D-иконки нет — так и должно быть (ограничение API).
4. OSI включён/выключен, `customuse` вкл/выкл, `fluse`/`gruse` вкл/выкл.
5. Игрок с иконкой в LibCustomIcons: проверить, кто побеждает (`hodorprio` off/on).
6. Merged-игрок: иконка не «переезжает» к чужой записи.
7. UI-масштаб 100% / 150%, 4K: размеры в списках не разъезжаются.
8. BG/инстанс/другая зона: иконки группы не висят в пустоте.
9. `/reloadui` в группе: иконки восстанавливаются.
10. Удаление OSI из AddOns: аддон грузится, 2D работает, в чат/настройки выводится предупреждение, ошибок в `EO_LuaError` нет.

---

## 9. Чего не делаем

| | Почему |
|---|---|
| Свой 3D-рендер | дублирует OSI, ~200 строк и вечная поддержка камеры |
| Иконки в чате | визуальный шум; если OSI рисует — пусть рисует |
| Анимации | в 2D нечем показать, а через OSI — только LCI, куда писать нельзя |
| Запись в LibCustomIcons | API read-only |
| Своя вкладка «иконки» | хватает блока в панели деталей |
| Второе поле `icon3d` | OSI читает один слот; два поля дают противоречие |
| Управление размером мира | это настройка OSI, не наша |

---

## 10. Риски

| Риск | Как снижаем |
|---|---|
| `GetUnitRawWorldPosition("reticleover")` не работает | подтверждено: для не-групповых юнитов `0,0,0`; 3D над целью не делаем, остаётся 2D в рамке |
| OSI переименует методы | все вызовы через `pcall`, фича молча отключается, 2D живёт |
| OSI сохранит наши иконки в свой SV | сохраняем/возвращаем чужое, при выключении снимаем всё своё |
| Двойные иконки в списках | `OsiHandles2D` перед отрисовкой |
| Иконка есть, а файла нет | ESO молча рисует пустоту; лечится только манифестом + визуальной проверкой |
| Много файлов в архиве | курируем 40–80, а не все паки |
| Чужой аддон читает `special` иначе | не наша зона; документируем |

---

## 11. Открытые мелочи

1. Имя файла иконки blacklist по умолчанию — подобрать, когда будет набор (череп/крест/красный глаз).
2. Порог «иконка из blacklist» в нашем окне: показывать серую подпись `blacklist` и неактивный Clear — или разрешить назначить поверх? По текущему правилу ручная иконка приоритетнее, значит разрешить назначать поверх **надо**.
3. Нужен ли счётчик «сколько игроков с иконкой» на вкладке — не нужно, пока не попросят.
