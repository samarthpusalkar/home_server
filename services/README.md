## Services Folder

Put each custom service in its own directory:

- `services/<service-name>/Dockerfile`
- `services/<service-name>/requirements.txt` (or package manager file)
- `services/<service-name>/app code`

### Add A New Service

1. Create `services/<service-name>/`.
2. Add a service entry in `docker-compose.yml`.
3. Add Traefik labels with a path variable:
   - `traefik.http.routers.<service>.rule=Host(\`${PUBLIC_APP_HOST}\`) && PathPrefix(\`${<SERVICE>_PUBLIC_PATH}\`)`
4. Add `<SERVICE>_PUBLIC_PATH` to `.env` on the Pi if you want it public.
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
    - "traefik.http.routers.myservice.rule=Host(`${PUBLIC_APP_HOST}`) && PathPrefix(`${MYSERVICE_PUBLIC_PATH:-/myservice}`)"
    - "traefik.http.routers.myservice.entrypoints=web"
    - "traefik.http.routers.myservice.middlewares=myservice-strip"
    - "traefik.http.middlewares.myservice-strip.stripprefix.prefixes=${MYSERVICE_PUBLIC_PATH:-/myservice}"
    - "traefik.http.services.myservice.loadbalancer.server.port=8000"
```
