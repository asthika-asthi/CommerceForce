from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from database import Base, engine
import models


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root():
    return {"message": "API running"}


@app.get("/api/health")
def health():
    return {"status": "ok", "message": "Backend is running"}


#for production
#allow_origins=[
#    "https://your-frontend-domain.com"
#]
# @app.get("/")
# def root():
#     return {"message": "API running"}