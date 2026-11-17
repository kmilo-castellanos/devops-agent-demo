#!/usr/bin/env bash
# Crea una rama con una regresión "sutil": un refactor que elimina la validación
# de cupones expirados. Los tests unitarios siguen pasando; el release testing la detecta.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
BRANCH="feature/coupon-refactor"
git checkout main
git checkout -B "$BRANCH"
git apply -p1 demo/regression.patch
git commit -am "refactor: simplify coupon validation"
git push -u origin "$BRANCH" --force-with-lease
echo
echo "Abre el PR: https://github.com/$(git remote get-url origin | sed -E 's#.*github.com[:/](.*)\.git#\1#; s#.*github.com[:/](.*)#\1#')/compare/main...$BRANCH?expand=1"
