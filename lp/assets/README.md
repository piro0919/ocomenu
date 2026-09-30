# assets

`YujiSyuku-subset.ttf` is the brush face drawn into the Open Graph card
(`src/app/[locale]/opengraph-image.tsx`). It is the same face the site uses for
its title and item names, cut down to the characters the card actually shows.

Any character missing from it silently falls back to a different face, so when
the card's copy changes, rebuild the subset:

```sh
curl -sL -o /tmp/YujiSyuku-Regular.ttf \
  "https://github.com/google/fonts/raw/main/ofl/yujisyuku/YujiSyuku-Regular.ttf"

pyftsubset /tmp/YujiSyuku-Regular.ttf \
  --text="Ocomenu Finder's right-click menu, your way おこめにゅぅ Finder の右クリックを、自分のお品書きに" \
  --unicodes="U+0020-007E" \
  --output-file=assets/YujiSyuku-subset.ttf \
  --no-hinting --desubroutinize --layout-features=''
```
