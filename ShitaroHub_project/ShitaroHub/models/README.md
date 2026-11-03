# models/

3D-модели.

- `angel_v1.pack` : модель «Ангел» для вкладки skins (меши Roblox, текстуры и превью в одном файле).
  Если модель обновить, называй новый файл `angel_v2.pack` и поменяй `PACK_PATH` / `PACK_NAME` в
  `modules/skins.lua`: так инжектор не возьмёт старую копию из кэша.
- `manifest.lua` и `core/models.lua` : общий помощник для моделей по ID ассета или файлу `.rbxm`.
  Вкладка skins им не пользуется, это заготовка на будущее.

Пересобрать `.pack` из `.glb`:
`python3 tools/build_angel_pack.py angel.glb front.png models/angel_v1.pack` (нужны numpy и Pillow).
