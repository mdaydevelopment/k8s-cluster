#!/usr/bin/env bash
# Wipes the live Minecraft Bedrock world (and its NAS backup copy) and lets
# the server regenerate a fresh one on restart. Destructive — asks for
# confirmation unless -y/--yes is passed.
set -euo pipefail

NAMESPACE="minecraft-bedrock"
DEPLOYMENT="minecraft-bedrock"
LEVEL_NAME="world"
ASSUME_YES=false

usage() {
  echo "Usage: $0 [-l|--level-name NAME] [-y|--yes]"
  echo "  -l, --level-name  World directory to wipe (default: world)"
  echo "  -y, --yes         Skip the confirmation prompt"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -l|--level-name) LEVEL_NAME="$2"; shift 2 ;;
    -y|--yes) ASSUME_YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

POD=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/controller="$DEPLOYMENT" -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD" ]; then
  echo "No running minecraft-bedrock pod found in namespace $NAMESPACE" >&2
  exit 1
fi

echo "This will permanently delete world '$LEVEL_NAME' from:"
echo "  - live data:   pod $POD:/data/worlds/$LEVEL_NAME"
echo "  - NAS backup:  pod $POD:/backup/worlds/$LEVEL_NAME"

if [ "$ASSUME_YES" != true ]; then
  read -r -p "Type the world name ('$LEVEL_NAME') to confirm: " CONFIRM
  if [ "$CONFIRM" != "$LEVEL_NAME" ]; then
    echo "Confirmation did not match, aborting." >&2
    exit 1
  fi
fi

kubectl exec -n "$NAMESPACE" "$POD" -c app -- rm -rf "/data/worlds/$LEVEL_NAME"
kubectl exec -n "$NAMESPACE" "$POD" -c app -- rm -rf "/backup/worlds/$LEVEL_NAME"

echo "Wiped. Restarting deployment to regenerate the world..."
kubectl rollout restart deployment/"$DEPLOYMENT" -n "$NAMESPACE"
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s

echo "Done. Tailing logs for the new world generation (ctrl-c to stop watching):"
NEW_POD=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/controller="$DEPLOYMENT" -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n "$NAMESPACE" "$NEW_POD" -c app -f
