# Education Domain: MCP Server (Python)

FastMCP server exposing education tools as Model Context Protocol resources and tools.
Wraps the Python tool implementations with MCP-compliant interfaces.

## Generated File: `mcp_server/education_server.py`

```python
"""Education MCP server for {{PROJECT_NAME}}.

Exposes learning path, flashcard, quiz, and knowledge base tools via
the Model Context Protocol using FastMCP.
"""

from __future__ import annotations

import json
from typing import Any

from mcp.server.fastmcp import FastMCP

from {{PACKAGE_NAME}}.tools.education_tools import (
    Difficulty,
    KBAction,
    QuestionType,
    flashcard_generator,
    knowledge_base,
    learning_path,
    quiz_engine,
)

# ---------------------------------------------------------------------------
# Server setup
# ---------------------------------------------------------------------------

mcp = FastMCP(
    "{{PROJECT_NAME}} Education Server",
    version="{{VERSION}}",
)


# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

@mcp.resource("education://subjects")
async def list_subjects() -> str:
    """List available subject areas."""
    subjects = {{SUBJECT_LIST}}
    return json.dumps({"subjects": subjects}, indent=2)


@mcp.resource("education://difficulty-levels")
async def list_difficulty_levels() -> str:
    """List supported difficulty levels."""
    levels = [d.value for d in Difficulty]
    return json.dumps({"levels": levels}, indent=2)


@mcp.resource("education://question-types")
async def list_question_types() -> str:
    """List supported quiz question types."""
    types = [q.value for q in QuestionType]
    return json.dumps({"question_types": types}, indent=2)


@mcp.resource("education://knowledge/{topic}")
async def get_knowledge_entry(topic: str) -> str:
    """Retrieve a knowledge base entry by topic."""
    result = await knowledge_base(action="read", topic=topic)
    return result.model_dump_json(indent=2)


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

@mcp.tool()
async def create_learning_path(
    subject: str,
    level: str = "beginner",
    goals: list[str] | None = None,
) -> str:
    """Generate a personalized learning path.

    Args:
        subject: The subject area (e.g. "linear algebra", "python programming").
        level: Learner level -- beginner, intermediate, or advanced.
        goals: Specific learning objectives. Defaults to a general overview.
    """
    if goals is None:
        goals = [f"Understand fundamentals of {subject}"]
    plan = await learning_path(subject=subject, level=level, goals=goals)
    return plan.model_dump_json(indent=2)


@mcp.tool()
async def create_flashcards(
    topic: str,
    count: int = 10,
    difficulty: str = "intermediate",
) -> str:
    """Generate flashcards for spaced-repetition study.

    Args:
        topic: The concept or subject to create cards for.
        count: Number of cards to generate (1-50).
        difficulty: Card difficulty -- beginner, intermediate, or advanced.
    """
    cards = await flashcard_generator(topic=topic, count=count, difficulty=difficulty)
    return cards.model_dump_json(indent=2)


@mcp.tool()
async def create_quiz(
    topic: str,
    count: int = 5,
    question_type: str = "multiple_choice",
) -> str:
    """Generate a quiz for knowledge assessment.

    Args:
        topic: Subject area for the quiz.
        count: Number of questions (1-30).
        question_type: One of multiple_choice, short_answer, true_false.
    """
    quiz = await quiz_engine(topic=topic, count=count, question_type=question_type)
    return quiz.model_dump_json(indent=2)


@mcp.tool()
async def manage_knowledge(
    action: str,
    topic: str,
    content: str = "",
) -> str:
    """Create, read, update, or delete knowledge base entries.

    Args:
        action: One of create, read, update, delete.
        topic: The topic key for the entry.
        content: Entry content (required for create/update).
    """
    result = await knowledge_base(action=action, topic=topic, content=content)
    return result.model_dump_json(indent=2)


# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

@mcp.prompt()
async def study_session(topic: str, level: str = "intermediate") -> str:
    """Start a guided study session on a topic."""
    return (
        f"I want to study {topic} at the {level} level. "
        f"Please create a learning path, generate flashcards, and prepare "
        f"a short quiz to test my understanding. Guide me step by step "
        f"using the Socratic method."
    )


@mcp.prompt()
async def review_session(topic: str) -> str:
    """Start a spaced-repetition review session."""
    return (
        f"I need to review {topic}. Please pull up my flashcards for this "
        f"topic and quiz me on the ones due for review. Track which ones I "
        f"get right and wrong, and adjust the review schedule accordingly."
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    mcp.run(transport="{{MCP_TRANSPORT}}")


if __name__ == "__main__":
    main()
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project |
| `{{PACKAGE_NAME}}` | Python package name used in imports |
| `{{VERSION}}` | Server version string (e.g. `"0.1.0"`) |
| `{{SUBJECT_LIST}}` | JSON list of available subjects (e.g. `["math", "science", "history"]`) |
| `{{MCP_TRANSPORT}}` | MCP transport mode -- `"stdio"` or `"sse"` |

## Dependencies

```
mcp[cli]>=1.0.0
pydantic>=2.0
```
