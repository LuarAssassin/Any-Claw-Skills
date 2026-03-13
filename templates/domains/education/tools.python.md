# Education Domain: Python Tool Implementations

Tool functions for the education domain using Pydantic models and async patterns.
Provides learning path generation, flashcard creation, quiz engine, and knowledge base CRUD.

## Generated File: `tools/education_tools.py`

```python
"""Education domain tools for {{PROJECT_NAME}}.

Provides learning path generation, flashcard creation, quiz generation,
and knowledge base management with async interfaces and Pydantic validation.
"""

from __future__ import annotations

import hashlib
import json
import uuid
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class Difficulty(str, Enum):
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    ADVANCED = "advanced"


class QuestionType(str, Enum):
    MULTIPLE_CHOICE = "multiple_choice"
    SHORT_ANSWER = "short_answer"
    TRUE_FALSE = "true_false"


class KBAction(str, Enum):
    CREATE = "create"
    READ = "read"
    UPDATE = "update"
    DELETE = "delete"


class BloomLevel(str, Enum):
    REMEMBER = "remember"
    UNDERSTAND = "understand"
    APPLY = "apply"
    ANALYZE = "analyze"
    EVALUATE = "evaluate"
    CREATE = "create"


# ---------------------------------------------------------------------------
# Models -- Learning Path
# ---------------------------------------------------------------------------

class Milestone(BaseModel):
    title: str
    description: str
    duration_days: int = Field(ge=1)
    resources: list[str] = Field(default_factory=list)
    objectives: list[str] = Field(default_factory=list)


class LearningPlan(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    subject: str
    level: Difficulty
    goals: list[str]
    milestones: list[Milestone]
    total_duration_days: int = 0
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )

    def model_post_init(self, __context: Any) -> None:
        self.total_duration_days = sum(m.duration_days for m in self.milestones)


# ---------------------------------------------------------------------------
# Models -- Flashcards
# ---------------------------------------------------------------------------

class Flashcard(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:8])
    front: str
    back: str
    difficulty: Difficulty
    tags: list[str] = Field(default_factory=list)
    next_review: str | None = None


class Flashcards(BaseModel):
    topic: str
    cards: list[Flashcard]
    count: int = 0

    def model_post_init(self, __context: Any) -> None:
        self.count = len(self.cards)


# ---------------------------------------------------------------------------
# Models -- Quiz
# ---------------------------------------------------------------------------

class Choice(BaseModel):
    label: str
    text: str
    is_correct: bool = False


class Question(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:8])
    text: str
    question_type: QuestionType
    choices: list[Choice] = Field(default_factory=list)
    correct_answer: str
    explanation: str = ""
    bloom_level: BloomLevel = BloomLevel.REMEMBER


class Quiz(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    topic: str
    questions: list[Question]
    total_points: int = 0
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )

    def model_post_init(self, __context: Any) -> None:
        self.total_points = len(self.questions)


# ---------------------------------------------------------------------------
# Models -- Knowledge Base
# ---------------------------------------------------------------------------

class KBEntry(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    topic: str
    content: str
    tags: list[str] = Field(default_factory=list)
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    updated_at: str = ""


class KBResult(BaseModel):
    action: KBAction
    success: bool
    entry: KBEntry | None = None
    message: str = ""


# ---------------------------------------------------------------------------
# Storage backend (file-based, swappable)
# ---------------------------------------------------------------------------

class _Store:
    """Simple JSON file store for knowledge base entries."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._path.mkdir(parents=True, exist_ok=True)

    def _file(self, topic: str) -> Path:
        slug = hashlib.sha256(topic.lower().encode()).hexdigest()[:16]
        return self._path / f"{slug}.json"

    async def save(self, entry: KBEntry) -> None:
        self._file(entry.topic).write_text(entry.model_dump_json(indent=2))

    async def load(self, topic: str) -> KBEntry | None:
        f = self._file(topic)
        if not f.exists():
            return None
        return KBEntry.model_validate_json(f.read_text())

    async def delete(self, topic: str) -> bool:
        f = self._file(topic)
        if f.exists():
            f.unlink()
            return True
        return False


_store = _Store(Path("{{DATA_DIR}}") / "knowledge_base")


# ---------------------------------------------------------------------------
# Tool: learning_path
# ---------------------------------------------------------------------------

async def learning_path(
    subject: str,
    level: str,
    goals: list[str],
) -> LearningPlan:
    """Generate a personalized learning path.

    Args:
        subject: The subject or topic area (e.g. "linear algebra").
        level: Learner level -- "beginner", "intermediate", or "advanced".
        goals: List of learning objectives the student wants to achieve.

    Returns:
        A LearningPlan with ordered milestones and estimated durations.
    """
    difficulty = Difficulty(level.lower())

    duration_map = {
        Difficulty.BEGINNER: 7,
        Difficulty.INTERMEDIATE: 10,
        Difficulty.ADVANCED: 14,
    }
    base_days = duration_map[difficulty]

    milestones: list[Milestone] = []
    for i, goal in enumerate(goals, start=1):
        milestones.append(
            Milestone(
                title=f"Milestone {i}: {goal}",
                description=f"Work toward: {goal}",
                duration_days=base_days,
                resources=[
                    f"{{{{RESOURCE_BASE_URL}}}}/{subject.lower().replace(' ', '-')}/m{i}"
                ],
                objectives=[goal],
            )
        )

    return LearningPlan(
        subject=subject,
        level=difficulty,
        goals=goals,
        milestones=milestones,
    )


# ---------------------------------------------------------------------------
# Tool: flashcard_generator
# ---------------------------------------------------------------------------

async def flashcard_generator(
    topic: str,
    count: int = 10,
    difficulty: str = "intermediate",
) -> Flashcards:
    """Create flashcards for a given topic.

    Args:
        topic: Subject or concept to create cards for.
        count: Number of flashcards to generate (1..50).
        difficulty: Card difficulty -- "beginner", "intermediate", or "advanced".

    Returns:
        A Flashcards collection ready for spaced-repetition review.
    """
    count = max(1, min(count, 50))
    diff = Difficulty(difficulty.lower())

    cards: list[Flashcard] = []
    for i in range(count):
        cards.append(
            Flashcard(
                front=f"[{topic}] Question {i + 1} ({{{{LLM_GENERATED_FRONT}}}})",
                back=f"Answer {i + 1} ({{{{LLM_GENERATED_BACK}}}})",
                difficulty=diff,
                tags=[topic.lower()],
            )
        )

    return Flashcards(topic=topic, cards=cards)


# ---------------------------------------------------------------------------
# Tool: quiz_engine
# ---------------------------------------------------------------------------

async def quiz_engine(
    topic: str,
    count: int = 5,
    question_type: str = "multiple_choice",
) -> Quiz:
    """Generate quiz questions for assessment.

    Args:
        topic: Subject area for the quiz.
        count: Number of questions (1..30).
        question_type: One of "multiple_choice", "short_answer", "true_false".

    Returns:
        A Quiz with questions, choices (if applicable), and correct answers.
    """
    count = max(1, min(count, 30))
    q_type = QuestionType(question_type.lower())

    questions: list[Question] = []
    for i in range(count):
        choices: list[Choice] = []
        correct = f"{{{{LLM_GENERATED_ANSWER_{i + 1}}}}}"

        if q_type == QuestionType.MULTIPLE_CHOICE:
            choices = [
                Choice(label="A", text=f"Option A ({{{{LLM_OPTION_A_{i + 1}}}}})"),
                Choice(label="B", text=f"Option B ({{{{LLM_OPTION_B_{i + 1}}}}})"),
                Choice(label="C", text=f"Option C ({{{{LLM_OPTION_C_{i + 1}}}}})"),
                Choice(label="D", text=f"Option D ({{{{LLM_OPTION_D_{i + 1}}}}})", is_correct=True),
            ]
            correct = "D"
        elif q_type == QuestionType.TRUE_FALSE:
            choices = [
                Choice(label="T", text="True"),
                Choice(label="F", text="False", is_correct=True),
            ]
            correct = "F"

        questions.append(
            Question(
                text=f"[{topic}] Question {i + 1} ({{{{LLM_GENERATED_QUESTION_{i + 1}}}}})",
                question_type=q_type,
                choices=choices,
                correct_answer=correct,
                explanation=f"{{{{LLM_GENERATED_EXPLANATION_{i + 1}}}}}",
                bloom_level=BloomLevel.UNDERSTAND,
            )
        )

    return Quiz(topic=topic, questions=questions)


# ---------------------------------------------------------------------------
# Tool: knowledge_base
# ---------------------------------------------------------------------------

async def knowledge_base(
    action: str,
    topic: str,
    content: str = "",
) -> KBResult:
    """CRUD operations on the knowledge base.

    Args:
        action: One of "create", "read", "update", "delete".
        topic: The topic key for the knowledge entry.
        content: Content body (required for create/update, ignored for read/delete).

    Returns:
        KBResult indicating success/failure and the affected entry.
    """
    act = KBAction(action.lower())

    if act == KBAction.CREATE:
        existing = await _store.load(topic)
        if existing:
            return KBResult(action=act, success=False, message=f"Entry already exists for '{topic}'. Use 'update' instead.")
        entry = KBEntry(topic=topic, content=content, tags=[topic.lower()])
        await _store.save(entry)
        return KBResult(action=act, success=True, entry=entry, message="Entry created.")

    if act == KBAction.READ:
        entry = await _store.load(topic)
        if not entry:
            return KBResult(action=act, success=False, message=f"No entry found for '{topic}'.")
        return KBResult(action=act, success=True, entry=entry)

    if act == KBAction.UPDATE:
        entry = await _store.load(topic)
        if not entry:
            return KBResult(action=act, success=False, message=f"No entry found for '{topic}'. Use 'create' first.")
        entry.content = content
        entry.updated_at = datetime.now(timezone.utc).isoformat()
        await _store.save(entry)
        return KBResult(action=act, success=True, entry=entry, message="Entry updated.")

    # DELETE
    deleted = await _store.delete(topic)
    if not deleted:
        return KBResult(action=act, success=False, message=f"No entry found for '{topic}'.")
    return KBResult(action=act, success=True, message=f"Entry for '{topic}' deleted.")
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project |
| `{{DATA_DIR}}` | Directory for persistent data storage (e.g. `./data`) |
| `{{RESOURCE_BASE_URL}}` | Base URL for learning resources |
| `{{LLM_GENERATED_*}}` | Placeholders replaced at runtime by LLM-generated content |

## Dependencies

```
pydantic>=2.0
```
