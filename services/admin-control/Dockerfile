FROM python:3.12-slim

WORKDIR /app

COPY services/admin-control/requirements.txt .
RUN python -m pip install --no-cache-dir -r requirements.txt

COPY services/admin-control/app.py .
COPY services/admin-control/templates ./templates
COPY services/admin-control/static ./static
COPY config/admin-control/registry.seed.json ./registry.seed.json

EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
