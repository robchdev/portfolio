#!/bin/sh
# Publishes this folder as the public site https://robchdev.github.io/studio/
cd "$(dirname "$0")" || exit 1
gh repo create robchdev/studio --public --source=. --push --description "robchdev: iOS and Mac app development" || exit 1
gh api -X POST repos/robchdev/studio/pages -f "source[branch]=main" -f "source[path]=/" >/dev/null && echo "Pages on: https://robchdev.github.io/studio/ (online in 1-2 minutes)"
