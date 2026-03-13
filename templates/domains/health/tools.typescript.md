# Health Tools - TypeScript Implementation

> TypeScript tool implementations for health domain functionality.
> Replace `{{PROJECT_NAME}}` and `{{PACKAGE_NAME}}` with your project values.

## Dependencies

```json
{
  "dependencies": {
    "zod": "^3.22.0",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "@types/uuid": "^9.0.0",
    "typescript": "^5.3.0"
  }
}
```

## Code

```typescript
/**
 * {{PROJECT_NAME}} - Health domain tools.
 *
 * Provides food recognition, medication tracking, health reminders,
 * and symptom assessment utilities.
 */

import { z } from "zod";
import { v4 as uuidv4 } from "uuid";

// ---------------------------------------------------------------------------
// Shared schemas
// ---------------------------------------------------------------------------

const StatusSchema = z.enum(["ok", "error"]);

const ResultSchema = z.object({
  status: StatusSchema,
  message: z.string(),
  id: z.string().optional(),
});
type Result = z.infer<typeof ResultSchema>;

// ---------------------------------------------------------------------------
// Food recognition
// ---------------------------------------------------------------------------

const MacroNutrientsSchema = z.object({
  calories_kcal: z.number().describe("Energy in kcal"),
  protein_g: z.number().describe("Protein in grams"),
  carbs_g: z.number().describe("Carbohydrates in grams"),
  fat_g: z.number().describe("Fat in grams"),
  fiber_g: z.number().default(0).describe("Dietary fiber in grams"),
});

const NutritionInfoSchema = z.object({
  food_item: z.string(),
  serving_size: z.string(),
  macros: MacroNutrientsSchema,
  confidence: z.number().min(0).max(1),
  disclaimer: z.string().default(
    "Nutritional estimates are approximate. Consult a registered " +
      "dietitian for precise dietary guidance."
  ),
});
type NutritionInfo = z.infer<typeof NutritionInfoSchema>;

interface FoodEntry {
  serving: string;
  cal: number;
  p: number;
  c: number;
  f: number;
  fi: number;
}

const FOOD_DB: Record<string, FoodEntry> = {
  apple: { serving: "1 medium (182g)", cal: 95, p: 0.5, c: 25, f: 0.3, fi: 4.4 },
  banana: { serving: "1 medium (118g)", cal: 105, p: 1.3, c: 27, f: 0.4, fi: 3.1 },
  "chicken breast": { serving: "100g cooked", cal: 165, p: 31, c: 0, f: 3.6, fi: 0 },
  rice: { serving: "1 cup cooked (158g)", cal: 206, p: 4.3, c: 45, f: 0.4, fi: 0.6 },
  egg: { serving: "1 large (50g)", cal: 72, p: 6.3, c: 0.4, f: 4.8, fi: 0 },
  salad: { serving: "1 bowl (150g)", cal: 20, p: 1.5, c: 3.5, f: 0.2, fi: 2.0 },
  bread: { serving: "1 slice (30g)", cal: 79, p: 2.7, c: 15, f: 1.0, fi: 0.6 },
  milk: { serving: "1 cup (244ml)", cal: 149, p: 8, c: 12, f: 8, fi: 0 },
  salmon: { serving: "100g cooked", cal: 208, p: 20, c: 0, f: 13, fi: 0 },
  pasta: { serving: "1 cup cooked (140g)", cal: 220, p: 8, c: 43, f: 1.3, fi: 2.5 },
};

/** Estimate nutritional content from a food description. */
export async function foodRecognition(description: string): Promise<NutritionInfo> {
  const descLower = description.toLowerCase().trim();

  for (const [key, vals] of Object.entries(FOOD_DB)) {
    if (descLower.includes(key)) {
      return {
        food_item: key.charAt(0).toUpperCase() + key.slice(1),
        serving_size: vals.serving,
        macros: {
          calories_kcal: vals.cal,
          protein_g: vals.p,
          carbs_g: vals.c,
          fat_g: vals.f,
          fiber_g: vals.fi,
        },
        confidence: 0.75,
        disclaimer:
          "Nutritional estimates are approximate. Consult a registered " +
          "dietitian for precise dietary guidance.",
      };
    }
  }

  return {
    food_item: description,
    serving_size: "estimated single serving",
    macros: { calories_kcal: 250, protein_g: 10, carbs_g: 30, fat_g: 10, fiber_g: 3 },
    confidence: 0.3,
    disclaimer:
      "Nutritional estimates are approximate. Consult a registered " +
      "dietitian for precise dietary guidance.",
  };
}

// ---------------------------------------------------------------------------
// Medication tracker
// ---------------------------------------------------------------------------

const MedicationEntrySchema = z.object({
  id: z.string(),
  medication: z.string(),
  dosage: z.string(),
  schedule: z.string(),
  createdAt: z.date(),
  active: z.boolean().default(true),
});
type MedicationEntry = z.infer<typeof MedicationEntrySchema>;

const medications = new Map<string, MedicationEntry>();

/** Create, read, update, or delete medication schedule entries. */
export async function medicationTracker(
  action: string,
  medication: string,
  dosage = "",
  schedule = ""
): Promise<Result> {
  const act = action.toLowerCase().trim();

  if (act === "add") {
    const id = uuidv4().slice(0, 8);
    medications.set(id, { id, medication, dosage, schedule, createdAt: new Date(), active: true });
    return { status: "ok", message: `Added ${medication} (${dosage})`, id };
  }

  if (act === "list") {
    const matches = [...medications.values()].filter(
      (e) => e.medication.toLowerCase().includes(medication.toLowerCase()) && e.active
    );
    if (matches.length === 0) {
      return { status: "ok", message: "No matching medications found." };
    }
    const summary = matches.map((e) => `${e.medication} ${e.dosage} [${e.schedule}]`).join("; ");
    return { status: "ok", message: summary };
  }

  if (act === "update") {
    for (const entry of medications.values()) {
      if (entry.medication.toLowerCase().includes(medication.toLowerCase()) && entry.active) {
        if (dosage) entry.dosage = dosage;
        if (schedule) entry.schedule = schedule;
        return { status: "ok", message: `Updated ${entry.medication}`, id: entry.id };
      }
    }
    return { status: "error", message: `Medication '${medication}' not found.` };
  }

  if (act === "remove") {
    for (const entry of medications.values()) {
      if (entry.medication.toLowerCase().includes(medication.toLowerCase()) && entry.active) {
        entry.active = false;
        return { status: "ok", message: `Removed ${entry.medication}`, id: entry.id };
      }
    }
    return { status: "error", message: `Medication '${medication}' not found.` };
  }

  return { status: "error", message: `Unknown action: ${action}` };
}

// ---------------------------------------------------------------------------
// Health reminders
// ---------------------------------------------------------------------------

interface ReminderEntry {
  id: string;
  reminderType: string;
  time: string;
  message: string;
  createdAt: Date;
  active: boolean;
}

const reminders = new Map<string, ReminderEntry>();

/** Set a health-related reminder. */
export async function healthReminder(
  type: string,
  time: string,
  message: string
): Promise<Result> {
  const id = uuidv4().slice(0, 8);
  reminders.set(id, {
    id,
    reminderType: type,
    time,
    message,
    createdAt: new Date(),
    active: true,
  });
  return { status: "ok", message: `Reminder set: '${message}' at ${time} (${type})`, id };
}

// ---------------------------------------------------------------------------
// Symptom assessment
// ---------------------------------------------------------------------------

const AssessmentSchema = z.object({
  symptoms: z.array(z.string()),
  possible_categories: z.array(z.string()),
  severity_hint: z.string(),
  recommendation: z.string(),
  disclaimer: z.string().default(
    "This is general information only. It is NOT a medical diagnosis. " +
      "Please consult a qualified healthcare professional for medical advice."
  ),
});
type Assessment = z.infer<typeof AssessmentSchema>;

const EMERGENCY_SYMPTOMS = new Set([
  "chest pain", "difficulty breathing", "shortness of breath",
  "sudden numbness", "severe headache", "loss of consciousness",
  "uncontrolled bleeding", "suicidal thoughts",
]);

const SYMPTOM_CATEGORIES: Record<string, string[]> = {
  respiratory: ["cough", "sore throat", "runny nose", "congestion", "sneezing"],
  digestive: ["nausea", "vomiting", "diarrhea", "stomach pain", "bloating"],
  musculoskeletal: ["back pain", "joint pain", "muscle ache", "stiffness"],
  neurological: ["headache", "dizziness", "fatigue", "insomnia"],
  dermatological: ["rash", "itching", "hives", "dry skin"],
};

/** Provide general information about reported symptoms. */
export async function symptomAssessment(symptoms: string[]): Promise<Assessment> {
  const normalized = symptoms.map((s) => s.toLowerCase().trim());

  const emergencyMatches = normalized.filter((s) => EMERGENCY_SYMPTOMS.has(s));
  if (emergencyMatches.length > 0) {
    return {
      symptoms: normalized,
      possible_categories: ["emergency"],
      severity_hint: "potentially serious",
      recommendation:
        "One or more of your symptoms may require immediate medical " +
        "attention. Please call emergency services or visit the nearest " +
        "emergency room right away.",
      disclaimer:
        "This is general information only. It is NOT a medical diagnosis. " +
        "Please consult a qualified healthcare professional for medical advice.",
    };
  }

  const matchedCategories = new Set<string>();
  for (const symptom of normalized) {
    for (const [category, keywords] of Object.entries(SYMPTOM_CATEGORIES)) {
      if (keywords.includes(symptom)) {
        matchedCategories.add(category);
      }
    }
  }

  const severity = normalized.length <= 2 ? "mild" : "moderate";
  const cats = [...matchedCategories].sort();

  const recommendation = cats.length > 0
    ? `Your symptoms may be related to: ${cats.join(", ")}. ` +
      "If symptoms persist for more than a few days or worsen, please see a healthcare provider."
    : "Your symptoms could not be automatically categorized. Please " +
      "describe them to a healthcare professional for proper evaluation.";

  return {
    symptoms: normalized,
    possible_categories: cats.length > 0 ? cats : ["uncategorized"],
    severity_hint: severity,
    recommendation,
    disclaimer:
      "This is general information only. It is NOT a medical diagnosis. " +
      "Please consult a qualified healthcare professional for medical advice.",
  };
}
```
