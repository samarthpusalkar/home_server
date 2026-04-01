from fastapi import FastAPI

app = FastAPI(title="template-python-service")


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}

