## Services Folder

Put each custom service in its own directory:

- `services/<service-name>/Dockerfile`
- `services/<service-name>/requirements.txt` (or package manager file)
- `services/<service-name>/app code`

### Add A New Service

1. Create `services/<service-name>/`.
2. Add a service entry in `docker-compose.yml`.
3. Add Traefik labels with a hostname variable:
   - `traefik.http.routers.<service>.rule=Host(\`${<SERVICE>_PUBLIC_HOST}\`)`
4. Add admin-discovery labels if you want the admin panel to control it automatically:
   - `homelab.admin.managed=true`
   - `homelab.admin.name=My Service`
   - `homelab.admin.exposure=traefik`
   - `homelab.admin.description=Short human-readable summary`
5. Add `<SERVICE>_PUBLIC_HOST` to `.env` on the Pi if you want it public. Use `example.com` placeholders in `.env.example` so the repo stays domain-agnostic.
6. Commit and push to `main`.

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
    - "traefik.http.routers.myservice.rule=Host(`${MYSERVICE_PUBLIC_HOST:-myservice.example.com}`)"
    - "traefik.http.routers.myservice.entrypoints=web"
    - "traefik.http.services.myservice.loadbalancer.server.port=8000"
    - "homelab.admin.managed=true"
    - "homelab.admin.name=My Service"
    - "homelab.admin.exposure=traefik"
    - "homelab.admin.description=Describe the service briefly"
```
