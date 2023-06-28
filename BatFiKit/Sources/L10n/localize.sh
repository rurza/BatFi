#!/bin/sh

#  localize.sh
#  NepTunes
#
#  Created by Adam on 26/03/2022.
#  Copyright © 2022 micropixels. All rights reserved.


if [ -z ${POE_API_TOKEN+x} ]; then
  echo "POE_API_TOKEN is unset";
  exit;
fi

PROJECT_ID="629883"
SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)

languages=("en" "pl" "ja")
for language in "${languages[@]}"
do
    mkdir $language.lproj
    poesie --token $POE_API_TOKEN --project $PROJECT_ID --lang $language --ios "$SCRIPT_DIR/$language.lproj/Localizable.strings"
done

if which swiftgen > /dev/null; then
  swiftgen
else
  echo "warning: SwiftGen not installed, download from https://github.com/SwiftGen/SwiftGen"
fi
