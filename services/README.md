## Services Folder

Put each custom service in its own directory:

- `services/<service-name>/Dockerfile`
- `services/<service-name>/requirements.txt` (or package manager file)
- `services/<service-name>/app code`

### Add A New Service

1. Create `services/<service-name>/`.
2. Add a service entry in `docker-compose.yml`.
3. Add Traefik labels with a hostname variable:
   - `traefik.http.routers.<service>.rule=Host(\`${<SERVICE>_HOST}\`)`
4. Add `<SERVICE>_HOST` to `.env` on the Pi.
5. Commit and push to `main`.

The deploy workflow will pull the repo on the Pi and run:

- `docker compose pull`
- `docker compose up -d --build --remove-orphans`

### Compose Snippet

```yaml
myservice:
  build: ./services/myservice
  container_name: myservice
  restart: unless-stopped
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.myservice.rule=Host(`${MYSERVICE_HOST:-myservice.example.com}`)"
    - "traefik.http.routers.myservice.entrypoints=web"
    - "traefik.http.services.myservice.loadbalancer.server.port=8000"
```

