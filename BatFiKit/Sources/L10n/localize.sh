#!/bin/sh

#  localize.sh
#  NepTunes
#
#  Created by Adam on 26/03/2022.
#  Copyright © 2022 micropixels. All rights reserved.


if which texterify > /dev/null; then
  texterify download
else
  echo "warning: Texterify not installed, download from https://github.com/txty-io/txty-cli"
fi

if which swiftgen > /dev/null; then
  swiftgen
else
  echo "warning: SwiftGen not installed, download from https://github.com/SwiftGen/SwiftGen"
fi
