# WGM

Система управления WG/AWG-VPN на Elixir/OTP.

Срез 1 (ядро): доменная модель, генерация конфигов, валидация AWG-лимитов,
генерация ключей и парсеры `wg show dump` / `awg show dump`.

## Тесты

```bash
mix test
```

## Демо

```bash
mix run scripts/generate_config_demo.exs
```
