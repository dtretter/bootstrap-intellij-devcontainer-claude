#!/bin/bash
cd "$(dirname "$0")"
docker compose -f .devcontainer/docker-compose.yml exec app bash