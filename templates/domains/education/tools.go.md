# Education Domain: Go Tool Implementations

Tool functions for the education domain using idiomatic Go with structs, enums,
and a file-backed knowledge base. Provides learning path generation, flashcard
creation, quiz engine, and knowledge base CRUD.

## Generated File: `tools/education_tools.go`

```go
// Package tools provides education domain tools for {{PROJECT_NAME}}.
//
// Includes learning path generation, flashcard creation, quiz generation,
// and knowledge base management.
package tools

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

type Difficulty string

const (
	DifficultyBeginner     Difficulty = "beginner"
	DifficultyIntermediate Difficulty = "intermediate"
	DifficultyAdvanced     Difficulty = "advanced"
)

func ParseDifficulty(s string) (Difficulty, error) {
	switch strings.ToLower(s) {
	case "beginner":
		return DifficultyBeginner, nil
	case "intermediate":
		return DifficultyIntermediate, nil
	case "advanced":
		return DifficultyAdvanced, nil
	default:
		return "", fmt.Errorf("invalid difficulty: %s", s)
	}
}

type QuestionType string

const (
	QuestionMultipleChoice QuestionType = "multiple_choice"
	QuestionShortAnswer    QuestionType = "short_answer"
	QuestionTrueFalse      QuestionType = "true_false"
)

func ParseQuestionType(s string) (QuestionType, error) {
	switch strings.ToLower(s) {
	case "multiple_choice":
		return QuestionMultipleChoice, nil
	case "short_answer":
		return QuestionShortAnswer, nil
	case "true_false":
		return QuestionTrueFalse, nil
	default:
		return "", fmt.Errorf("invalid question type: %s", s)
	}
}

type KBAction string

const (
	KBActionCreate KBAction = "create"
	KBActionRead   KBAction = "read"
	KBActionUpdate KBAction = "update"
	KBActionDelete KBAction = "delete"
)

type BloomLevel string

const (
	BloomRemember   BloomLevel = "remember"
	BloomUnderstand BloomLevel = "understand"
	BloomApply      BloomLevel = "apply"
	BloomAnalyze    BloomLevel = "analyze"
	BloomEvaluate   BloomLevel = "evaluate"
	BloomCreate     BloomLevel = "create"
)

// ---------------------------------------------------------------------------
// Types -- Learning Path
// ---------------------------------------------------------------------------

type Milestone struct {
	Title        string   `json:"title"`
	Description  string   `json:"description"`
	DurationDays int      `json:"duration_days"`
	Resources    []string `json:"resources"`
	Objectives   []string `json:"objectives"`
}

type LearningPlan struct {
	ID                string      `json:"id"`
	Subject           string      `json:"subject"`
	Level             Difficulty  `json:"level"`
	Goals             []string    `json:"goals"`
	Milestones        []Milestone `json:"milestones"`
	TotalDurationDays int         `json:"total_duration_days"`
	CreatedAt         string      `json:"created_at"`
}

// ---------------------------------------------------------------------------
// Types -- Flashcards
// ---------------------------------------------------------------------------

type Flashcard struct {
	ID         string     `json:"id"`
	Front      string     `json:"front"`
	Back       string     `json:"back"`
	Difficulty Difficulty `json:"difficulty"`
	Tags       []string   `json:"tags"`
	NextReview string     `json:"next_review,omitempty"`
}

type Flashcards struct {
	Topic string      `json:"topic"`
	Cards []Flashcard `json:"cards"`
	Count int         `json:"count"`
}

// ---------------------------------------------------------------------------
// Types -- Quiz
// ---------------------------------------------------------------------------

type Choice struct {
	Label     string `json:"label"`
	Text      string `json:"text"`
	IsCorrect bool   `json:"is_correct"`
}

type Question struct {
	ID            string       `json:"id"`
	Text          string       `json:"text"`
	QuestionType  QuestionType `json:"question_type"`
	Choices       []Choice     `json:"choices"`
	CorrectAnswer string       `json:"correct_answer"`
	Explanation   string       `json:"explanation"`
	BloomLevel    BloomLevel   `json:"bloom_level"`
}

type Quiz struct {
	ID          string     `json:"id"`
	Topic       string     `json:"topic"`
	Questions   []Question `json:"questions"`
	TotalPoints int        `json:"total_points"`
	CreatedAt   string     `json:"created_at"`
}

// ---------------------------------------------------------------------------
// Types -- Knowledge Base
// ---------------------------------------------------------------------------

type KBEntry struct {
	ID        string   `json:"id"`
	Topic     string   `json:"topic"`
	Content   string   `json:"content"`
	Tags      []string `json:"tags"`
	CreatedAt string   `json:"created_at"`
	UpdatedAt string   `json:"updated_at,omitempty"`
}

type KBResult struct {
	Action  KBAction `json:"action"`
	Success bool     `json:"success"`
	Entry   *KBEntry `json:"entry,omitempty"`
	Message string   `json:"message"`
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const dataDir = "{{DATA_DIR}}"

func shortID(n int) string {
	const chars = "abcdef0123456789"
	b := make([]byte, n)
	for i := range b {
		b[i] = chars[rand.Intn(len(chars))]
	}
	return string(b)
}

func topicSlug(topic string) string {
	h := sha256.Sum256([]byte(strings.ToLower(topic)))
	return fmt.Sprintf("%x", h[:8])
}

func kbFilePath(topic string) string {
	return filepath.Join(dataDir, "knowledge_base", topicSlug(topic)+".json")
}

func clamp(val, lo, hi int) int {
	if val < lo {
		return lo
	}
	if val > hi {
		return hi
	}
	return val
}

func nowISO() string {
	return time.Now().UTC().Format(time.RFC3339)
}

// ---------------------------------------------------------------------------
// Tool: LearningPath
// ---------------------------------------------------------------------------

// LearningPath generates a personalized learning plan based on the subject,
// learner level, and stated goals.
func LearningPath(subject, level string, goals []string) (*LearningPlan, error) {
	diff, err := ParseDifficulty(level)
	if err != nil {
		return nil, err
	}

	baseDays := map[Difficulty]int{
		DifficultyBeginner:     7,
		DifficultyIntermediate: 10,
		DifficultyAdvanced:     14,
	}

	milestones := make([]Milestone, 0, len(goals))
	totalDays := 0
	slug := strings.ToLower(strings.ReplaceAll(subject, " ", "-"))

	for i, goal := range goals {
		d := baseDays[diff]
		totalDays += d
		milestones = append(milestones, Milestone{
			Title:        fmt.Sprintf("Milestone %d: %s", i+1, goal),
			Description:  fmt.Sprintf("Work toward: %s", goal),
			DurationDays: d,
			Resources: []string{
				fmt.Sprintf("{{RESOURCE_BASE_URL}}/%s/m%d", slug, i+1),
			},
			Objectives: []string{goal},
		})
	}

	return &LearningPlan{
		ID:                shortID(12),
		Subject:           subject,
		Level:             diff,
		Goals:             goals,
		Milestones:        milestones,
		TotalDurationDays: totalDays,
		CreatedAt:         nowISO(),
	}, nil
}

// ---------------------------------------------------------------------------
// Tool: FlashcardGenerator
// ---------------------------------------------------------------------------

// FlashcardGenerator creates a set of flashcards for the given topic.
func FlashcardGenerator(topic string, count int, difficulty string) (*Flashcards, error) {
	count = clamp(count, 1, 50)
	diff, err := ParseDifficulty(difficulty)
	if err != nil {
		return nil, err
	}

	cards := make([]Flashcard, 0, count)
	for i := 0; i < count; i++ {
		cards = append(cards, Flashcard{
			ID:         shortID(8),
			Front:      fmt.Sprintf("[%s] Question %d ({{LLM_GENERATED_FRONT}})", topic, i+1),
			Back:       fmt.Sprintf("Answer %d ({{LLM_GENERATED_BACK}})", i+1),
			Difficulty: diff,
			Tags:       []string{strings.ToLower(topic)},
		})
	}

	return &Flashcards{Topic: topic, Cards: cards, Count: len(cards)}, nil
}

// ---------------------------------------------------------------------------
// Tool: QuizEngine
// ---------------------------------------------------------------------------

// QuizEngine generates quiz questions for the specified topic.
func QuizEngine(topic string, count int, questionType string) (*Quiz, error) {
	count = clamp(count, 1, 30)
	qType, err := ParseQuestionType(questionType)
	if err != nil {
		return nil, err
	}

	questions := make([]Question, 0, count)
	for i := 0; i < count; i++ {
		var choices []Choice
		correct := fmt.Sprintf("{{LLM_GENERATED_ANSWER_%d}}", i+1)

		switch qType {
		case QuestionMultipleChoice:
			choices = []Choice{
				{Label: "A", Text: fmt.Sprintf("Option A ({{LLM_OPTION_A_%d}})", i+1), IsCorrect: false},
				{Label: "B", Text: fmt.Sprintf("Option B ({{LLM_OPTION_B_%d}})", i+1), IsCorrect: false},
				{Label: "C", Text: fmt.Sprintf("Option C ({{LLM_OPTION_C_%d}})", i+1), IsCorrect: false},
				{Label: "D", Text: fmt.Sprintf("Option D ({{LLM_OPTION_D_%d}})", i+1), IsCorrect: true},
			}
			correct = "D"
		case QuestionTrueFalse:
			choices = []Choice{
				{Label: "T", Text: "True", IsCorrect: false},
				{Label: "F", Text: "False", IsCorrect: true},
			}
			correct = "F"
		}

		questions = append(questions, Question{
			ID:            shortID(8),
			Text:          fmt.Sprintf("[%s] Question %d ({{LLM_GENERATED_QUESTION_%d}})", topic, i+1, i+1),
			QuestionType:  qType,
			Choices:       choices,
			CorrectAnswer: correct,
			Explanation:   fmt.Sprintf("{{LLM_GENERATED_EXPLANATION_%d}}", i+1),
			BloomLevel:    BloomUnderstand,
		})
	}

	return &Quiz{
		ID:          shortID(12),
		Topic:       topic,
		Questions:   questions,
		TotalPoints: len(questions),
		CreatedAt:   nowISO(),
	}, nil
}

// ---------------------------------------------------------------------------
// Tool: KnowledgeBase
// ---------------------------------------------------------------------------

// KnowledgeBase performs CRUD operations on knowledge base entries stored as
// JSON files on disk.
func KnowledgeBase(action, topic, content string) (*KBResult, error) {
	act := KBAction(strings.ToLower(action))
	fp := kbFilePath(topic)

	switch act {
	case KBActionCreate:
		if _, err := os.Stat(fp); err == nil {
			return &KBResult{Action: act, Success: false, Message: fmt.Sprintf("Entry already exists for '%s'. Use 'update' instead.", topic)}, nil
		}
		entry := &KBEntry{
			ID:        shortID(12),
			Topic:     topic,
			Content:   content,
			Tags:      []string{strings.ToLower(topic)},
			CreatedAt: nowISO(),
		}
		if err := saveKBEntry(fp, entry); err != nil {
			return nil, fmt.Errorf("failed to save entry: %w", err)
		}
		return &KBResult{Action: act, Success: true, Entry: entry, Message: "Entry created."}, nil

	case KBActionRead:
		entry, err := loadKBEntry(fp)
		if err != nil {
			return &KBResult{Action: act, Success: false, Message: fmt.Sprintf("No entry found for '%s'.", topic)}, nil
		}
		return &KBResult{Action: act, Success: true, Entry: entry}, nil

	case KBActionUpdate:
		entry, err := loadKBEntry(fp)
		if err != nil {
			return &KBResult{Action: act, Success: false, Message: fmt.Sprintf("No entry found for '%s'. Use 'create' first.", topic)}, nil
		}
		entry.Content = content
		entry.UpdatedAt = nowISO()
		if err := saveKBEntry(fp, entry); err != nil {
			return nil, fmt.Errorf("failed to update entry: %w", err)
		}
		return &KBResult{Action: act, Success: true, Entry: entry, Message: "Entry updated."}, nil

	case KBActionDelete:
		if err := os.Remove(fp); err != nil {
			if errors.Is(err, os.ErrNotExist) {
				return &KBResult{Action: act, Success: false, Message: fmt.Sprintf("No entry found for '%s'.", topic)}, nil
			}
			return nil, fmt.Errorf("failed to delete entry: %w", err)
		}
		return &KBResult{Action: act, Success: true, Message: fmt.Sprintf("Entry for '%s' deleted.", topic)}, nil

	default:
		return nil, fmt.Errorf("unknown action: %s", action)
	}
}

// ---------------------------------------------------------------------------
// File helpers
// ---------------------------------------------------------------------------

func saveKBEntry(fp string, entry *KBEntry) error {
	if err := os.MkdirAll(filepath.Dir(fp), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(entry, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(fp, data, 0o644)
}

func loadKBEntry(fp string) (*KBEntry, error) {
	data, err := os.ReadFile(fp)
	if err != nil {
		return nil, err
	}
	var entry KBEntry
	if err := json.Unmarshal(data, &entry); err != nil {
		return nil, err
	}
	return &entry, nil
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

Standard library only. No external dependencies required.
