# Maintainer: Philippe Matray <phmatray@gmail.com>
#
# macarchy-core is not shaped like the other packages in this org: most of what
# install.sh lands is USER CONFIGURATION -- theme hooks, shell plugins, a Hypr
# key file -- which pacman cannot write. So the package splits honestly:
#
#   system half  -> /usr/bin, /usr/lib/systemd/user, /usr/lib/udev/rules.d
#   user half    -> /usr/share/macarchy-core/, as templates the scriptlet names
#
# It is deliberately NOT a full install. The scriptlet says so and names every
# destination, rather than shipping something that looks complete and is not.
pkgname=macarchy-core
# Rewritten from the tag by the packaging job before makepkg runs. This value is
# the fallback for a manual makepkg from a checkout.
pkgver=0.4.1
pkgrel=1
pkgdesc="macOS behaviours for a MacBook on Omarchy/Asahi: dock, Cmd keys, Cmd+Tab, pinch gestures, auto-brightness"
arch=('any')
url="https://github.com/macarchy/macarchy-core"
license=('MIT')
install=macarchy-core.install
depends=('bash' 'python' 'brightnessctl')
optdepends=('omarchy: the theme hooks and shell plugins target it'
            'grim: bar-contrast samples the screen with it'
            'imagemagick: bar-contrast reduces the sample with it'
            'jq: reading the bar layer geometry'
            'hyprland: the gestures and key grammar')
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP')

package() {
  cd "$srcdir/$pkgname-$pkgver"

  # --- the system half ------------------------------------------------------
  local s
  for s in style/* hardware/*; do
    [[ -f $s && -x $s ]] || continue
    install -Dm755 "$s" "$pkgdir/usr/bin/$(basename "$s")"
  done

  # The units say ExecStart=%h/.local/bin/… because install.sh symlinks there.
  # A package writes nothing into $HOME: verbatim they give 203/EXEC from a
  # package that installed perfectly.
  local u
  for u in systemd/*.service; do
    sed 's|%h/\.local/bin/|/usr/bin/|' "$u" > "$srcdir/$(basename "$u").pkg"
    grep -q '^ExecStart=/usr/bin/' "$srcdir/$(basename "$u").pkg"   # or fail the build
    install -Dm644 "$srcdir/$(basename "$u").pkg" \
      "$pkgdir/usr/lib/systemd/user/$(basename "$u")"
  done
  for u in systemd/*.timer; do
    install -Dm644 "$u" "$pkgdir/usr/lib/systemd/user/$(basename "$u")"
  done

  install -Dm644 udev/90-battery-charge-limit.rules \
    "$pkgdir/usr/lib/udev/rules.d/90-battery-charge-limit.rules"

  # --- the user half, as templates -----------------------------------------
  # Every one of these belongs somewhere under $HOME that pacman may not touch.
  # macarchy-core.install names each destination.
  install -d "$pkgdir/usr/share/$pkgname"
  cp -r hooks keys examples shell-plugins "$pkgdir/usr/share/$pkgname/"
  cp -r agents "$pkgdir/usr/share/$pkgname/"

  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
}
