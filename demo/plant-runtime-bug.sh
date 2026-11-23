#!/usr/bin/env bash
# D1: introduce un bug de ejecución en el checkout (TypeError -> HTTP 500).
# Los tests unitarios siguen pasando. Después: ./demo/deploy.sh <sha> y provoca el error en la UI/API.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
BRANCH="feature/order-label"
git checkout main
git checkout -B "$BRANCH"
git apply -p1 demo/runtime-bug.patch
git commit -am "feat: add fulfilment label to orders"
git push -u origin "$BRANCH" --force-with-lease
SHA="$(git rev-parse HEAD)"
echo
echo "Cuando Actions publique la imagen: ./demo/deploy.sh $SHA"
echo "Provocar el error: curl -XPOST \$URL/api/orders -H 'content-type: application/json' \\"
echo "  -d '{\"items\":[{\"id\":\"p1\",\"qty\":1}],\"email\":\"a@b.co\"}'"
