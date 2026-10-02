#!/bin/sh
# Xcode Cloud：封存好、要送 TestFlight 的那一次，把最近幾次的提交寫成測試人員看到的「測試內容」（What to Test）。
# TestFlight/ 放在 .xcodeproj 旁邊，Xcode Cloud 會讀 WhatToTest.<語系>.txt（Apple 的做法）。
set -e

if [ -d "$CI_APP_STORE_SIGNED_APP_PATH" ]; then
  repo="$CI_PRIMARY_REPOSITORY_PATH"
  dir="$repo/TestFlight"
  mkdir -p "$dir"
  # Xcode Cloud 只抓最新的一個提交，往回多拿幾個
  git -C "$repo" fetch --deepen 8 >/dev/null 2>&1 || true
  notes=$(git -C "$repo" log -8 --no-merges --pretty=format:'・%s')
  {
    echo "版本 ${CI_BUILD_NUMBER}（${CI_BRANCH:-$CI_COMMIT}）"
    echo
    echo "$notes"
  } > "$dir/WhatToTest.zh-Hant.txt"
  cp "$dir/WhatToTest.zh-Hant.txt" "$dir/WhatToTest.en-US.txt"
fi
