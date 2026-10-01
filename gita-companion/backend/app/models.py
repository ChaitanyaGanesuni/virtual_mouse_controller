"""Import every module's models so Base.metadata is complete (Alembic, tests)."""

from app.core.db import Base
from app.modules.ai_tutor import models as ai_tutor
from app.modules.audio import models as audio
from app.modules.auth import models as auth
from app.modules.content import models as content
from app.modules.practice import models as practice
from app.modules.progress import models as progress
from app.modules.rag import models as rag
from app.modules.study import models as study

__all__ = ["Base", "ai_tutor", "audio", "auth", "content", "practice", "progress", "rag", "study"]
