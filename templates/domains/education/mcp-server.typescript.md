# Education Domain: MCP Server (TypeScript)

MCP SDK server exposing education tools as Model Context Protocol resources and tools.
Wraps the TypeScript tool implementations with MCP-compliant interfaces.

## Generated File: `mcp-server/education-server.ts`

```typescript
/**
 * Education MCP server for {{PROJECT_NAME}}.
 *
 * Exposes learning path, flashcard, quiz, and knowledge base tools via
 * the Model Context Protocol using the official MCP TypeScript SDK.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

import {
  learningPath,
  flashcardGenerator,
  quizEngine,
  knowledgeBase,
} from "../tools/education-tools.js";

// ---------------------------------------------------------------------------
// Server setup
// ---------------------------------------------------------------------------

const server = new McpServer({
  name: "{{PROJECT_NAME}} Education Server",
  version: "{{VERSION}}",
});

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

server.resource("subjects", "education://subjects", async (uri) => ({
  contents: [
    {
      uri: uri.href,
      mimeType: "application/json",
      text: JSON.stringify({ subjects: {{SUBJECT_LIST}} }, null, 2),
    },
  ],
}));

server.resource(
  "difficulty-levels",
  "education://difficulty-levels",
  async (uri) => ({
    contents: [
      {
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify(
          { levels: ["beginner", "intermediate", "advanced"] },
          null,
          2,
        ),
      },
    ],
  }),
);

server.resource(
  "question-types",
  "education://question-types",
  async (uri) => ({
    contents: [
      {
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify(
          { question_types: ["multiple_choice", "short_answer", "true_false"] },
          null,
          2,
        ),
      },
    ],
  }),
);

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

server.tool(
  "create_learning_path",
  "Generate a personalized learning path with milestones and resources",
  {
    subject: z.string().describe("Subject area (e.g. 'linear algebra')"),
    level: z
      .enum(["beginner", "intermediate", "advanced"])
      .default("beginner")
      .describe("Learner level"),
    goals: z
      .array(z.string())
      .optional()
      .describe("Specific learning objectives"),
  },
  async ({ subject, level, goals }) => {
    const effectiveGoals = goals ?? [`Understand fundamentals of ${subject}`];
    const plan = await learningPath(subject, level, effectiveGoals);
    return {
      content: [{ type: "text", text: JSON.stringify(plan, null, 2) }],
    };
  },
);

server.tool(
  "create_flashcards",
  "Generate flashcards for spaced-repetition study",
  {
    topic: z.string().describe("Concept or subject for the cards"),
    count: z.number().min(1).max(50).default(10).describe("Number of cards"),
    difficulty: z
      .enum(["beginner", "intermediate", "advanced"])
      .default("intermediate")
      .describe("Card difficulty"),
  },
  async ({ topic, count, difficulty }) => {
    const cards = await flashcardGenerator(topic, count, difficulty);
    return {
      content: [{ type: "text", text: JSON.stringify(cards, null, 2) }],
    };
  },
);

server.tool(
  "create_quiz",
  "Generate a quiz for knowledge assessment",
  {
    topic: z.string().describe("Subject area for the quiz"),
    count: z.number().min(1).max(30).default(5).describe("Number of questions"),
    questionType: z
      .enum(["multiple_choice", "short_answer", "true_false"])
      .default("multiple_choice")
      .describe("Type of questions"),
  },
  async ({ topic, count, questionType }) => {
    const quiz = await quizEngine(topic, count, questionType);
    return {
      content: [{ type: "text", text: JSON.stringify(quiz, null, 2) }],
    };
  },
);

server.tool(
  "manage_knowledge",
  "Create, read, update, or delete knowledge base entries",
  {
    action: z
      .enum(["create", "read", "update", "delete"])
      .describe("CRUD action"),
    topic: z.string().describe("Topic key for the entry"),
    content: z
      .string()
      .default("")
      .describe("Entry content (for create/update)"),
  },
  async ({ action, topic, content }) => {
    const result = await knowledgeBase(action, topic, content);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  },
);

// ---------------------------------------------------------------------------
// Prompts
// ---------------------------------------------------------------------------

server.prompt(
  "study_session",
  "Start a guided study session on a topic",
  {
    topic: z.string().describe("Topic to study"),
    level: z
      .enum(["beginner", "intermediate", "advanced"])
      .default("intermediate")
      .describe("Study level"),
  },
  async ({ topic, level }) => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text:
            `I want to study ${topic} at the ${level} level. ` +
            `Please create a learning path, generate flashcards, and prepare ` +
            `a short quiz to test my understanding. Guide me step by step ` +
            `using the Socratic method.`,
        },
      },
    ],
  }),
);

server.prompt(
  "review_session",
  "Start a spaced-repetition review session",
  { topic: z.string().describe("Topic to review") },
  async ({ topic }) => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text:
            `I need to review ${topic}. Please pull up my flashcards for this ` +
            `topic and quiz me on the ones due for review. Track which ones I ` +
            `get right and wrong, and adjust the review schedule accordingly.`,
        },
      },
    ],
  }),
);

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("{{PROJECT_NAME}} Education MCP server running on stdio");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project |
| `{{VERSION}}` | Server version string (e.g. `"0.1.0"`) |
| `{{SUBJECT_LIST}}` | JSON array of available subjects (e.g. `["math", "science", "history"]`) |

## Dependencies

```json
{
  "@modelcontextprotocol/sdk": "^1.0.0",
  "zod": "^3.22.0"
}
```
