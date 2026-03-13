# Smart Home Domain Knowledge

Reference knowledge for smart home assistants covering protocols, device categories, automation patterns, and energy optimization.

## Communication Protocols

### Zigbee
- Low-power mesh network operating on 2.4 GHz (IEEE 802.15.4).
- Range: 10-20 meters indoors; mesh topology extends effective range.
- Supports up to ~200 devices per coordinator.
- Common profiles: Zigbee Home Automation (ZHA), Zigbee Light Link (ZLL).
- Requires a Zigbee coordinator (USB stick or built into hub).

### Z-Wave
- Sub-GHz mesh network (908.42 MHz in US, 868.42 MHz in EU).
- Better wall penetration than Zigbee due to lower frequency.
- Maximum 232 devices per network with up to 4 hops.
- Z-Wave Plus (Series 500/700) improves range and battery life.
- Requires a Z-Wave controller; all devices must be same regional frequency.

### Matter
- IP-based standard (over Wi-Fi, Thread, Ethernet) by the Connectivity Standards Alliance.
- Multi-admin: single device can be controlled by multiple ecosystems simultaneously.
- Thread border routers bridge Thread mesh devices to IP networks.
- Commissioning uses QR codes or NFC for secure device onboarding.
- Supported by Apple, Google, Amazon, Samsung from launch.

### Wi-Fi
- Direct IP connectivity, no hub required in most cases.
- Higher power consumption than Zigbee/Z-Wave; unsuitable for battery devices.
- Can congest home networks when many devices are connected.
- Common for cameras, speakers, and smart displays.

### Bluetooth / BLE
- Short range (typically under 10 meters), low energy.
- Often used for initial device setup and proximity-based control.
- Bluetooth Mesh extends range for lighting networks.

## Device Categories

| Category | Examples | Common Actions |
|---|---|---|
| Lights | Bulbs, strips, switches | turn_on, turn_off, set_brightness, set_color, set_color_temp |
| Thermostats | Smart HVAC controllers | set_temperature, set_mode (heat/cool/auto/off), set_fan |
| Locks | Deadbolts, smart handles | lock, unlock, get_status |
| Sensors | Motion, door/window, temperature, humidity, leak | get_reading (read-only) |
| Cameras | Indoor, outdoor, doorbell | get_snapshot, start_stream, set_mode (home/away) |
| Blinds/Shades | Motorized window coverings | open, close, set_position (0-100%) |
| Speakers | Smart speakers, soundbars | play, pause, set_volume, tts_speak |
| Switches/Plugs | Smart outlets, relay switches | turn_on, turn_off, toggle |
| Appliances | Washers, robot vacuums, ovens | start, stop, set_mode |

## Automation Patterns

### Time-Based
- Fixed schedule: "Turn off all lights at 11:00 PM."
- Relative to sun: "Open blinds 30 minutes after sunrise."
- Recurring: "Run robot vacuum every Tuesday and Friday at 10:00 AM."

### Event-Driven
- Device state change: "When front door unlocks, turn on hallway light."
- Sensor threshold: "When humidity exceeds 65%, turn on dehumidifier."
- Presence detection: "When last person leaves geofence, activate Away scene."

### Conditional Logic
- Time window guards: "Only trigger motion lights between sunset and sunrise."
- Device state guards: "Only run AC if thermostat reads above 76F."
- Mode guards: "Only send camera alerts when mode is Away."

### Common Rule Structures
1. **IF** trigger fires **AND** all conditions met **THEN** execute actions.
2. Rules should have unique names and can be enabled/disabled without deletion.
3. Conflicting rules (same device, opposing actions) should be flagged at creation time.
4. Rate-limit rapid-fire triggers to avoid device flooding (minimum 5-second debounce).

## Energy Optimization

### Monitoring Strategies
- Track per-device consumption to identify phantom loads and high-usage devices.
- Compare usage across identical periods (this week vs. last week) for trend analysis.
- Set budget thresholds and alert when projected monthly cost exceeds target.

### Reduction Techniques
- **HVAC scheduling**: Set back temperature 2-3 degrees during sleep and away hours.
- **Vampire load elimination**: Use smart plugs to cut power to standby electronics.
- **Lighting optimization**: Automate lights off in unoccupied rooms via occupancy sensors.
- **Peak shaving**: Shift high-draw appliances (dryer, dishwasher, EV charger) to off-peak hours.
- **Solar integration**: When solar production exceeds consumption, pre-cool/pre-heat the home.

### Cost Calculation
- `cost = kwh * rate_per_kwh`
- Time-of-use rates vary by utility; store rate tiers in configuration.
- Present costs alongside consumption for user-actionable insights.

## Safety Considerations

- Never disable smoke/CO detectors or override manufacturer safety shutoffs.
- Security devices (locks, alarms, garage doors) require explicit user confirmation.
- Log all security-related actions with timestamps for audit trails.
- Validate automation rules cannot create unsafe conditions (e.g., space heater on + nobody home).
- Rate-limit device commands to prevent relay damage from rapid toggling.
- Ensure fail-safe defaults: if hub loses connectivity, devices should hold last safe state.

## Placeholders

| Placeholder | Description |
|---|---|
| `{{HUB_PLATFORM}}` | Hub platform name (Home Assistant, SmartThings, Hubitat, etc.) |
| `{{ENERGY_RATE}}` | Display energy rate, e.g. `$0.12/kWh` |
| `{{TEMP_UNIT}}` | Temperature unit preference |
