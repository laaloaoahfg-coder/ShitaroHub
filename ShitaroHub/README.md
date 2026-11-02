# ShitaroHub

Меню + ESP + камера + аимбот для Roblox, разбитое на папки и файлы. Запуск одной строкой через инжектор.

## Структура

```
ShitaroHub/
├── loader.lua        точка входа: качает и запускает остальное
├── core/
│   ├── ui.lua        окно, вкладки, настройки, палитра, курсор, выход
│   └── models.lua    помощник для 3D-моделей
├── modules/
│   ├── esp.lua       ESP: box, line, name, distance, skeleton, health
│   ├── camera.lua    FOV, третье лицо, свободная камера
│   └── aim.lua       аимбот и круг FOV
└── models/           папка под 3D-модели (manifest.lua + README)
```

## Запуск

Репозиторий: `laaloaoahfg-coder/ShitaroHub`, ветка `main`. Команда для инжектора:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/laaloaoahfg-coder/ShitaroHub/main/loader.lua"))()
```

Если репозиторий другой, поменяй `BASE_URL` в первых строках `loader.lua`.

## Загрузка на GitHub

Сохрани те же пути, что в структуре выше: `core/ui.lua`, `modules/esp.lua` и так далее. Через сайт: **Add file → Create new file**, в поле имени пиши путь с косой чертой (`core/ui.lua`), GitHub сам создаст папку. С компьютера можно перетащить папки целиком через **Upload files**.

## Локальный запуск (без интернета)

Положи папку в `workspace` инжектора под именем `ShitaroHub`:

```lua
getgenv().ShitaroConfig = { Mode = "local" }
loadstring(readfile("ShitaroHub/loader.lua"))()
```

## Как это устроено

`loader.lua` скачивает `core/ui.lua` и запускает его. Ядро строит общий контекст и по очереди загружает `esp`, `camera`, `aim`. Если один модуль не скачался или упал, остальные работают, а причина пишется в консоль через `warn`.

`core/ui.lua` остался одним файлом (около 3 100 строк): его части связаны десятками общих переменных.
