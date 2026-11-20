# Scenic Garmin Watch Face

A custom watch face for the **Garmin Forerunner 55**, built in **Monkey C** with Garmin's Connect IQ SDK. The scenery changes with the weekday, season, time of day, and available weather data.

Created by **Hudson Blattman**, with ChatGPT as a coding and learning partner.

## Features

- Large time display that follows the watch's 12-hour or 24-hour preference.
- Date, battery percentage, and a notification indicator.
- Red, yellow, and green battery levels, plus an overlaid charging symbol.
- Outdoor temperature with a thermometer whose fill height and color change with temperature.
- Seven weekday landscapes with seasonal details.
- Sunrise, daytime, sunset, and nighttime appearances.
- Dithered sky, ocean, and ground textures that suggest additional shades using the watch's eight supported colors.
- Moving clouds with varied shapes, flat bottoms, and highlights near the sun.
- Fixed cloud movement speed with left/right direction based on available wind-bearing data.
- Stars, an approximate lunar phase, and decorative sun and moon paths.
- Sun and moon reflections on the lake and ocean.
- Weather effects for rain, heavy rain, snow, heavy snow, rain/snow mix, wind, fog, mist, and thunderstorms.
- Holiday decorations positioned for each landscape.

## Weekly landscapes

| Day | Scene |
| --- | --- |
| Sunday | Rolling hills and meadow |
| Monday | Forest |
| Tuesday | Lake and cabin |
| Wednesday | City skyline |
| Thursday | Desert dunes and cacti |
| Friday | Mountains |
| Saturday | Ocean islands |

Seasons use a Northern Hemisphere calendar: spring in March-May, summer in June-August, fall in September-November, and winter in December-February.

## Holidays

| Holiday | Date | Decorations |
| --- | --- | --- |
| New Year's Day | January 1 | Fireworks across the sky |
| Valentine's Day | February 14 | Hearts |
| St. Patrick's Day | March 17 | Four-leaf clover |
| Easter | Calculated each year | Colorful eggs across the landscape |
| Independence Day | July 4 | U.S. flag and fireworks |
| Halloween | October 31 | Pumpkins and jack-o'-lanterns |
| U.S. Thanksgiving | Fourth Thursday in November | Cornucopia |
| Christmas | December 25 | Decorated tree and scattered presents |

Decorations appear on the holiday itself. Easter follows the Western Gregorian calculation.

## Build and run

### Requirements

- Visual Studio Code with Garmin's **Monkey C** extension.
- Garmin **Connect IQ SDK Manager** and an installed SDK.
- Forerunner 55 device support installed through SDK Manager.
- A local Garmin developer signing key.

### Simulator

1. Clone or download this repository and open the folder containing `monkey.jungle` in VS Code.
2. Configure the Monkey C extension to use your installed SDK and local developer key.
3. Check that the Forerunner 55 is included in `manifest.xml`.
4. Run the Monkey C build/run command, selecting the Forerunner 55 simulator target.
5. Use the Connect IQ simulator to preview the watch face.

On newer simulators, **Settings > Display Mode > Always-Active**, followed by **High Power**, triggers the sleep/wake transition used by the animation code.

### Install on your own watch

1. Build the project for the physical Forerunner 55 target, rather than the simulator target.
2. Connect the watch to your computer using its USB cable.
3. Copy the compiled `.prg` file into the watch's `GARMIN/APPS` directory.
4. Safely disconnect the watch and select the installed face through its watch-face menu.

This is a source project; a developer key and local build are required unless a compiled release is provided separately.

## Weather and animation behavior

The watch face uses Garmin's cached weather information. Conditions can be missing or out of date, and outdoor weather temperature is not a reading from a thermometer in the watch. Missing temperature is displayed as `--`.

Sunrise and sunset use the weather observation location when available. If solar data is unavailable, the fallback times are **6 a.m. sunrise** and **6 p.m. sunset**.

Smooth animation and rapid lightning flashes run while the watch face is awake. In low-power mode, scenery changes appear on Garmin's normal updates. Small thunderstorm bolts remain part of the scenery without requiring the awake animation timer.

The moon shape approximates the lunar phase. The sun and moon travel along decorative paths; these are not precise astronomical position or moonrise calculations. The lightning flash is a visual drawing effect, not a backlight adjustment or a weather-alert system.

## Preview different weather

Inside `onUpdate()` in `source/Watch_FaceView.mc`, place a temporary assignment immediately before `updateWeatherMotion(conditions, weatherScene);`:

```monkeyc
weatherScene = 8; // Preview thunderstorms
```

| Value | Weather scene |
| --- | --- |
| 0 | Partly cloudy / default |
| 1 | Clear |
| 2 | Overcast |
| 3 | Rain |
| 4 | Snow |
| 5 | Windy |
| 6 | Fog |
| 7 | Mist / haze |
| 8 | Thunderstorms |
| 9 | Heavy rain |
| 10 | Heavy snow |
| 11 | Rain and snow together |

Comment out or remove the assignment after testing to restore actual weather. Also check for temporary `sceneId`, `season`, or `holiday` overrides before installing a normal-use build.

## Project files

| Path | Purpose |
| --- | --- |
| `source/` | Monkey C application, watch-face, and supporting code |
| `resources/` | Images, texture bitmaps, layouts, strings, and settings |
| `manifest.xml` | Application metadata, supported devices, and permissions |
| `monkey.jungle` | Build configuration |
| `.gitignore` | Files excluded from Git tracking |

Keep resource IDs and filenames consistent with the references in the code. Preserve the resource folder structure when downloading or uploading the project.

## Signing keys and generated files

Keep the Garmin developer signing key outside the repository. Generated output such as `bin/`, `gen/`, `.prg`, and `.iq` files can be rebuilt and does not need to be committed.

When uploading through GitHub's website, manually exclude those files: the web uploader does not apply `.gitignore` rules.
