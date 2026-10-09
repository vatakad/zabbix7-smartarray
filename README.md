# HP Smart Array Monitoring for Zabbix 7.0

Мониторинг RAID-контроллеров HP Smart Array (P410, P222 и совместимые) через утилиту `ssacli` (или `hpssacli`/`hpacucli`) с отправкой данных в Zabbix через `zabbix_sender`.

---

## Содержание

1. [Возможности](#возможности)
2. [Состав пакета](#состав-пакета)
3. [Требования](#требования)
4. [Установка](#установка)
5. [Настройка Zabbix Agent](#настройка-zabbix-agent)
6. [Настройка Zabbix Server](#настройка-zabbix-server)
7. [Проверка работы](#проверка-работы)
8. [Как это работает](#как-это-работает)
9. [Макросы](#макросы)
10. [Триггеры](#триггеры)
11. [Решение проблем](#решение-проблем)
12. [Известные особенности](#известные-особенности)
13. [Файлы и пути](#файлы-и-пути)

---

## Возможности

- Автообнаружение (LLD) контроллеров, логических и физических дисков
- Мониторинг статуса контроллера, кэша, батареи/конденсатора (BBU)
- Мониторинг статуса логических томов (RAID-массивов)
- Мониторинг статуса и температуры физических дисков
- Отправка данных через `zabbix_sender` (item type `TRAP`)
- Поддержка нескольких контроллеров в одном хосте
- Совместимость с Zabbix 7.0

---

## Состав пакета

| Файл | Назначение |
|------|-----------|
| `hp-raid-data-processor.sh` | Сбор данных с контроллеров и отправка в Zabbix через `zabbix_sender` |
| `hp-raid-ctrl-discovery.sh` | LLD-скрипт для обнаружения контроллеров |
| `hp-raid-ld-discovery.sh` | LLD-скрипт для обнаружения логических томов |
| `hp-raid-pd-discovery.sh` | LLD-скрипт для обнаружения физических дисков |
| `hp-raid-smart-array.conf` | Конфигурация Zabbix Agent (`UserParameter`) |
| `hp-smart-array-template.xml` | Шаблон Zabbix для импорта |

---

## Требования

### На хосте с агентом

- Linux (проверено на Debian/Ubuntu)
- Zabbix Agent 7.0 или новее
- `zabbix_sender` (пакет `zabbix-sender`)
- Одна из утилит: `ssacli` (рекомендуется), `hpssacli` или `hpacucli`
- `bash`, `sed`, `awk`, `grep` (стандартные утилиты)
- Права `root` для установки

### На Zabbix Server

- Zabbix Server 7.0 или новее
- Импорт шаблона `hp-smart-array-template.xml`

---

## Установка

### Шаг 1. Установить утилиту ssacli

Скачайте `ssacli` с сайта HPE (HPE Smart Storage Administrator CLI) и установите:

```bash
# Пример для Debian/Ubuntu (файл .deb)
dpkg -i ssacli-*.deb

# Пример для RHEL/CentOS (файл .rpm)
rpm -ivh ssacli-*.rpm
```

Проверьте, что утилита доступна:

```bash
which ssacli
ssacli ctrl all show
```

### Шаг 2. Установить zabbix-sender

```bash
# Debian/Ubuntu
apt install zabbix-sender

# RHEL/CentOS
yum install zabbix-sender
```

Проверьте:

```bash
which zabbix_sender
```

### Шаг 3. Скопировать скрипты

```bash
mkdir -p /usr/local/bin/array
cp hp-raid-*.sh /usr/local/bin/array/
chmod +x /usr/local/bin/array/hp-raid-*.sh
chown root:root /usr/local/bin/array/hp-raid-*.sh
```

### Шаг 4. Установить конфиг агента

```bash
cp hp-raid-smart-array.conf /etc/zabbix/zabbix_agentd.d/
```

### Шаг 5. Перезапустить агент

```bash
systemctl restart zabbix-agent
```

### Шаг 6. Импортировать шаблон в Zabbix

1. Откройте веб-интерфейс Zabbix.
2. Перейдите в **Data collection → Templates**.
3. Нажмите **Import**.
4. Выберите файл `hp-smart-array-template.xml`.
5. Убедитесь, что в настройках импорта стоит **Update existing**.
6. Нажмите **Import**.

### Шаг 7. Привязать шаблон к хосту

1. Перейдите в **Data collection → Hosts**.
2. Выберите хост с агентом.
3. В поле **Templates** добавьте `HP-SmartArray-Template`.
4. Нажмите **Update**.

### Шаг 8. Настроить cron для сбора данных

Скрипт `hp-raid-data-processor.sh` должен запускаться регулярно (например, каждые 5 минут) для сбора свежих данных.

Откройте crontab:

```bash
crontab -e
```

Добавьте строку (запуск каждые 5 минут):

```cron
*/5 * * * * /usr/local/bin/array/hp-raid-data-processor.sh >/dev/null 2>&1
```

> **Важно:** discovery-скрипты работают с файлом `/tmp/hp-raid-data-harvester.out`, который создаётся основным скриптом. Если этот файл отсутствует, discovery вернёт ошибку.

---

## Настройка Zabbix Agent

В файле `/etc/zabbix/zabbix_agentd.conf` должны быть заданы параметры:

```ini
Server=192.168.1.100
ServerActive=192.168.1.100
Hostname=my-hp-server
```

Где:

- `Server` — адрес Zabbix Server (для пассивных проверок)
- `ServerActive` — адрес для активных проверок и `zabbix_sender`
- `Hostname` — имя хоста, которое должно совпадать с именем в Zabbix

> **Внимание:** имя хоста в конфиге агента (`Hostname`) должно точно совпадать с именем хоста в Zabbix. Иначе данные от `zabbix_sender` не будут приняты.

---

## Настройка Zabbix Server

### Проверка получения данных

После привязки шаблона:

1. Перейдите в **Monitoring → Latest data**.
2. Отфильтруйте по имени хоста.
3. Введите в поиск `hpraid`.
4. Вы должны увидеть items:
   - `hpraid.ctrl.status[0]`
   - `hpraid.cache.status[0]`
   - `hpraid.bbu.status[0]`
   - `hpraid.ld.status[0:1]`
   - `hpraid.pd.status[0:1I:1:1]`
   - `hpraid.pd.temperature[0:1I:1:1]`

Если данных нет — подождите 5 минут (цикл cron и discovery) или запустите скрипт вручную.

---

## Проверка работы

### Ручной запуск сбора данных

```bash
/usr/local/bin/array/hp-raid-data-processor.sh
```

### Проверка файла с данными

```bash
ls -la /tmp/hp-raid-data-harvester.out
grep -E '^### (ctrl|ld|pd) begin' /tmp/hp-raid-data-harvester.out
```

Пример вывода:

```
### ctrl begin 0 ###
### ld begin 0 1 ###
### ld begin 0 2 ###
### pd begin 0 1I:1:1 ###
### pd begin 0 1I:1:2 ###
```

### Проверка discovery-скриптов

```bash
/usr/local/bin/array/hp-raid-ctrl-discovery.sh
/usr/local/bin/array/hp-raid-ld-discovery.sh
/usr/local/bin/array/hp-raid-pd-discovery.sh
```

Пример вывода:

```json
{"data":[{"{#CTRL_SLOT}": "0"}]}
{"data":[{"{#LD}": "0:1"},{"{#LD}": "0:2"}]}
{"data":[{"{#PD}": "0:1I:1:1"},{"{#PD}": "0:1I:1:2"}]}
```

### Проверка через Zabbix Agent

```bash
zabbix_agentd -t hpraid.ctrl.discovery
zabbix_agentd -t hpraid.ld.discovery
zabbix_agentd -t hpraid.pd.discovery
zabbix_agentd -t 'hpraid.ctrl.status[0]'
zabbix_agentd -t 'hpraid.pd.status[0:1I:1:1]'
zabbix_agentd -t 'hpraid.pd.temperature[0:1I:1:1]'
```

### Проверка через zabbix_get (с сервера)

```bash
zabbix_get -s <agent_ip> -k 'hpraid.ctrl.status[0]'
zabbix_get -s <agent_ip> -k 'hpraid.pd.temperature[0:1I:1:1]'
```

---

## Как это работает

### Схема работы

```
+---------------------+     +---------------------------+     +----------------+
|  ssacli (HP CLI)    | --> | hp-raid-data-processor.sh | --> | zabbix_sender  |
+---------------------+     +---------------------------+     +----------------+
                                       |
                                       v
                        /tmp/hp-raid-data-harvester.out
                                       |
                                       v
                       +-------------------------------+
                       | hp-raid-*-discovery.sh (LLD)  |
                       +-------------------------------+
                                       |
                                       v
                              Zabbix Agent (UserParameter)
                                       |
                                       v
                                 Zabbix Server
```

### Пошагово

1. **Сбор данных.** Скрипт `hp-raid-data-processor.sh` вызывает `ssacli` и собирает информацию о контроллерах, логических и физических дисках. Результат сохраняется в файл `/tmp/hp-raid-data-harvester.out`.

2. **Формирование ключей.** Скрипт формирует список ключей Zabbix (например, `hpraid.pd.temperature[0:1I:1:1]`) на основе данных из файла.

3. **Извлечение значений.** Для каждого ключа скрипт извлекает значение из файла и формирует строку для `zabbix_sender`.

4. **Отправка.** `zabbix_sender` отправляет данные на Zabbix Server.

5. **LLD.** Discovery-скрипты вызываются Zabbix Agent по расписанию (каждые 300 секунд), парсят файл `/tmp/hp-raid-data-harvester.out` и возвращают JSON-список обнаруженных объектов.

6. **Создание items.** Zabbix Server автоматически создаёт items и триггеры для каждого обнаруженного объекта.

### Формат маркеров в файле

Файл `/tmp/hp-raid-data-harvester.out` содержит секции, разделённые маркерами:

```
### ctrl section begin ###
### ctrl begin 0 ###
... вывод ssacli ctrl slot=0 show ...
### ctrl end 0 ###
### ctrl section end ###

### ld section begin ###
### ld begin 0 1 ###
... вывод ssacli ctrl slot=0 ld 1 show ...
### ld end 0 1 ###
### ld section end ###

### pd section begin ###
### pd begin 0 1I:1:1 ###
... вывод ssacli ctrl slot=0 pd 1I:1:1 show ...
### pd end 0 1I:1:1 ###
### pd section end ###
```

Именно по этим маркерам работают discovery-скрипты и `UserParameter` в конфиге агента.

---

## Макросы

Шаблон использует следующие макросы:

| Макрос | Значение по умолчанию | Описание |
|--------|----------------------|----------|
| `{$HPRAID.PD.TEMP.MAX}` | `60` | Максимальная допустимая температура физического диска (°C) |
| `{$HPRAID.PD.TEMP.MIN}` | `0` | Минимальная допустимая температура физического диска (°C) |

Изменить макросы можно в настройках хоста или шаблона:

**Data collection → Hosts → <хост> → Macros**

---

## Триггеры

| Триггер | Severity | Условие |
|---------|----------|---------|
| Controller state is not OK | HIGH | `hpraid.ctrl.status[*]` не `OK` |
| Cache state is not OK | HIGH | `hpraid.cache.status[*]` не `OK` |
| BBU state is not OK | HIGH | `hpraid.bbu.status[*]` не `OK` |
| Logical volume state is not OK | HIGH | `hpraid.ld.status[*]` не `OK` |
| Physical drive state is not OK | HIGH | `hpraid.pd.status[*]` не `OK` |
| Physical drive temperature too high | WARNING | `hpraid.pd.temperature[*]` > `{$HPRAID.PD.TEMP.MAX}` |

> **Примечание:** триггеры срабатывают только если значение item не пустое (проверка через `length(last(...))`). Это исключает ложные срабатывания, когда данные ещё не получены или объект отсутствует.

---

## Решение проблем

### Проблема: discovery возвращает пустой список

**Симптом:**

```json
{"data":[]}
```

**Причина:** Формат данных не совпадает с regex в фильтре шаблона.

**Решение:**

1. Посмотрите реальный формат данных:
   ```bash
   /usr/local/bin/array/hp-raid-pd-discovery.sh
   ```
2. Если формат `{#PD}` отличается от `^[0-9]+:.+$`, обновите фильтр в шаблоне.

### Проблема: `ssacli, hpssacli or hpacucli not installed`

**Причина:** Утилита `ssacli` не найдена в `PATH`.

**Решение:**

```bash
which ssacli
# если пусто — установите ssacli
```

### Проблема: `zabbix_sender not installed`

**Причина:** Не установлен пакет `zabbix-sender`.

**Решение:**

```bash
apt install zabbix-sender   # Debian/Ubuntu
yum install zabbix-sender   # RHEL/CentOS
```

### Проблема: данные не приходят в Zabbix

**Причина:** `Hostname` в конфиге агента не совпадает с именем хоста в Zabbix.

**Решение:**

```bash
grep Hostname /etc/zabbix/zabbix_agentd.conf
```

Сравните с именем хоста в Zabbix UI (**Data collection → Hosts**). Они должны совпадать.

### Проблема: item `ZBX_NOTSUPPORTED`

**Причина:** Путь к скрипту в `UserParameter` неверный.

**Решение:**

```bash
grep UserParameter /etc/zabbix/zabbix_agentd.d/hp-raid-smart-array.conf
ls -la /usr/local/bin/array/
```

Убедитесь, что скрипты исполняемые (`chmod +x`) и находятся по указанным путям.

### Проблема: ошибка импорта шаблона `unknown function "strlen"`

**Причина:** Функция `strlen` не существует в Zabbix 7.0.

**Решение:** Используйте `length(last(...))`. В актуальной версии шаблона это уже исправлено.

### Проблема: ошибка импорта `incorrect usage of function "length"`

**Причина:** `length()` требует передачи значения, а не ключа.

**Решение:** Правильный синтаксис: `length(last(/host/key))`. В актуальной версии шаблона это уже исправлено.

---

## Известные особенности

### Формат физических дисков

В зависимости от модели контроллера и версии `ssacli`, физический диск может обозначаться по-разному:

- `0:1:1` — слот 0, порт 1, диск 1
- `0:1I:1:1` — слот 0, порт 1I, box 1, bay 1
- `0:2C:1:2` — слот 0, порт 2C, box 1, bay 2

Discovery-скрипты возвращают полный идентификатор, а фильтр шаблона `^[0-9]+:.+$` пропускает все варианты.

### Контроллер в слоте 0

На некоторых системах контроллер определяется как `Slot 0`, а не `Slot 1`. Это нормально — discovery вернёт `{#CTRL_SLOT} = "0"`, и все items будут созданы с этим значением.

### Запуск по cron

Скрипт `hp-raid-data-processor.sh` **не является** демоном. Его нужно запускать по расписанию (cron, systemd timer и т.п.). Рекомендуемый интервал — 5 минут.

### Файл `/tmp/hp-raid-data-harvester.out`

Файл создаётся при каждом запуске `hp-raid-data-processor.sh` и используется discovery-скриптами. Если файл отсутствует или устарел, discovery вернёт ошибку или пустой список. Убедитесь, что cron работает.

---

## Файлы и пути

| Путь | Назначение |
|------|-----------|
| `/usr/local/bin/array/hp-raid-data-processor.sh` | Основной скрипт сбора данных |
| `/usr/local/bin/array/hp-raid-ctrl-discovery.sh` | LLD контроллеров |
| `/usr/local/bin/array/hp-raid-ld-discovery.sh` | LLD логических томов |
| `/usr/local/bin/array/hp-raid-pd-discovery.sh` | LLD физических дисков |
| `/etc/zabbix/zabbix_agentd.d/hp-raid-smart-array.conf` | Конфиг агента |
| `/tmp/hp-raid-data-harvester.out` | Временный файл с данными |
| `/tmp/hp-raid-data-harvester.tmp` | Промежуточный файл |
| `/tmp/zabbix-sender-hp-raid-data.in` | Входной файл для `zabbix_sender` |
| `/tmp/keys` | Список ключей для отправки |

---

## Лицензия

Скрипты основаны на работе Lesovsky A.V. и Christoph Zimmermann. Свободно распространяются и модифицируются.

---

## Авторы оригинальной версии

- **Lesovsky A.V.** — оригинальные скрипты
- **Christoph Zimmermann** — доработки
- **Обновление для Zabbix 7.0 + ssacli** — адаптация под актуальные версии

---

## Changelog

### Версия для Zabbix 7.0 + ssacli

- Обновлены discovery-скрипты под формат `ssacli`
- Исправлены фильтры LLD в шаблоне (regex вместо пустого значения)
- Исправлен синтаксис триггеров: `length(last(...))` вместо `strlen(...)`
- Добавлены макросы `{$HPRAID.PD.TEMP.MAX}` и `{$HPRAID.PD.TEMP.MIN}`
- Добавлен триггер температуры физического диска
- Добавлены теги `Application` и `Component` для всех items и триггеров
- Исправлена отправка через `zabbix_sender`: приоритет `ServerActive` над `Server`
- Добавлена проверка наличия `zabbix_sender`
- Устойчивость discovery-скриптов к разному количеству пробелов в маркерах
- Поддержка разных форматов физических дисков (`0:1:1`, `0:1I:1:1`, `0:2C:1:2`)