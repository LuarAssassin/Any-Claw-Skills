# Education Domain: Knowledge Base

Reference knowledge for building education-focused AI agents. Covers learning science
principles, assessment design, and pedagogical strategies that tools and prompts
in this domain should be grounded in.

## Spaced Repetition

Spaced repetition is an evidence-based learning technique that schedules reviews at
increasing intervals to exploit the spacing effect in memory consolidation.

**Core algorithm (SM-2 simplified):**

- New cards start at interval = 1 day.
- Correct recall: multiply interval by an ease factor (default 2.5).
- Incorrect recall: reset interval to 1 day and reduce ease factor by 0.2 (minimum 1.3).
- Review is due when current_date >= last_review_date + interval.

**Implementation guidelines:**

- Track per-card: `interval`, `ease_factor`, `repetitions`, `next_review`.
- Provide "again", "hard", "good", "easy" response buttons that map to ease adjustments.
- Surface cards due for review first, then introduce new cards up to the daily limit.
- Default daily new card limit: 20. Default daily review limit: 100.

## Bloom's Taxonomy

A hierarchy of cognitive skills used to classify learning objectives and assessment
questions. Tools should tag questions with the appropriate level.

| Level | Description | Question Stems |
|---|---|---|
| **Remember** | Recall facts and basic concepts | Define, list, name, identify, recall |
| **Understand** | Explain ideas or concepts | Describe, explain, summarize, paraphrase |
| **Apply** | Use information in new situations | Solve, demonstrate, apply, calculate |
| **Analyze** | Draw connections among ideas | Compare, contrast, examine, differentiate |
| **Evaluate** | Justify a decision or position | Judge, critique, argue, defend, assess |
| **Create** | Produce new or original work | Design, construct, develop, formulate |

When generating quizzes, aim for a distribution across levels appropriate to the
learner's stage: beginners focus on Remember/Understand, intermediates on
Apply/Analyze, advanced on Evaluate/Create.

## Learning Strategies

Strategies the tutor should recommend and incorporate into learning paths:

**Active recall** -- Retrieve information from memory rather than passively re-reading.
Generate practice questions and encourage self-testing.

**Interleaving** -- Mix different topics or problem types within a study session
rather than blocking by topic. Improves discrimination and transfer.

**Elaborative interrogation** -- Ask "why" and "how" questions to connect new
information to existing knowledge. Central to the Socratic method.

**Concrete examples** -- Ground abstract concepts with specific, relatable examples.
Use analogies when introducing unfamiliar domains.

**Dual coding** -- Combine verbal explanations with visual representations (diagrams,
charts, concept maps) when the medium supports it.

**Retrieval practice** -- Frequent low-stakes testing improves long-term retention
more than additional study time.

## Assessment Types

| Type | Best For | Tool Mapping |
|---|---|---|
| **Multiple choice** | Broad knowledge coverage, auto-grading | `quiz_engine` with `multiple_choice` |
| **Short answer** | Testing recall and expression | `quiz_engine` with `short_answer` |
| **True/false** | Quick concept checks | `quiz_engine` with `true_false` |
| **Flashcard review** | Spaced repetition, vocabulary, definitions | `flashcard_generator` |
| **Project-based** | Bloom's Create level, synthesis | Learning path milestones |
| **Formative** | Ongoing, low-stakes, during learning | Embedded quiz after each milestone |
| **Summative** | End-of-unit, comprehensive evaluation | Full quiz at path completion |

## Curriculum Alignment

When generating content, align to the configured curriculum standard:

- **Common Core** -- Focus on standards codes (e.g., CCSS.MATH.CONTENT.HSA.REI.B.3).
- **AP** -- Align to College Board unit structure and learning objectives.
- **IB** -- Map to IB subject guide assessment criteria.
- **Custom** -- Use the learner's stated objectives as the alignment target.

Tag generated content with the relevant standard identifiers when a curriculum
is configured, so progress can be tracked against formal requirements.

## Difficulty Calibration

Guidelines for calibrating content difficulty:

- **Beginner**: Assume no prior knowledge. Use simple vocabulary. Provide worked
  examples before asking practice questions. Bloom levels: Remember, Understand.
- **Intermediate**: Assume foundational understanding. Introduce nuance and edge
  cases. Mix problem types. Bloom levels: Apply, Analyze.
- **Advanced**: Assume solid grasp of fundamentals. Pose open-ended problems,
  require synthesis across topics. Bloom levels: Evaluate, Create.

Adjust dynamically based on quiz performance: if accuracy exceeds 85%, suggest
advancing to the next level. If accuracy falls below 60%, recommend review.
