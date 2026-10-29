# INCY для iOS 12.5.8

VPN-клиент для iPhone 6 и других iPhone с архитектурой arm64. Минимальная
версия системы в проекте — iOS 12.5. Приложение написано на Swift/UIKit;
расширение `PacketTunnel` передаёт трафик через `hev-socks5-tunnel` в Xray.

## Что уже реализовано

- Профили VLESS, включая REALITY и Vision, VMess AEAD, Trojan,
  Shadowsocks/SS2022, SOCKS5 и HTTP-прокси.
- Импорт ссылок, списков ссылок, HTTPS-подписок и QR-кодов.
- Выбор, переименование и удаление профилей; хранение ключей в Keychain.
- Подключение VPN, счётчики трафика и выбор DNS-сервера.
- Отдельные цели Xcode для приложения и VPN-расширения.

## Сборка через GitHub Actions

1. Откройте [Actions → iOS Build](https://github.com/nabivkubkov-prog/VPN-IOS-12.5.8/actions/workflows/ios-build.yml).
2. Нажмите **Run workflow** и выберите ветку с исправлениями сборки:
   `codex/ios-github-build`, пока они не перенесены в `main`.
3. Дождитесь завершения запуска. Workflow проверяет Swift-профили и
   конфигурации Xray, собирает нативные библиотеки и архив приложения.
4. В разделе **Artifacts** скачайте `INCY-iOS-12.5.8-unsigned` и распакуйте
   ZIP. Внутри находится `INCY-iOS-12.5.8-unsigned.ipa` с VPN-расширением.

Запуск из GitHub CLI:

```powershell
gh workflow run ios-build.yml --repo nabivkubkov-prog/VPN-IOS-12.5.8 --ref codex/ios-github-build
gh run list --repo nabivkubkov-prog/VPN-IOS-12.5.8 --workflow ios-build.yml
```

IPA собирается без подписи. Для установки и работы VPN на обычном iPhone
нужно подписать приложение и расширение профилями Apple Developer с
возможностью Network Extensions и общей группой Keychain. На устройстве
с джейлбрейком способ установки зависит от используемого джейлбрейка.

## Локальная сборка на Mac

Нужны Xcode с iPhoneOS SDK и Go **1.22.12**. Версию Go фиксируем для
совместимости со старой iOS; обновлять её автоматически нельзя.

```bash
git clone --branch codex/ios-github-build --recurse-submodules https://github.com/nabivkubkov-prog/VPN-IOS-12.5.8.git
cd VPN-IOS-12.5.8
bash Scripts/check-macos.sh
```

В существующей копии проекта сначала выполните
`git submodule update --init --recursive`. Ревизия библиотеки туннеля
закреплена в Git; `Scripts/build-core.sh` проверяет её перед сборкой.

Для подписанной сборки задайте уникальный `INCY_BUNDLE_BASE` и свой
`DEVELOPMENT_TEAM` в `Config/Signing.xcconfig`, настройте подпись обеих
целей в Xcode и соберите схему `INCY`. Windows подходит для редактирования
проекта и запуска GitHub Actions; компиляция iOS выполняется на Mac.
