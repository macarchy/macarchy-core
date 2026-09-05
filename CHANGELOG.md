# Changelog

## [0.6.0](https://github.com/macarchy/macarchy-core/compare/v0.5.0...v0.6.0) (2026-09-05)


### Features

* **agents:** a Claude Code status line that follows the Omarchy theme ([#16](https://github.com/macarchy/macarchy-core/issues/16)) ([4d50566](https://github.com/macarchy/macarchy-core/commit/4d50566ea56991c5601c92fefc1bf3b8cf43d340))

## [0.5.0](https://github.com/macarchy/macarchy-core/compare/v0.4.1...v0.5.0) (2026-09-04)


### Features

* **pkg:** publish an installable package on every release ([#14](https://github.com/macarchy/macarchy-core/issues/14)) ([fed49d7](https://github.com/macarchy/macarchy-core/commit/fed49d7922574333891c5991160144bdc628167c))

## [0.4.1](https://github.com/macarchy/macarchy-core/compare/v0.4.0...v0.4.1) (2026-09-04)


### Bug Fixes

* a deliberate no-op exits 0, not 1 ([#12](https://github.com/macarchy/macarchy-core/issues/12)) ([2099698](https://github.com/macarchy/macarchy-core/commit/2099698d0b3778c4197e4801304cc4bffda0e535))

## [0.4.0](https://github.com/macarchy/macarchy-core/compare/v0.3.0...v0.4.0) (2026-09-04)


### ⚠ BREAKING CHANGES

* rename to macarchy-core and move commands out of the omarchy-* namespace

### Bug Fixes

* **changelog:** restore the three entry texts to their commit subjects ([4c21e88](https://github.com/macarchy/macarchy-core/commit/4c21e8814784981891be918a8c57b6e92922a8c7))
* **rename:** restore macos-dynamic-wallpaper and the dated design docs ([0e711f7](https://github.com/macarchy/macarchy-core/commit/0e711f7892debaf1607b796764dff2681ba9a217))


### Code Refactoring

* rename to macarchy-core and move commands out of the omarchy-* namespace ([17fb52d](https://github.com/macarchy/macarchy-core/commit/17fb52dbd8e48cbf43bd23f7ad53edb1cf8ca153))

## [0.3.0](https://github.com/macarchy/macarchy-core/compare/v0.2.1...v0.3.0) (2026-09-04)


### Features

* notify when the appearance and contrast jobs fail ([#9](https://github.com/macarchy/macarchy-core/issues/9)) ([8b040c6](https://github.com/macarchy/macarchy-core/commit/8b040c6ed5573b27de18305bae83dd0f56b757ff))


### Bug Fixes

* create ~/.config/hypr before installing into it ([#8](https://github.com/macarchy/macarchy-core/issues/8)) ([c4a190c](https://github.com/macarchy/macarchy-core/commit/c4a190c29f719db5ad8992d9377a900c44c1d762))

## [0.2.1](https://github.com/macarchy/macarchy-core/compare/v0.2.0...v0.2.1) (2026-09-04)


### Bug Fixes

* **bar-contrast:** follow the aquarium, not just the theme and the clock ([#5](https://github.com/macarchy/macarchy-core/issues/5)) ([ad2f90b](https://github.com/macarchy/macarchy-core/commit/ad2f90b487fd96ff29b4f2b1b46404b91d5767e6))

## [0.2.0](https://github.com/macarchy/macarchy-core/compare/v0.1.0...v0.2.0) (2026-09-04)


### Features

* **als:** report the paused state in status ([2849e22](https://github.com/macarchy/macarchy-core/commit/2849e221657305f4a6f3ca22ffc017ad6cc7920b))
* **appearance:** 5-minute timer, example conf, enable on first install only ([b956970](https://github.com/macarchy/macarchy-core/commit/b9569707de402eb53990bceb6dff77a48cd855b4))
* **appearance:** follow the sun by default, add status ([f4d5e2b](https://github.com/macarchy/macarchy-core/commit/f4d5e2bba4c0bc943c477cca4624e6ba85b382c3))
* **bar-contrast:** add omarchy-bar-contrast — pick the transparent bar's text colour from the screen ([217884f](https://github.com/macarchy/macarchy-core/commit/217884f854089df9ba830463f0fc77a8927731c9))
* **control-center:** a shell that hosts modules, and a home worth looking at ([c0c7cf5](https://github.com/macarchy/macarchy-core/commit/c0c7cf530da4fa0279e3250cf39b6de59e29ab27))
* **control-center:** Apparence — assemble your own Jarvis ([1c4f67e](https://github.com/macarchy/macarchy-core/commit/1c4f67ec0d75997aa5c2405ecee727c8b44d06b2))
* **control-center:** Auto appearance follows the sun, with a Détecter button ([5ac7c49](https://github.com/macarchy/macarchy-core/commit/5ac7c49962e3bb04f133ac1a431acad1dbd3d361))
* **control-center:** Jarvis status banner, automations, suggestion inbox ([44f2d56](https://github.com/macarchy/macarchy-core/commit/44f2d560b3507e6f91ac775f944cc80edf78e777))
* **control-center:** what Jarvis does when the microphone is muted ([26aa7ee](https://github.com/macarchy/macarchy-core/commit/26aa7ee6c3eac82277a569f639504f58ad43c191))
* **control-center:** write to Jarvis from the status banner ([5232018](https://github.com/macarchy/macarchy-core/commit/5232018a80b80020f8ce389bebd8dd885c86351f))
* **dfr:** a 'jarvis' button type that wears the assistant's state ([7ee6f28](https://github.com/macarchy/macarchy-core/commit/7ee6f2852e008c758ca4c6b54f30f76722bbf4bc))
* **dfr:** a Babel fish button — one tap talks to Jarvis ([858c46a](https://github.com/macarchy/macarchy-core/commit/858c46a8431dd27d49d2c55fd4aead69f339ada5))
* **hypr:** Cmd-key grammar and the Cmd+Tab app switcher ([eb5430e](https://github.com/macarchy/macarchy-core/commit/eb5430e9eb015d0609d7a208ea21a191b802e989))
* **icons:** bring the hand-drawn Touch Bar SVGs into the repo ([2376f69](https://github.com/macarchy/macarchy-core/commit/2376f69ac46010add30afbdf219380e89426d926))
* **libinput:** ship the measured libinput thresholds for the MTP trackpad ([f27c8ad](https://github.com/macarchy/macarchy-core/commit/f27c8ada6df4d1e13f6e2a0a3538eedf20deb5da))
* **locate:** add omarchy-locate — IP geolocation into the shared location ([b6e094b](https://github.com/macarchy/macarchy-core/commit/b6e094bfcd28c9882d515bc425a33a97b6c2193f))
* **shell-plugins:** bring the Control Center and Notification Center under version control ([cdb0458](https://github.com/macarchy/macarchy-core/commit/cdb045829873d700c250e541c9c5f5e3006bd43b))
* **sun:** add omarchy-sun — sunrise and sunset for the shared location ([d80d7f3](https://github.com/macarchy/macarchy-core/commit/d80d7f3d6b5ba22ca9e2e95bf933dc9d3f9398bf))


### Bug Fixes

* **control-center:** an abort reads as an abort, and the ears settle on the way out ([834a024](https://github.com/macarchy/macarchy-core/commit/834a0249b92b5147127f0c33bd3d830b0c91dd96))
* **control-center:** reserve two label lines on every quick tile ([8ec7b38](https://github.com/macarchy/macarchy-core/commit/8ec7b381f892fefbafb45805f7ea44c1b20d55bf))
* **control-center:** say what the Langue pills actually control ([d129753](https://github.com/macarchy/macarchy-core/commit/d1297535eec9f02a91b480f621b700003e3ad8a5))
* **control-center:** smoother Jarvis page scrolling ([29dcaf6](https://github.com/macarchy/macarchy-core/commit/29dcaf651a337f82f67ad82035a433798cc0f6d7))
* **control-center:** the Apparence tile leaves Auto mode ([1d12320](https://github.com/macarchy/macarchy-core/commit/1d123209e2d4afea0f57ff82f471c48ccd8d88d3))
* **control-center:** touchpad scrolling at finger speed on the Jarvis page ([b28ee0b](https://github.com/macarchy/macarchy-core/commit/b28ee0b1967b8af731dfe5656d1475f47ae7da9e))
* **control-center:** truthful probes and readable pills ([81990a2](https://github.com/macarchy/macarchy-core/commit/81990a2ca799153f47d2600ed0911cc79c40475c))
* final-review fixes — solar guard validation, locate coordinate check, module refresh wiring ([109b3de](https://github.com/macarchy/macarchy-core/commit/109b3deb68a007c5c7ae896f40e3f37c977f1967))
* **install:** skip the __pycache__ directories when installing scripts ([a639180](https://github.com/macarchy/macarchy-core/commit/a6391808a04baade3da0697e8552dff4cf7744aa))
* **locate:** keep the config file's mode across the atomic write ([67a62e7](https://github.com/macarchy/macarchy-core/commit/67a62e7071ba6be3670e27f526cdd4db88711364))
* **notification-center:** touchpad scrolling at finger speed ([2a6ef11](https://github.com/macarchy/macarchy-core/commit/2a6ef11212e04f188a3d5d95f0e0bf36c961c005))
* **shell-plugins:** secondary text at 0.68 alpha in Control Center and Notification Center ([7e4bbec](https://github.com/macarchy/macarchy-core/commit/7e4bbec93015e66ebfc41f819d725b91020877e6))
