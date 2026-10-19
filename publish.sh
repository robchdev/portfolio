#!/bin/sh
# Publishes this folder as the public site https://robchdev.github.io/portfolio/
cd "$(dirname "$0")" || exit 1
gh repo create robchdev/portfolio --public --source=. --push --description "robchdev: iOS and Mac app development" || exit 1
gh api -X POST repos/robchdev/portfolio/pages -f "source[branch]=main" -f "source[path]=/" >/dev/null && echo "Pages on: https://robchdev.github.io/portfolio/ (online in 1-2 minutes)"
