# Smart Home Tools (Go)

Go tool implementations for smart home device control, automation, energy monitoring, and scene management.

## Dependencies

```
go get github.com/go-resty/resty/v2
```

## Generated File: `tools/smarthome/smarthome.go`

```go
// Package smarthome provides smart home domain tools for {{PROJECT_NAME}}.
package smarthome

import (
	"encoding/json"
	"fmt"
	"math"
	"time"

	"github.com/go-resty/resty/v2"
)

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

type DeviceCategory string

const (
	CategoryLight     DeviceCategory = "light"
	CategorySwitch    DeviceCategory = "switch"
	CategoryThermostat DeviceCategory = "thermostat"
	CategoryLock      DeviceCategory = "lock"
	CategorySensor    DeviceCategory = "sensor"
	CategoryCamera    DeviceCategory = "camera"
	CategoryBlinds    DeviceCategory = "blinds"
	CategorySpeaker   DeviceCategory = "speaker"
	CategoryAppliance DeviceCategory = "appliance"
)

type DeviceState struct {
	DeviceID    string                 `json:"device_id"`
	Name        string                 `json:"name"`
	Category    DeviceCategory         `json:"category"`
	Online      bool                   `json:"online"`
	State       map[string]interface{} `json:"state"`
	LastUpdated time.Time              `json:"last_updated"`
}

type Trigger struct {
	Type   string                 `json:"type"`
	Config map[string]interface{} `json:"config,omitempty"`
}

type Condition struct {
	DeviceID  string      `json:"device_id,omitempty"`
	Attribute string      `json:"attribute"`
	Operator  string      `json:"operator"`
	Value     interface{} `json:"value"`
}

type AutomationAction struct {
	DeviceID string                 `json:"device_id"`
	Action   string                 `json:"action"`
	Params   map[string]interface{} `json:"params,omitempty"`
}

type Rule struct {
	RuleID        string             `json:"rule_id"`
	Name          string             `json:"name"`
	Enabled       bool               `json:"enabled"`
	Trigger       Trigger            `json:"trigger"`
	Conditions    []Condition        `json:"conditions,omitempty"`
	Actions       []AutomationAction `json:"actions,omitempty"`
	CreatedAt     time.Time          `json:"created_at"`
	LastTriggered *time.Time         `json:"last_triggered,omitempty"`
}

type EnergyEntry struct {
	DeviceID   string  `json:"device_id,omitempty"`
	DeviceName string  `json:"device_name,omitempty"`
	Period     string  `json:"period"`
	KWh        float64 `json:"kwh"`
	Cost       float64 `json:"cost"`
	AvgWatts   float64 `json:"avg_watts"`
}

type EnergyReport struct {
	Period    string        `json:"period"`
	Start     time.Time     `json:"start"`
	End       time.Time     `json:"end"`
	Entries   []EnergyEntry `json:"entries"`
	TotalKWh  float64       `json:"total_kwh"`
	TotalCost float64       `json:"total_cost"`
}

type Scene struct {
	SceneID   string                   `json:"scene_id"`
	Name      string                   `json:"name"`
	Devices   []map[string]interface{} `json:"devices"`
	CreatedAt time.Time                `json:"created_at"`
}

// ---------------------------------------------------------------------------
// Hub client
// ---------------------------------------------------------------------------

type Hub struct {
	client *resty.Client
}

func NewHub(baseURL, token string) *Hub {
	c := resty.New().
		SetBaseURL(baseURL).
		SetAuthToken(token).
		SetHeader("Content-Type", "application/json")
	return &Hub{client: c}
}

func (h *Hub) get(path string, result interface{}) error {
	resp, err := h.client.R().SetResult(result).Get(path)
	if err != nil {
		return err
	}
	if resp.IsError() {
		return fmt.Errorf("hub API error: %d %s", resp.StatusCode(), resp.Status())
	}
	return nil
}

func (h *Hub) post(path string, body, result interface{}) error {
	resp, err := h.client.R().SetBody(body).SetResult(result).Post(path)
	if err != nil {
		return err
	}
	if resp.IsError() {
		return fmt.Errorf("hub API error: %d %s", resp.StatusCode(), resp.Status())
	}
	return nil
}

func (h *Hub) patch(path string, body, result interface{}) error {
	resp, err := h.client.R().SetBody(body).SetResult(result).Patch(path)
	if err != nil {
		return err
	}
	if resp.IsError() {
		return fmt.Errorf("hub API error: %d %s", resp.StatusCode(), resp.Status())
	}
	return nil
}

func (h *Hub) delete(path string) error {
	resp, err := h.client.R().Delete(path)
	if err != nil {
		return err
	}
	if resp.IsError() {
		return fmt.Errorf("hub API error: %d %s", resp.StatusCode(), resp.Status())
	}
	return nil
}

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

type Tools struct {
	hub        *Hub
	energyRate float64
}

func New(baseURL, token string, energyRate float64) *Tools {
	return &Tools{
		hub:        NewHub(baseURL, token),
		energyRate: energyRate,
	}
}

// DeviceControl sends an action to a smart home device and returns its updated state.
func (t *Tools) DeviceControl(deviceID, action string, params map[string]interface{}) (*DeviceState, error) {
	// Fetch current device to check category
	var device map[string]interface{}
	if err := t.hub.get(fmt.Sprintf("/devices/%s", deviceID), &device); err != nil {
		return nil, fmt.Errorf("failed to fetch device %s: %w", deviceID, err)
	}

	var result map[string]interface{}
	path := fmt.Sprintf("/devices/%s/%s", deviceID, action)
	if err := t.hub.post(path, params, &result); err != nil {
		return nil, fmt.Errorf("failed to control device %s: %w", deviceID, err)
	}

	name, _ := result["name"].(string)
	if name == "" {
		name = deviceID
	}
	cat, _ := result["category"].(string)
	if cat == "" {
		cat = "switch"
	}
	online, _ := result["online"].(bool)
	stateMap, _ := result["state"].(map[string]interface{})

	return &DeviceState{
		DeviceID:    deviceID,
		Name:        name,
		Category:    DeviceCategory(cat),
		Online:      online,
		State:       stateMap,
		LastUpdated: time.Now().UTC(),
	}, nil
}

// AutomationRules performs CRUD operations on automation rules.
func (t *Tools) AutomationRules(action string, opts RuleOptions) (interface{}, error) {
	switch action {
	case "create":
		if opts.Name == "" || opts.Trigger == nil || len(opts.Actions) == 0 {
			return nil, fmt.Errorf("create requires Name, Trigger, and Actions")
		}
		body := map[string]interface{}{
			"name":       opts.Name,
			"enabled":    opts.Enabled,
			"trigger":    opts.Trigger,
			"conditions": opts.Conditions,
			"actions":    opts.Actions,
		}
		var result Rule
		if err := t.hub.post("/automations", body, &result); err != nil {
			return nil, err
		}
		return &result, nil

	case "get":
		if opts.RuleID == "" {
			return nil, fmt.Errorf("get requires RuleID")
		}
		var result Rule
		if err := t.hub.get(fmt.Sprintf("/automations/%s", opts.RuleID), &result); err != nil {
			return nil, err
		}
		return &result, nil

	case "list":
		var wrapper struct {
			Rules []Rule `json:"rules"`
		}
		if err := t.hub.get("/automations", &wrapper); err != nil {
			return nil, err
		}
		return wrapper.Rules, nil

	case "update":
		if opts.RuleID == "" {
			return nil, fmt.Errorf("update requires RuleID")
		}
		body := make(map[string]interface{})
		if opts.Name != "" {
			body["name"] = opts.Name
		}
		if opts.Trigger != nil {
			body["trigger"] = opts.Trigger
		}
		if opts.Conditions != nil {
			body["conditions"] = opts.Conditions
		}
		if opts.Actions != nil {
			body["actions"] = opts.Actions
		}
		body["enabled"] = opts.Enabled
		var result Rule
		if err := t.hub.patch(fmt.Sprintf("/automations/%s", opts.RuleID), body, &result); err != nil {
			return nil, err
		}
		return &result, nil

	case "delete":
		if opts.RuleID == "" {
			return nil, fmt.Errorf("delete requires RuleID")
		}
		if err := t.hub.delete(fmt.Sprintf("/automations/%s", opts.RuleID)); err != nil {
			return nil, err
		}
		return &Rule{RuleID: opts.RuleID, Name: "(deleted)"}, nil

	default:
		return nil, fmt.Errorf("unknown action: %s", action)
	}
}

type RuleOptions struct {
	RuleID     string
	Name       string
	Enabled    bool
	Trigger    *Trigger
	Conditions []Condition
	Actions    []AutomationAction
}

// EnergyMonitor retrieves energy consumption data for the given period.
func (t *Tools) EnergyMonitor(period string, deviceID string) (*EnergyReport, error) {
	path := fmt.Sprintf("/energy?period=%s", period)
	if deviceID != "" {
		path += fmt.Sprintf("&device_id=%s", deviceID)
	}

	var data struct {
		Entries []struct {
			DeviceID   string  `json:"device_id"`
			DeviceName string  `json:"device_name"`
			KWh        float64 `json:"kwh"`
			AvgWatts   float64 `json:"avg_watts"`
		} `json:"entries"`
	}
	if err := t.hub.get(path, &data); err != nil {
		return nil, fmt.Errorf("failed to fetch energy data: %w", err)
	}

	var totalKWh float64
	entries := make([]EnergyEntry, 0, len(data.Entries))
	for _, item := range data.Entries {
		totalKWh += item.KWh
		entries = append(entries, EnergyEntry{
			DeviceID:   item.DeviceID,
			DeviceName: item.DeviceName,
			Period:     period,
			KWh:        roundTo(item.KWh, 3),
			Cost:       roundTo(item.KWh*t.energyRate, 2),
			AvgWatts:   roundTo(item.AvgWatts, 1),
		})
	}

	periodHours := map[string]int{
		"hour": 1, "day": 24, "week": 168, "month": 720, "year": 8760,
	}
	hours := periodHours[period]
	if hours == 0 {
		hours = 24
	}
	now := time.Now().UTC()

	return &EnergyReport{
		Period:    period,
		Start:     now.Add(-time.Duration(hours) * time.Hour),
		End:       now,
		Entries:   entries,
		TotalKWh:  roundTo(totalKWh, 3),
		TotalCost: roundTo(totalKWh*t.energyRate, 2),
	}, nil
}

// SceneManager performs CRUD operations and activation of device scenes.
func (t *Tools) SceneManager(action string, opts SceneOptions) (interface{}, error) {
	switch action {
	case "create":
		if opts.Name == "" || len(opts.Devices) == 0 {
			return nil, fmt.Errorf("create requires Name and Devices")
		}
		var result Scene
		body := map[string]interface{}{"name": opts.Name, "devices": opts.Devices}
		if err := t.hub.post("/scenes", body, &result); err != nil {
			return nil, err
		}
		return &result, nil

	case "activate":
		if opts.SceneID == "" {
			return nil, fmt.Errorf("activate requires SceneID")
		}
		var result Scene
		if err := t.hub.post(fmt.Sprintf("/scenes/%s/activate", opts.SceneID), nil, &result); err != nil {
			return nil, err
		}
		return &result, nil

	case "get":
		if opts.SceneID == "" {
			return nil, fmt.Errorf("get requires SceneID")
		}
		var result Scene
		if err := t.hub.get(fmt.Sprintf("/scenes/%s", opts.SceneID), &result); err != nil {
			return nil, err
		}
		return &result, nil

	case "list":
		var wrapper struct {
			Scenes []Scene `json:"scenes"`
		}
		if err := t.hub.get("/scenes", &wrapper); err != nil {
			return nil, err
		}
		return wrapper.Scenes, nil

	case "update":
		if opts.SceneID == "" {
			return nil, fmt.Errorf("update requires SceneID")
		}
		body := make(map[string]interface{})
		if opts.Name != "" {
			body["name"] = opts.Name
		}
		if opts.Devices != nil {
			body["devices"] = opts.Devices
		}
		var result Scene
		if err := t.hub.patch(fmt.Sprintf("/scenes/%s", opts.SceneID), body, &result); err != nil {
			return nil, err
		}
		return &result, nil

	case "delete":
		if opts.SceneID == "" {
			return nil, fmt.Errorf("delete requires SceneID")
		}
		if err := t.hub.delete(fmt.Sprintf("/scenes/%s", opts.SceneID)); err != nil {
			return nil, err
		}
		return &Scene{SceneID: opts.SceneID, Name: "(deleted)"}, nil

	default:
		return nil, fmt.Errorf("unknown action: %s", action)
	}
}

type SceneOptions struct {
	SceneID string
	Name    string
	Devices []map[string]interface{}
}

func roundTo(val float64, places int) float64 {
	p := math.Pow(10, float64(places))
	return math.Round(val*p) / p
}

// MarshalJSON is a convenience for serializing any tool result.
func MarshalJSON(v interface{}) ([]byte, error) {
	return json.MarshalIndent(v, "", "  ")
}
```

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project |
| `{{HUB_URL}}` | Hub API base URL (passed to `NewHub`) |
| `{{HUB_TOKEN}}` | Hub API authentication token (passed to `NewHub`) |
| `{{ENERGY_RATE_FLOAT}}` | Energy rate as a float, e.g. `0.12` (passed to `New`) |
