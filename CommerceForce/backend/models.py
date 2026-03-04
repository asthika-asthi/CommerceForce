from sqlalchemy import Column, Integer, String, Boolean
from database import Base, engine


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    is_admin = Column(Boolean, default=False)