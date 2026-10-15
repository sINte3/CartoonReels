# CartoonReels — рабочий 2D-риг и проба движения

Remotion 4.0.535, React 19.2.3, TypeScript. Все рисунки сцены созданы в SVG-коде проекта; внешние генеративные API и материалы не использовались.

## Подготовка в облаке

Рабочая директория: `/workspace/CartoonReels/animation`.

```bash
bash scripts/cloud-runtime.sh npm ci --no-audit --no-fund
bash scripts/cloud-runtime.sh npm run lint
bash scripts/cloud-runtime.sh ./node_modules/.bin/remotion compositions src/index.ts
```

Нужны Node.js 24, установленный Chromium `/usr/bin/chromium` и FFmpeg. Они уже есть в текущем образе. `cloud-runtime.sh` настраивает записываемые XDG-каталоги и поддержку прокси в Node, сохраняя системную проверку TLS. HOME и секреты не меняются.

В `remotion.config.ts` выбран установленный браузер и режим `chrome-for-testing`: его современный headless-интерфейс проверен с Chromium 154. Название режима не означает, что скачивается другой браузер. Проверка `chromium --dump-dom` здесь непригодна; готовность проверяется через Remotion и реальную композицию. Политики браузера и проверка сертификатов не отключались.

## Студия

```bash
bash scripts/cloud-runtime.sh npm run dev -- --no-open --port=3000
```

Сервис — отдельный живой процесс; после восстановления среды его надо запустить снова. В onboarding не выдавать пользователю localhost как работающий веб-предпросмотр. Внутренняя HTTP-проверка: `curl -fsS http://127.0.0.1:3000/`. Она проверяет сервис; отдельная команда `remotion compositions` и успешный рендер проверяют саму композицию.

## Результаты

- `CharacterSheet`: 2400×1600, шесть выражений/поз, рабочий дизайн.
- `TailStudy`: 1080×1920, 24 fps, восемь секунд, без звука. Хвост дотягивается до щётки, удерживает и наклоняет её; хозяин реагирует.
- Это техническая проба героя и движения. Сюжет EP001 «Чисто!» целиком ещё не собран.

```bash
bash scripts/cloud-runtime.sh ./node_modules/.bin/remotion still src/index.ts CharacterSheet out/hero-poses.png
bash scripts/cloud-runtime.sh ./node_modules/.bin/remotion still src/index.ts TailStudy out/tail-contact.png --frame=82
bash scripts/cloud-runtime.sh ./node_modules/.bin/remotion render src/index.ts TailStudy out/tail-study-8s.mp4 --codec=h264 --crf=20 --concurrency=2
```

Сгенерированные файлы находятся в игнорируемом `out/`. Результаты технической проверки и SHA-256 записаны в `out/validation.json`. Просмотр отдельных кадров и полное декодирование не заменяют оценку движения человеком в реальном времени. Звука в этой пробе нет намеренно.

## Сохранность и ограничения

Использовать существующий checkout; Git worktree без прямого запроса не создавать. Исходники и lockfile входят в этот репозиторий. Рабочий `out/` игнорируется; небольшой зафиксированный набор первой пробы и архив для скачивания находятся в `../deliverables/study-01/`. Большой постоянный архив будущих медиа ещё не настроен. Успешное восстановление и запуск в новой задаче пока не проверялись.

Платные генерации, расход внешних генеративных квот, публикации роликов в соцсетях и новые платные ресурсы по-прежнему не разрешены. Передача готовых файлов в этот GitHub-репозиторий отдельно разрешена пользователем независимо от его видимости. Эти команды выполняют сборку кодовой анимации в имеющейся среде. Для использования Remotion соблюдать [его лицензию](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md).
