# models/

Папка под 3D-модели. Пока пустая, подготовлена заранее.

Два способа подключить модель:

1. **По ID ассета Roblox** — впиши в `manifest.lua`: `name = { id = 123456789 }`.
2. **Свой файл** `.rbxm` / `.rbxmx` — положи сюда и впиши `name = { file = "models/name.rbxm" }`.
   Работает в режиме `Mode = "local"` (папка `ShitaroHub` в workspace инжектора, нужен `getcustomasset`).

Загрузка из кода модуля: `ctx.Loader.module("core/models.lua").load("name")`.
