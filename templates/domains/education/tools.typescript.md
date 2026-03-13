# Education Domain: TypeScript Tool Implementations

Tool functions for the education domain with Zod validation and async patterns.
Provides learning path generation, flashcard creation, quiz engine, and knowledge base CRUD.

## Generated File: `tools/education-tools.ts`

```typescript
/**
 * Education domain tools for {{PROJECT_NAME}}.
 *
 * Provides learning path generation, flashcard creation, quiz generation,
 * and knowledge base management.
 */

import { randomUUID } from "crypto";
import { readFile, writeFile, unlink, mkdir } from "fs/promises";
import { join } from "path";
import { createHash } from "crypto";
import { z } from "zod";

// ---------------------------------------------------------------------------
// Enums and Schemas
// ---------------------------------------------------------------------------

const Difficulty = z.enum(["beginner", "intermediate", "advanced"]);
type Difficulty = z.infer<typeof Difficulty>;

const QuestionType = z.enum(["multiple_choice", "short_answer", "true_false"]);
type QuestionType = z.infer<typeof QuestionType>;

const KBAction = z.enum(["create", "read", "update", "delete"]);
type KBAction = z.infer<typeof KBAction>;

const BloomLevel = z.enum([
  "remember",
  "understand",
  "apply",
  "analyze",
  "evaluate",
  "create",
]);
type BloomLevel = z.infer<typeof BloomLevel>;

// ---------------------------------------------------------------------------
// Types -- Learning Path
// ---------------------------------------------------------------------------

interface Milestone {
  title: string;
  description: string;
  durationDays: number;
  resources: string[];
  objectives: string[];
}

interface LearningPlan {
  id: string;
  subject: string;
  level: Difficulty;
  goals: string[];
  milestones: Milestone[];
  totalDurationDays: number;
  createdAt: string;
}

// ---------------------------------------------------------------------------
// Types -- Flashcards
// ---------------------------------------------------------------------------

interface Flashcard {
  id: string;
  front: string;
  back: string;
  difficulty: Difficulty;
  tags: string[];
  nextReview: string | null;
}

interface Flashcards {
  topic: string;
  cards: Flashcard[];
  count: number;
}

// ---------------------------------------------------------------------------
// Types -- Quiz
// ---------------------------------------------------------------------------

interface Choice {
  label: string;
  text: string;
  isCorrect: boolean;
}

interface Question {
  id: string;
  text: string;
  questionType: QuestionType;
  choices: Choice[];
  correctAnswer: string;
  explanation: string;
  bloomLevel: BloomLevel;
}

interface Quiz {
  id: string;
  topic: string;
  questions: Question[];
  totalPoints: number;
  createdAt: string;
}

// ---------------------------------------------------------------------------
// Types -- Knowledge Base
// ---------------------------------------------------------------------------

interface KBEntry {
  id: string;
  topic: string;
  content: string;
  tags: string[];
  createdAt: string;
  updatedAt: string;
}

interface KBResult {
  action: KBAction;
  success: boolean;
  entry: KBEntry | null;
  message: string;
}

// ---------------------------------------------------------------------------
// Storage backend (file-based, swappable)
// ---------------------------------------------------------------------------

const DATA_DIR = "{{DATA_DIR}}";
const KB_DIR = join(DATA_DIR, "knowledge_base");

function topicSlug(topic: string): string {
  return createHash("sha256").update(topic.toLowerCase()).digest("hex").slice(0, 16);
}

async function ensureDir(dir: string): Promise<void> {
  await mkdir(dir, { recursive: true });
}

async function saveEntry(entry: KBEntry): Promise<void> {
  await ensureDir(KB_DIR);
  const file = join(KB_DIR, `${topicSlug(entry.topic)}.json`);
  await writeFile(file, JSON.stringify(entry, null, 2));
}

async function loadEntry(topic: string): Promise<KBEntry | null> {
  const file = join(KB_DIR, `${topicSlug(topic)}.json`);
  try {
    const data = await readFile(file, "utf-8");
    return JSON.parse(data) as KBEntry;
  } catch {
    return null;
  }
}

async function deleteEntry(topic: string): Promise<boolean> {
  const file = join(KB_DIR, `${topicSlug(topic)}.json`);
  try {
    await unlink(file);
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Tool: learningPath
// ---------------------------------------------------------------------------

export async function learningPath(
  subject: string,
  level: string,
  goals: string[],
): Promise<LearningPlan> {
  const diff = Difficulty.parse(level.toLowerCase());
  const baseDays: Record<Difficulty, number> = {
    beginner: 7,
    intermediate: 10,
    advanced: 14,
  };

  const milestones: Milestone[] = goals.map((goal, i) => ({
    title: `Milestone ${i + 1}: ${goal}`,
    description: `Work toward: ${goal}`,
    durationDays: baseDays[diff],
    resources: [
      `{{RESOURCE_BASE_URL}}/${subject.toLowerCase().replace(/\s+/g, "-")}/m${i + 1}`,
    ],
    objectives: [goal],
  }));

  const totalDurationDays = milestones.reduce((sum, m) => sum + m.durationDays, 0);

  return {
    id: randomUUID().replace(/-/g, "").slice(0, 12),
    subject,
    level: diff,
    goals,
    milestones,
    totalDurationDays,
    createdAt: new Date().toISOString(),
  };
}

// ---------------------------------------------------------------------------
// Tool: flashcardGenerator
// ---------------------------------------------------------------------------

export async function flashcardGenerator(
  topic: string,
  count: number = 10,
  difficulty: string = "intermediate",
): Promise<Flashcards> {
  const safeCount = Math.max(1, Math.min(count, 50));
  const diff = Difficulty.parse(difficulty.toLowerCase());

  const cards: Flashcard[] = Array.from({ length: safeCount }, (_, i) => ({
    id: randomUUID().replace(/-/g, "").slice(0, 8),
    front: `[${topic}] Question ${i + 1} ({{LLM_GENERATED_FRONT}})`,
    back: `Answer ${i + 1} ({{LLM_GENERATED_BACK}})`,
    difficulty: diff,
    tags: [topic.toLowerCase()],
    nextReview: null,
  }));

  return { topic, cards, count: cards.length };
}

// ---------------------------------------------------------------------------
// Tool: quizEngine
// ---------------------------------------------------------------------------

export async function quizEngine(
  topic: string,
  count: number = 5,
  questionType: string = "multiple_choice",
): Promise<Quiz> {
  const safeCount = Math.max(1, Math.min(count, 30));
  const qType = QuestionType.parse(questionType.toLowerCase());

  const questions: Question[] = Array.from({ length: safeCount }, (_, i) => {
    let choices: Choice[] = [];
    let correctAnswer = `{{LLM_GENERATED_ANSWER_${i + 1}}}`;

    if (qType === "multiple_choice") {
      choices = [
        { label: "A", text: `Option A ({{LLM_OPTION_A_${i + 1}}})`, isCorrect: false },
        { label: "B", text: `Option B ({{LLM_OPTION_B_${i + 1}}})`, isCorrect: false },
        { label: "C", text: `Option C ({{LLM_OPTION_C_${i + 1}}})`, isCorrect: false },
        { label: "D", text: `Option D ({{LLM_OPTION_D_${i + 1}}})`, isCorrect: true },
      ];
      correctAnswer = "D";
    } else if (qType === "true_false") {
      choices = [
        { label: "T", text: "True", isCorrect: false },
        { label: "F", text: "False", isCorrect: true },
      ];
      correctAnswer = "F";
    }

    return {
      id: randomUUID().replace(/-/g, "").slice(0, 8),
      text: `[${topic}] Question ${i + 1} ({{LLM_GENERATED_QUESTION_${i + 1}}})`,
      questionType: qType,
      choices,
      correctAnswer,
      explanation: `{{LLM_GENERATED_EXPLANATION_${i + 1}}}`,
      bloomLevel: "understand" as BloomLevel,
    };
  });

  return {
    id: randomUUID().replace(/-/g, "").slice(0, 12),
    topic,
    questions,
    totalPoints: questions.length,
    createdAt: new Date().toISOString(),
  };
}

// ---------------------------------------------------------------------------
// Tool: knowledgeBase
// ---------------------------------------------------------------------------

export async function knowledgeBase(
  action: string,
  topic: string,
  content: string = "",
): Promise<KBResult> {
  const act = KBAction.parse(action.toLowerCase());

  if (act === "create") {
    const existing = await loadEntry(topic);
    if (existing) {
      return { action: act, success: false, entry: null, message: `Entry already exists for '${topic}'. Use 'update' instead.` };
    }
    const entry: KBEntry = {
      id: randomUUID().replace(/-/g, "").slice(0, 12),
      topic,
      content,
      tags: [topic.toLowerCase()],
      createdAt: new Date().toISOString(),
      updatedAt: "",
    };
    await saveEntry(entry);
    return { action: act, success: true, entry, message: "Entry created." };
  }

  if (act === "read") {
    const entry = await loadEntry(topic);
    if (!entry) {
      return { action: act, success: false, entry: null, message: `No entry found for '${topic}'.` };
    }
    return { action: act, success: true, entry, message: "" };
  }

  if (act === "update") {
    const entry = await loadEntry(topic);
    if (!entry) {
      return { action: act, success: false, entry: null, message: `No entry found for '${topic}'. Use 'create' first.` };
    }
    entry.content = content;
    entry.updatedAt = new Date().toISOString();
    await saveEntry(entry);
    return { action: act, success: true, entry, message: "Entry updated." };
  }

  // delete
  const deleted = await deleteEntry(topic);
  if (!deleted) {
    return { action: act, success: false, entry: null, message: `No entry found for '${topic}'.` };
  }
  return { action: act, success: true, entry: null, message: `Entry for '${topic}' deleted.` };
}
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
zod
```
