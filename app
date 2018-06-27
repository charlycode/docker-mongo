#!/bin/bash
SCRIPT_DIR=$(cd -P "$( dirname "$0")" && pwd) && cd "$SCRIPT_DIR" || exit 1
ARG_REPLICAS="" && [ "$1" == "scale" ] && ARG_REPLICAS=$(echo "$*" | sed 's/.*scale //')
[ -f ./.env ] && source ./.env
export PROJECT STAGE REPLICAS SCRIPT_DIR
[ "$ARG_REPLICAS" ] && REPLICAS=$ARG_REPLICAS
[ ! "$PROJECT" ] && echo "Missing PROJECT=name on '.env' file" && exit 1
[ ! "$STAGE" ] && echo "Missing STAGE=stage on '.env' file" && exit 1


_check_docker_compose() {
  ! which docker-compose >/dev/null 2>&1 \
    && echo "Missing 'docker-compose' tool. Install first on path" \
    && exit 1
}
_check_docker_compose

_usage() {
  APP=$(basename "$0")
  echo
  echo "Usage: $APP <start|stop|restart|update|scale>"
  echo
  echo "      $APP update          Pull/build latest containers versions"
  echo "      $APP scale           Scale services, ex. '$APP scale nginx=2 php=3'"
  echo
  echo "    Special actions:"
  echo
  echo "      $APP reload          Send reload signals to containers"
  echo "      $APP logrotate       Run logrotate on host logs (servers only)"
  echo "      $APP install         Install crond files in /etc/cron.d"
  echo
  echo "Default STAGE can be set on '.env' file"
  echo
  exit 1
}
# Get action and validate
CMD="$1"
echo "$CMD" | grep -Eq '^(start|stop|restart|update|scale|start_exec)$' || _usage

# Get YAML and validate
echo "$STAGE" | grep -Eq '^(devel|beta|stable)$' || _usage
YAML="$STAGE.yml"
[ ! -f "$YAML" ] && echo "Missing '$YAML' fix '.env' file" && exit 1

# If devel, get host's IP address for XDEBUG
#if [ "$STAGE" = "devel" ]; then
#  IP=$(ifconfig | grep -E '(addr:192\.|addr:10\.)' | grep -Eo '[0-9\.]+' | head -n1)
#  IP2=$(ifconfig | grep -E '(inet.192\.|inet.10\.)' | grep -Eo '[0-9\.]+' | head -n1)
#  [ "$IP" ] && export XDEBUG_HOST=$IP
#  [ ! "$IP" ] && [ "$IP2" ] && export XDEBUG_HOST=$IP2
#  echo "Using XDEBUG_HOST=$XDEBUG_HOST"
#fi

# Run docker-compose
scale() {
  SCALES=$(echo "$REPLICAS" | sed -e 's/^ //' -e 's/ $//' -e 's/  / /g' -e 's/ / --scale /g' -e 's/^/--scale /')
  echo "Starting with REPLICAS=$REPLICAS"
  docker-compose -p "$PROJECT" -f "$YAML" up -d $SCALES 2>&1 | grep -Ev 'Found orphan|external, skipping'
}

update() {
  docker-compose -p "$PROJECT" -f "$YAML" pull
  grep -q 'build:' "$YAML" && docker-compose -f "$YAML" build --pull --force-rm
  UPDATE=1
}

stop() {
  docker-compose -p "$PROJECT" -f "$YAML" down 2>&1 | grep -Ev 'Found orphan|external, skipping'
}

start() {
  [ ! "$UPDATE" ] && update
  if [ "$REPLICAS" ]; then
    scale $REPLICAS
  else
    docker-compose --service-ports -p "$PROJECT" -f "$YAML" up -d 2>&1 | grep -Ev 'Found orphan|external, skipping'
  fi
}

start_exec() {
  [ ! "$UPDATE" ] && update
  if [ "$REPLICAS" ]; then
    scale $REPLICAS
  else
    docker-compose --service-ports -p "$PROJECT" -f "$YAML" up -d 2>&1 | grep -Ev 'Found orphan|external, skipping'
    docker exec -it backups bash -c "su linkaform"
  fi
}

restart() {
  update
  stop
  start
}

# Execute command
"$@"
