# Health Tools - Python Implementation

> Python tool implementations for health domain functionality.
> Replace `{{PROJECT_NAME}}` and `{{PACKAGE_NAME}}` with your project values.

## Dependencies

```
pydantic>=2.0
python-dateutil>=2.8
```

## Code

```python
"""{{PROJECT_NAME}} - Health domain tools.

Provides food recognition, medication tracking, health reminders,
and symptom assessment utilities.
"""

from __future__ import annotations

import uuid
from datetime import datetime, time
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Shared models
# ---------------------------------------------------------------------------

class Status(str, Enum):
    OK = "ok"
    ERROR = "error"


class Result(BaseModel):
    """Generic operation result."""
    status: Status
    message: str
    id: Optional[str] = None


# ---------------------------------------------------------------------------
# Food recognition
# ---------------------------------------------------------------------------

class MacroNutrients(BaseModel):
    calories_kcal: float = Field(..., description="Energy in kcal")
    protein_g: float = Field(..., description="Protein in grams")
    carbs_g: float = Field(..., description="Carbohydrates in grams")
    fat_g: float = Field(..., description="Fat in grams")
    fiber_g: float = Field(0.0, description="Dietary fiber in grams")


class NutritionInfo(BaseModel):
    food_item: str
    serving_size: str
    macros: MacroNutrients
    confidence: float = Field(..., ge=0.0, le=1.0)
    disclaimer: str = (
        "Nutritional estimates are approximate. Consult a registered "
        "dietitian for precise dietary guidance."
    )


# Common food database (simplified reference values per typical serving)
_FOOD_DB: dict[str, dict] = {
    "apple": {"serving": "1 medium (182g)", "cal": 95, "p": 0.5, "c": 25, "f": 0.3, "fi": 4.4},
    "banana": {"serving": "1 medium (118g)", "cal": 105, "p": 1.3, "c": 27, "f": 0.4, "fi": 3.1},
    "chicken breast": {"serving": "100g cooked", "cal": 165, "p": 31, "c": 0, "f": 3.6, "fi": 0},
    "rice": {"serving": "1 cup cooked (158g)", "cal": 206, "p": 4.3, "c": 45, "f": 0.4, "fi": 0.6},
    "egg": {"serving": "1 large (50g)", "cal": 72, "p": 6.3, "c": 0.4, "f": 4.8, "fi": 0},
    "salad": {"serving": "1 bowl (150g)", "cal": 20, "p": 1.5, "c": 3.5, "f": 0.2, "fi": 2.0},
    "bread": {"serving": "1 slice (30g)", "cal": 79, "p": 2.7, "c": 15, "f": 1.0, "fi": 0.6},
    "milk": {"serving": "1 cup (244ml)", "cal": 149, "p": 8, "c": 12, "f": 8, "fi": 0},
    "salmon": {"serving": "100g cooked", "cal": 208, "p": 20, "c": 0, "f": 13, "fi": 0},
    "pasta": {"serving": "1 cup cooked (140g)", "cal": 220, "p": 8, "c": 43, "f": 1.3, "fi": 2.5},
}


async def food_recognition(description: str) -> NutritionInfo:
    """Estimate nutritional content from a food description.

    Args:
        description: Free-text description of the food item or meal.

    Returns:
        NutritionInfo with estimated macro-nutrient breakdown.
    """
    desc_lower = description.lower().strip()

    # Attempt to match against the built-in database
    for key, vals in _FOOD_DB.items():
        if key in desc_lower:
            return NutritionInfo(
                food_item=key.title(),
                serving_size=vals["serving"],
                macros=MacroNutrients(
                    calories_kcal=vals["cal"],
                    protein_g=vals["p"],
                    carbs_g=vals["c"],
                    fat_g=vals["f"],
                    fiber_g=vals["fi"],
                ),
                confidence=0.75,
            )

    # Fallback estimate for unrecognized items
    return NutritionInfo(
        food_item=description,
        serving_size="estimated single serving",
        macros=MacroNutrients(
            calories_kcal=250,
            protein_g=10,
            carbs_g=30,
            fat_g=10,
            fiber_g=3,
        ),
        confidence=0.3,
    )


# ---------------------------------------------------------------------------
# Medication tracker
# ---------------------------------------------------------------------------

class MedicationEntry(BaseModel):
    id: str
    medication: str
    dosage: str
    schedule: str
    created_at: datetime
    active: bool = True


# In-memory store (swap for a real DB in production)
_medications: dict[str, MedicationEntry] = {}


async def medication_tracker(
    action: str,
    medication: str,
    dosage: str = "",
    schedule: str = "",
) -> Result:
    """Create, read, update, or delete medication schedule entries.

    Args:
        action: One of 'add', 'list', 'update', 'remove'.
        medication: Name of the medication.
        dosage: Dosage amount and unit (e.g. '500mg').
        schedule: When to take it (e.g. 'twice daily', '08:00,20:00').

    Returns:
        Result indicating success or failure.
    """
    action = action.lower().strip()

    if action == "add":
        entry_id = str(uuid.uuid4())[:8]
        _medications[entry_id] = MedicationEntry(
            id=entry_id,
            medication=medication,
            dosage=dosage,
            schedule=schedule,
            created_at=datetime.utcnow(),
        )
        return Result(status=Status.OK, message=f"Added {medication} ({dosage})", id=entry_id)

    if action == "list":
        matches = [
            e for e in _medications.values()
            if medication.lower() in e.medication.lower() and e.active
        ]
        if not matches:
            return Result(status=Status.OK, message="No matching medications found.")
        summary = "; ".join(
            f"{e.medication} {e.dosage} [{e.schedule}]" for e in matches
        )
        return Result(status=Status.OK, message=summary)

    if action == "update":
        for entry in _medications.values():
            if medication.lower() in entry.medication.lower() and entry.active:
                if dosage:
                    entry.dosage = dosage
                if schedule:
                    entry.schedule = schedule
                return Result(status=Status.OK, message=f"Updated {entry.medication}", id=entry.id)
        return Result(status=Status.ERROR, message=f"Medication '{medication}' not found.")

    if action == "remove":
        for entry in _medications.values():
            if medication.lower() in entry.medication.lower() and entry.active:
                entry.active = False
                return Result(status=Status.OK, message=f"Removed {entry.medication}", id=entry.id)
        return Result(status=Status.ERROR, message=f"Medication '{medication}' not found.")

    return Result(status=Status.ERROR, message=f"Unknown action: {action}")


# ---------------------------------------------------------------------------
# Health reminders
# ---------------------------------------------------------------------------

class ReminderEntry(BaseModel):
    id: str
    reminder_type: str
    time: str
    message: str
    created_at: datetime
    active: bool = True


_reminders: dict[str, ReminderEntry] = {}


async def health_reminder(
    type: str,
    time: str,
    message: str,
) -> Result:
    """Set a health-related reminder.

    Args:
        type: Category such as 'medication', 'water', 'exercise', 'sleep'.
        time: When to trigger (e.g. '08:00', '14:30').
        message: Reminder text shown to the user.

    Returns:
        Result with the created reminder ID.
    """
    reminder_id = str(uuid.uuid4())[:8]
    _reminders[reminder_id] = ReminderEntry(
        id=reminder_id,
        reminder_type=type,
        time=time,
        message=message,
        created_at=datetime.utcnow(),
    )
    return Result(
        status=Status.OK,
        message=f"Reminder set: '{message}' at {time} ({type})",
        id=reminder_id,
    )


# ---------------------------------------------------------------------------
# Symptom assessment
# ---------------------------------------------------------------------------

class Assessment(BaseModel):
    symptoms: list[str]
    possible_categories: list[str]
    severity_hint: str
    recommendation: str
    disclaimer: str = (
        "This is general information only. It is NOT a medical diagnosis. "
        "Please consult a qualified healthcare professional for medical advice."
    )


_EMERGENCY_SYMPTOMS = {
    "chest pain", "difficulty breathing", "shortness of breath",
    "sudden numbness", "severe headache", "loss of consciousness",
    "uncontrolled bleeding", "suicidal thoughts",
}

_SYMPTOM_CATEGORIES: dict[str, list[str]] = {
    "respiratory": ["cough", "sore throat", "runny nose", "congestion", "sneezing"],
    "digestive": ["nausea", "vomiting", "diarrhea", "stomach pain", "bloating"],
    "musculoskeletal": ["back pain", "joint pain", "muscle ache", "stiffness"],
    "neurological": ["headache", "dizziness", "fatigue", "insomnia"],
    "dermatological": ["rash", "itching", "hives", "dry skin"],
}


async def symptom_assessment(symptoms: list[str]) -> Assessment:
    """Provide general information about reported symptoms.

    This does NOT diagnose any condition. Always advise the user to
    consult a healthcare professional.

    Args:
        symptoms: List of symptom descriptions.

    Returns:
        Assessment with categorization and general guidance.
    """
    normalized = [s.lower().strip() for s in symptoms]

    # Check for emergency symptoms
    emergency_matches = [s for s in normalized if s in _EMERGENCY_SYMPTOMS]
    if emergency_matches:
        return Assessment(
            symptoms=normalized,
            possible_categories=["emergency"],
            severity_hint="potentially serious",
            recommendation=(
                "One or more of your symptoms may require immediate medical "
                "attention. Please call emergency services or visit the nearest "
                "emergency room right away."
            ),
        )

    # Categorize symptoms
    matched_categories: set[str] = set()
    for symptom in normalized:
        for category, keywords in _SYMPTOM_CATEGORIES.items():
            if symptom in keywords:
                matched_categories.add(category)

    severity = "mild" if len(normalized) <= 2 else "moderate"

    if matched_categories:
        recommendation = (
            f"Your symptoms may be related to: {', '.join(sorted(matched_categories))}. "
            "If symptoms persist for more than a few days or worsen, please see "
            "a healthcare provider."
        )
    else:
        recommendation = (
            "Your symptoms could not be automatically categorized. Please "
            "describe them to a healthcare professional for proper evaluation."
        )

    return Assessment(
        symptoms=normalized,
        possible_categories=sorted(matched_categories) if matched_categories else ["uncategorized"],
        severity_hint=severity,
        recommendation=recommendation,
    )
```
