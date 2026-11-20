import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;
import Toybox.Math;
import Toybox.Timer;

class Watch_FaceView extends WatchUi.WatchFace {

    private var sunsetSky as WatchUi.BitmapResource? = null;
    private var daySky as WatchUi.BitmapResource? = null;
    private var oceanBitmap as WatchUi.BitmapResource? = null;
    private var oceanPhase = -1;
    private var groundBitmap as WatchUi.BitmapResource? = null;
    private var groundKey = -1;
    
    private var _weatherTimer as Timer.Timer? = null;
    private var _weatherAwake = false;
    private var _weatherLastTick = -1;
    private var _weatherSeconds = 0.0;

    private var _cloudDistance = 0.0;
    private var _cloudVelocity = 1.0;
    private var _windDirection = 1;

    private var _flashActive = false;
    private var _flashUntil = 0.0;
    private var _nextFlash = 0.0;
    private var _lightningX = 110;
    private var _gustStart = 0.0;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        sunsetSky = WatchUi.loadResource(
            Rez.Drawables.SunsetSky
        ) as WatchUi.BitmapResource;

        daySky = WatchUi.loadResource(
            Rez.Drawables.DaySky
        ) as WatchUi.BitmapResource;
    }

    function onShow() as Void {
    }

    function onUpdate(dc as Dc) as Void {
        var now = Time.now();
        var clockTime = System.getClockTime();
        var settings = System.getDeviceSettings();

        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        var centerX = screenWidth / 2;

        // Time
        var hour = clockTime.hour;
        var hourText = "";

        if (settings.is24Hour) {
            hourText = hour.format("%02d");
        } else {
            if (hour > 12) {
                hour -= 12;
            } else if (hour == 0) {
                hour = 12;
            }

            hourText = hour.format("%d");
        }

        var timeText = hourText + ":" + clockTime.min.format("%02d");

        // Date
        var today = Gregorian.info(now, Time.FORMAT_MEDIUM);
        var dateText = Lang.format(
            "$1$ $2$ $3$",
            [today.day_of_week, today.month, today.day]
        );

        // Numeric calendar values, separate from the formatted date text.
        var calendarDate = Gregorian.info(Time.now(), Time.FORMAT_SHORT);

        // Sunday through Saturday:
        // 0 meadow, 1 forest, 2 lake, 3 city,
        // 4 desert, 5 mountains, 6 ocean islands
        var weekdayScenes = [0, 1, 2, 3, 4, 5, 6];

        var sceneId = weekdayScenes[calendarDate.day_of_week - 1];
        var season = getSeason(calendarDate.month);
        var holiday = getHoliday(
            calendarDate.year,
            calendarDate.month,
            calendarDate.day
        );
        //sceneId = 3; // Sunday; use 0–6 for Sunday–Saturday
        //season = 1;

        // Optional previews:
        // season = 3;  // 0 spring, 1 summer, 2 fall, 3 winter
        // holiday = 1; // 0 none, 1 Christmas, 2 Halloween, 3 Easter, 4 New Year

        // Battery
        var batteryStats = System.getSystemStats();
        var batteryLevel = batteryStats.battery;
        var isCharging = batteryStats.charging;
        var batteryText = batteryLevel.format("%.0f") + "%";

        // Cached outdoor weather
        var conditions = Weather.getCurrentConditions();
        var temperatureC = null;
        var temperatureText = "--";
        var weatherScene = 0;
        
        if (conditions != null) {
            weatherScene = getWeatherScene(conditions.condition);

            if (conditions.temperature != null) {
                temperatureC = conditions.temperature;
                var temperature = conditions.temperature;

                if (settings.temperatureUnits == System.UNIT_STATUTE) {
                    temperature = temperature * 1.8 + 32.0;
                    temperatureText = temperature.format("%.0f") + "F";
                } else {
                    temperatureText = temperature.format("%.0f") + "C";
                }
            }
        }

        // Temporary weather preview:
        // 0 partly cloudy/default, 1 clear, 2 overcast, 3 rain, 4 snow
        //weatherScene = 1;

        // weatherScene = 5;  // Wind streams
        // weatherScene = 6;  // Fog
        // weatherScene = 7;  // Mist
        // weatherScene = 8;  // Thunderstorm
        // weatherScene = 9;  // Heavy rain
        // weatherScene = 10; // Heavy snow

        updateWeatherMotion(conditions, weatherScene);

        // Solar times, with defaults when location/data is unavailable.
        var sunriseMinutes = 6 * 60;
        var sunSetMinutes = 18 * 60;

        if (conditions != null &&
            conditions.observationLocationPosition != null) {

            var solarLocation = conditions.observationLocationPosition;
            var sunriseMoment = Weather.getSunrise(solarLocation, now);
            var sunsetMoment = Weather.getSunset(solarLocation, now);

            if (sunriseMoment != null) {
                var sunriseInfo = Gregorian.info(
                    sunriseMoment,
                    Time.FORMAT_SHORT
                );

                sunriseMinutes = sunriseInfo.hour * 60 + sunriseInfo.min;
            }

            if (sunsetMoment != null) {
                var sunsetInfo = Gregorian.info(
                    sunsetMoment,
                    Time.FORMAT_SHORT
                );

                sunSetMinutes = sunsetInfo.hour * 60 + sunsetInfo.min;
            }
        }

        // Scene phases:
        // 0 night, 1 sunrise, 2 day, 3 sunset
        var morningStart = sunriseMinutes - 30;
        var morningEnd = sunriseMinutes + 30;
        var eveningStart = sunSetMinutes - 60;
        var eveningEnd = sunSetMinutes + 30;

        var currentMinutes = clockTime.hour * 60 + clockTime.min;
        var phase = 0;

        if (currentMinutes < morningStart ||
            currentMinutes >= eveningEnd) {
            phase = 0;
        } else if (currentMinutes < morningEnd) {
            phase = 1;
        } else if (currentMinutes < eveningStart) {
            phase = 2;
        } else {
            phase = 3;
        }

        // Decorative moon path from nightfall until morning.
        var nightStartMinutes = eveningEnd;
        var nightEndMinutes = (morningStart + 1440) % 1440;

        var nightDuration = (
            nightEndMinutes - nightStartMinutes + 1440
        ) % 1440;

        if (nightDuration <= 0) {
            nightDuration = 12 * 60;
        }

        var nightElapsed = (
            currentMinutes - nightStartMinutes + 1440
        ) % 1440;

        var moonProgress = nightElapsed.toFloat() / nightDuration;

        if (moonProgress < 0.0) {
            moonProgress = 0.0;
        } else if (moonProgress > 1.0) {
            moonProgress = 1.0;
        }

        var movingMoonX = (
            36 + (screenWidth - 72) * moonProgress
        ).toNumber();

        var movingMoonY = (
            47 - 23 * Math.sin(Math.PI * moonProgress)
        ).toNumber();

        // Decorative sun path between sunrise and sunset.
        var daylightMinutes = sunSetMinutes - sunriseMinutes;

        if (daylightMinutes <= 0) {
            daylightMinutes = 12 * 60;
        }

        var sunProgress = (
            currentMinutes - sunriseMinutes
        ).toFloat() / daylightMinutes;

        if (sunProgress < 0.0) {
            sunProgress = 0.0;
        } else if (sunProgress > 1.0) {
            sunProgress = 1.0;
        }

        var movingSunX = (
            36 + (screenWidth - 72) * sunProgress
        ).toNumber();

        var movingSunY = (
            60 - 35 * Math.sin(Math.PI * sunProgress)
        ).toNumber();

        // Redraw the complete scene.
        dc.clearClip();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawSceneBase(dc, sceneId, phase, season);

        if (phase == 2 && daySky != null) {
            dc.drawBitmap(0, 0, daySky);
        } else if ((phase == 1 || phase == 3) && sunsetSky != null) {
            dc.drawBitmap(0, 0, sunsetSky);
        }
        // drawStripedSky(dc, phase);

        var moonPhase = calculateMoonPhase();

        // Sun or moon
        if (phase == 0) {
            drawNightSky(
                dc,
                movingMoonX,
                movingMoonY,
                moonPhase
            );
        } else {
            dc.setClip(0, 0, screenWidth, 62);
            dc.setColor(
                Graphics.COLOR_YELLOW,
                Graphics.COLOR_TRANSPARENT
            );
            dc.fillCircle(movingSunX, movingSunY, 9);
            dc.clearClip();

            drawMovingClouds(
                dc,
                movingSunX,
                movingSunY,
                weatherScene
            );
        }

        // Overcast clouds, rain, or snow cover the sky.
        drawWeatherOverlay(dc, weatherScene, phase);

        // Reflections appear only on the lake and ocean.
        if (
            (weatherScene < 2 || weatherScene == 5) &&
            (sceneId == 2 || sceneId == 6)
        ) {
                if (phase == 1 || phase == 3) {
                drawSunReflection(dc, movingSunX);
            } else if (phase == 0) {
                drawMoonReflection(dc, movingMoonX, moonPhase);
            }
        }

        // Islands appear in front of the sky and reflections.
        drawDailyScene(dc, sceneId, phase, season, holiday);

        drawWeatherForeground(dc, weatherScene);

        // White text over the darker ground textures.
        dc.setColor(
            _flashActive ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE,
            Graphics.COLOR_TRANSPARENT
        );

        dc.drawText(
            centerX,
            100,
            Graphics.FONT_NUMBER_HOT,
            timeText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        dc.drawText(
            centerX,
            143,
            Graphics.FONT_SMALL,
            dateText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Battery
        var batteryX = centerX - 53;
        var dataY = 174;
        var batteryColor = Graphics.COLOR_GREEN;

        if (!isCharging) {
            if (batteryLevel <= 20) {
                batteryColor = Graphics.COLOR_RED;
            } else if (batteryLevel <= 50) {
                batteryColor = Graphics.COLOR_YELLOW;
            }
        }

        dc.setColor(
            _flashActive ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE,
            Graphics.COLOR_TRANSPARENT
        );
        dc.drawRectangle(batteryX, 168, 18, 11);
        dc.fillRectangle(batteryX + 18, 171, 3, 5);

        var batteryFillWidth = (batteryLevel * 12 / 100).toNumber();

        if (batteryFillWidth < 0) {
            batteryFillWidth = 0;
        } else if (batteryFillWidth > 12) {
            batteryFillWidth = 12;
        }

        if (batteryFillWidth > 0) {
            dc.setColor(batteryColor, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(
                batteryX + 3,
                171,
                batteryFillWidth,
                5
            );
        }

        if (isCharging) {
            var boltX = batteryX + 5;

            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([
                [boltX + 5, 168],
                [boltX,     174],
                [boltX + 3, 174],
                [boltX + 1, 179],
                [boltX + 8, 172],
                [boltX + 4, 172]
            ]);
        }

        dc.setColor(
            _flashActive ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE,
            Graphics.COLOR_TRANSPARENT
        );
        dc.drawText(
            batteryX + 27,
            dataY,
            Graphics.FONT_XTINY,
            batteryText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // Thermometer outline
        var thermoX = centerX + 20;

        dc.fillRoundedRectangle(thermoX, 164, 8, 15, 4);
        dc.fillCircle(thermoX + 4, 179, 5);

        if (temperatureC != null) {
            var mercuryColor = Graphics.COLOR_RED;

            if (temperatureC <= 0) {
                mercuryColor = 0x00FFFF;
            } else if (temperatureC < 10) {
                mercuryColor = 0x0000FF;
            }

            var mercuryFraction = (temperatureC + 20.0) / 60.0;

            if (mercuryFraction < 0.0) {
                mercuryFraction = 0.0;
            } else if (mercuryFraction > 1.0) {
                mercuryFraction = 1.0;
            }

            var mercuryHeight = (
                2 + mercuryFraction * 10
            ).toNumber();

            dc.setColor(mercuryColor, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(
                thermoX + 3,
                179 - mercuryHeight,
                2,
                mercuryHeight
            );
            dc.fillCircle(thermoX + 4, 179, 3);
        }

        dc.setColor(
            _flashActive ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE,
            Graphics.COLOR_TRANSPARENT
        );
        dc.drawText(
            thermoX + 14,
            dataY,
            Graphics.FONT_XTINY,
            temperatureText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        // White notification bubble with red dot
        if (settings.notificationCount > 0) {
            var bubbleX = centerX - 10;
            var bubbleY = 188;

            dc.fillRoundedRectangle(bubbleX, bubbleY, 20, 14, 3);
            dc.fillPolygon([
                [bubbleX + 4, bubbleY + 11],
                [bubbleX + 4, bubbleY + 17],
                [bubbleX + 10, bubbleY + 11]
            ]);

            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(bubbleX + 18, bubbleY + 2, 3);
        }

        dc.setColor(
            _flashActive ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE,
            Graphics.COLOR_TRANSPARENT
        );
    }

    function getWeatherScene(condition) as Number {
        // 0 partly cloudy, 1 clear, 2 overcast, 3 rain,
        // 4 snow, 5 windy, 6 fog, 7 mist/haze,
        // 8 thunderstorms, 9 heavy rain, 10 heavy snow.
        switch (condition) {
            case Weather.CONDITION_CLEAR:
            case Weather.CONDITION_MOSTLY_CLEAR:
            case Weather.CONDITION_FAIR:
                return 1;

            case Weather.CONDITION_MOSTLY_CLOUDY:
            case Weather.CONDITION_CLOUDY:
                return 2;

            case Weather.CONDITION_RAIN:
            case Weather.CONDITION_LIGHT_RAIN:
            case Weather.CONDITION_SHOWERS:
            case Weather.CONDITION_LIGHT_SHOWERS:
            case Weather.CONDITION_SCATTERED_SHOWERS:
            case Weather.CONDITION_DRIZZLE:
                return 3;

            case Weather.CONDITION_SNOW:
            case Weather.CONDITION_LIGHT_SNOW:
            case Weather.CONDITION_FLURRIES:
                return 4;

            case Weather.CONDITION_WINTRY_MIX:
            case Weather.CONDITION_RAIN_SNOW:
            case Weather.CONDITION_LIGHT_RAIN_SNOW:
            case Weather.CONDITION_HEAVY_RAIN_SNOW:
                return 11;

            case Weather.CONDITION_WINDY:
                return 5;

            case Weather.CONDITION_FOG:
                return 6;

            case Weather.CONDITION_MIST:
            case Weather.CONDITION_HAZY:
            case Weather.CONDITION_HAZE:
                return 7;

            case Weather.CONDITION_THUNDERSTORMS:
            case Weather.CONDITION_SCATTERED_THUNDERSTORMS:
                return 8;

            case Weather.CONDITION_HEAVY_RAIN:
            case Weather.CONDITION_HEAVY_SHOWERS:
                return 9;

            case Weather.CONDITION_HEAVY_SNOW:
                return 10;
        }

        return 0;
    }

    function drawMovingClouds(dc as Dc,sunX as Number,sunY as Number,weatherScene as Number) as Void {

        // Other weather scenes use the overcast overlay.
        if (weatherScene != 0 && weatherScene != 5) {
            return;
        }

        var screenWidth = dc.getWidth();
        var cloudCycle = 720;
        var cloudTravelSeconds = 300;
        var cloudTime = _cloudDistance;

        var clouds = [
            [0,   37, 0],
            [100, 25, 1],
            [260, 43, 2],
            [460, 31, 3],
            [570, 40, 4]
        ];

        for (var cloudIndex = 0; cloudIndex < clouds.size(); cloudIndex++) {
            var cloudAge = wrapWeather(
                cloudTime - clouds[cloudIndex][0],
                cloudCycle
            );

            if (cloudAge < cloudTravelSeconds) {
                var cloudProgress = cloudAge.toFloat() / cloudTravelSeconds;

                var cloudX = (
                    -30 + (screenWidth + 60) * cloudProgress
                ).toNumber();

                var cloudY = clouds[cloudIndex][1];
                var cloudShape = clouds[cloudIndex][2];

                dc.setColor(
                    Graphics.COLOR_WHITE,
                    Graphics.COLOR_TRANSPARENT
                );

                // Flat bottoms for every cloud.
                dc.setClip(0, 0, screenWidth, cloudY + 3);

                if (cloudShape == 0) {
                    dc.fillCircle(cloudX - 9, cloudY, 6);
                    dc.fillCircle(cloudX, cloudY - 4, 8);
                    dc.fillCircle(cloudX + 9, cloudY + 1, 6);
                    dc.fillRectangle(cloudX - 9, cloudY, 18, 6);

                } else if (cloudShape == 1) {
                    dc.fillCircle(cloudX - 5, cloudY, 4);
                    dc.fillCircle(cloudX + 1, cloudY - 2, 5);
                    dc.fillCircle(cloudX + 7, cloudY, 3);
                    dc.fillRectangle(cloudX - 5, cloudY, 12, 3);

                } else if (cloudShape == 2) {
                    dc.fillCircle(cloudX - 15, cloudY, 4);
                    dc.fillCircle(cloudX - 7, cloudY - 2, 6);
                    dc.fillCircle(cloudX + 3, cloudY - 1, 5);
                    dc.fillCircle(cloudX + 12, cloudY, 5);
                    dc.fillCircle(cloudX + 19, cloudY + 1, 3);
                    dc.fillRectangle(cloudX - 15, cloudY, 34, 4);

                } else if (cloudShape == 3) {
                    dc.fillCircle(cloudX - 10, cloudY, 5);
                    dc.fillCircle(cloudX - 3, cloudY - 6, 8);
                    dc.fillCircle(cloudX + 7, cloudY - 2, 6);
                    dc.fillCircle(cloudX + 14, cloudY + 1, 4);
                    dc.fillRectangle(cloudX - 10, cloudY, 24, 4);

                } else {
                    dc.fillCircle(cloudX - 14, cloudY, 3);
                    dc.fillCircle(cloudX - 5, cloudY - 1, 4);
                    dc.fillCircle(cloudX + 5, cloudY, 3);
                    dc.fillCircle(cloudX + 14, cloudY + 1, 3);
                    dc.fillRectangle(cloudX - 14, cloudY, 28, 3);
                }

                dc.clearClip();

                // Golden underside near the sun.
                var dx = cloudX - sunX;
                var dy = cloudY - sunY;
                var distanceSquared = dx * dx + dy * dy;

                if (distanceSquared < 3025 && sunY >= cloudY) {
                    var highlightLeft = -8;
                    var highlightRight = 10;

                    if (cloudShape == 1) {
                        highlightLeft = -5;
                        highlightRight = 7;
                    } else if (cloudShape == 2) {
                        highlightLeft = -14;
                        highlightRight = 15;
                    } else if (cloudShape == 3) {
                        highlightLeft = -10;
                        highlightRight = 14;
                    } else if (cloudShape == 4) {
                        highlightLeft = -14;
                        highlightRight = 14;
                    }

                    var strength = 1.0 - distanceSquared / 3025.0;
                    var middle = (highlightLeft + highlightRight) / 2.0;
                    var halfWidth = (
                        (highlightRight - highlightLeft) * strength / 2.0
                    );

                    dc.setColor(
                        Graphics.COLOR_YELLOW,
                        Graphics.COLOR_TRANSPARENT
                    );

                    dc.drawLine(
                        cloudX + (middle - halfWidth).toNumber(),
                        cloudY + 2,
                        cloudX + (middle + halfWidth).toNumber(),
                        cloudY + 2
                    );
                }
            }
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    function drawWeatherOverlay(dc as Dc,scene as Number,phase as Number) as Void {
        var rain = scene == 3 || scene == 8 || scene == 9;
        var snow = scene == 4 || scene == 10;
        var mixed = scene == 11;

        if (scene != 2 && !rain && !snow && !mixed) {
            return;
        }

        var width = dc.getWidth();

        // Cloud bank; preserve the existing sky behind it.
        dc.setClip(0, 0, width, 35);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);

        var drift = wrapWeather(_cloudDistance * 0.6, 40.0);

        for (var cloud = -1; cloud < 7; cloud++) {
            var x = (cloud * 40 + drift).toNumber();
            var y = 26 + ((cloud + 2) % 2) * 3;

            dc.fillCircle(x, y, 12);
            dc.fillCircle(x + 13, y - 6, 14);
            dc.fillCircle(x + 27, y, 11);
            dc.fillRectangle(x, y, 28, 12);
        }

        dc.clearClip();

        if (!rain && !snow && !mixed) {
            return;
        }

        var count = 18;

        if (scene == 9 || scene == 8) {
            count = 38;
        } else if (scene == 10) {
            count = 42;
        }

        var fallSpeed = rain ? 23.0 : 9.0;

        if (scene == 9) {
            fallSpeed = 34.0;
        } else if (scene == 10) {
            fallSpeed = 14.0;
        }

        var streakLength =
            (scene == 9 || scene == 8) ? 9 : 4;

        var slant = (_cloudVelocity * 0.2).toNumber();

        if (slant < -5) {
            slant = -5;
        } else if (slant > 5) {
            slant = 5;
        }

        dc.setClip(0, 35, width, 27);

        dc.setColor(
            rain ? 0x00FFFF : 0xFFFFFF,
            Graphics.COLOR_TRANSPARENT
        );

        for (var drop = 0; drop < count; drop++) {
            // Mixed weather alternates rain and snow.
            var drawRain = rain || (mixed && drop % 2 == 0);

            var particleSpeed = fallSpeed;

            if (mixed) {
                // Rain falls faster than the snow beside it.
                particleSpeed = drawRain ? 23.0 : 9.0;
            }

            var px = wrapWeather(
                drop * 37 + 11 + _cloudDistance * 0.3,
                width
            ).toNumber();

            var py = 35 + wrapWeather(
                drop * 11 + _weatherSeconds * particleSpeed,
                27.0
            ).toNumber();

            if (drawRain) {
                dc.setColor(
                    0x00FFFF,
                    Graphics.COLOR_TRANSPARENT
                );

                dc.drawLine(
                    px,
                    py,
                    px + slant,
                    py + streakLength
                );

            } else {
                dc.setColor(
                    0xFFFFFF,
                    Graphics.COLOR_TRANSPARENT
                );

                dc.fillRectangle(px, py, 2, 2);

                if (drop % 3 == 0) {
                    dc.drawLine(px - 1, py, px + 2, py);
                    dc.drawLine(px, py - 1, px, py + 2);
                }
            }
        }

        dc.clearClip();
    }

    function drawSunReflection(dc as Dc, reflectionX as Number) as Void {
        var reflections = [
            [64,  -4,   4],
            [69,  -6,   5],
            [75,  -5,   8],
            [82,  -9,   6],
            [90,  -7,  11],
            [100, -12,  9],
            [111, -9,  14],
            [124, -15, 11],
            [139, -12, 17],
            [155, -18, 13]
        ];

        for (var i = 0; i < reflections.size(); i++) {
            var y = reflections[i][0];
            var left = reflectionX + reflections[i][1];
            var right = reflectionX + reflections[i][2];

            // Orange requests map to the available device palette.
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(left - 6, y, right + 6, y);

            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(left, y, right, y);
        }
    }

    function drawMoonReflection(dc as Dc, reflectionX, moonPhase) as Void {
        var moonLight = (
            1.0 - Math.cos(2.0 * Math.PI * moonPhase)
        ) / 2.0;

        var ripples = [
            [65, 3],
            [71, 4],
            [79, 5],
            [89, 6],
            [101, 8],
            [115, 9],
            [131, 11],
            [149, 13]
        ];

        var count = Math.floor(moonLight * ripples.size()).toNumber();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        for (var i = 0; i < count; i++) {
            var y = ripples[i][0];
            var halfWidth = Math.ceil(
                ripples[i][1] * moonLight
            ).toNumber();

            dc.drawLine(
                reflectionX - halfWidth,
                y,
                reflectionX + halfWidth,
                y
            );
        }
    }

    function drawNightSky(dc as Dc,moonX as Number,moonY as Number,moonPhase) as Void {

        var centerX = dc.getWidth() / 2;
        var radius = 11;

        var stars = [
            [-8, 12], [17, 19], [-29, 23],
            [38, 23], [-49, 31], [4, 32],
            [-68, 43], [-35, 43], [23, 43],
            [74, 45], [-80, 56], [-57, 55],
            [-16, 56], [9, 55], [34, 58],
            [65, 59], [-5, 41], [-24, 35]
        ];

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        for (var i = 0; i < stars.size(); i++) {
            var starX = centerX + stars[i][0];
            var starY = stars[i][1];
            var dx = starX - moonX;
            var dy = starY - moonY;

            // Don't show stars through the Moon's dark portion.
            if (dx * dx + dy * dy > 14 * 14) {
                dc.drawPoint(starX, starY);

                if (i == 1 || i == 4) {
                    dc.drawLine(starX - 2, starY, starX + 2, starY);
                    dc.drawLine(starX, starY - 2, starX, starY + 2);
                }
            }
        }

        var terminator = Math.cos(2.0 * Math.PI * moonPhase);

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);

        for (var row = -radius; row <= radius; row++) {
            var edge = Math.sqrt(radius * radius - row * row);
            var left = -edge;
            var right = edge;

            if (moonPhase < 0.5) {
                left = terminator * edge;
            } else {
                right = -terminator * edge;
            }

            if (right - left >= 0.8) {
                var startX = Math.ceil(moonX + left).toNumber();
                var endX = Math.floor(moonX + right).toNumber();

                if (startX <= endX) {
                    dc.drawLine(
                        startX,
                        moonY + row,
                        endX,
                        moonY + row
                    );
                }
            }
        }
    }

    function wrapDegrees(angle) {
        return angle - 360.0 * Math.floor(angle / 360.0);
    }

    function calculateMoonPhase() {
        // Approximate orbital calculation.
        var elapsed = (Time.now().value() - 946728000).toDouble();
        var t = elapsed / 86400.0 / 36525.0;
        var t2 = t * t;
        var t3 = t2 * t;

        var elongation = wrapDegrees(
            297.8501921
            + 445267.1114034 * t
            - 0.0018819 * t2
            + t3 / 545868.0
        );

        var sunAnomaly = wrapDegrees(
            357.5291092
            + 35999.0502909 * t
            - 0.0001536 * t2
            + t3 / 24490000.0
        );

        var moonAnomaly = wrapDegrees(
            134.9633964
            + 477198.8675055 * t
            + 0.0087414 * t2
            + t3 / 69699.9
        );

        var radians = Math.PI / 180.0;
        var d = elongation * radians;
        var m = sunAnomaly * radians;
        var mp = moonAnomaly * radians;

        var correctedAngle = elongation
            + 6.289 * Math.sin(mp)
            - 2.100 * Math.sin(m)
            + 1.274 * Math.sin(2.0 * d - mp)
            + 0.658 * Math.sin(2.0 * d)
            + 0.214 * Math.sin(2.0 * mp)
            + 0.110 * Math.sin(d);

        return wrapDegrees(correctedAngle) / 360.0;
    }

    function drawOcean(dc as Dc, phase as Number) as Void {
        if (oceanBitmap == null || oceanPhase != phase) {
            oceanBitmap = null;

            if (phase == 2) {
                oceanBitmap = WatchUi.loadResource(
                    Rez.Drawables.DayOcean
                ) as WatchUi.BitmapResource;

            } else if (phase == 1 || phase == 3) {
                oceanBitmap = WatchUi.loadResource(
                    Rez.Drawables.SunsetOcean
                ) as WatchUi.BitmapResource;

            } else {
                oceanBitmap = WatchUi.loadResource(
                    Rez.Drawables.NightOcean
                ) as WatchUi.BitmapResource;
            }

            oceanPhase = phase;
        }

        if (oceanBitmap != null) {
            dc.drawBitmap(0, 62, oceanBitmap);
        }
    }

    function drawHorizonIslands(dc as Dc, phase as Number, season as Number) as Void {
        var sandColor = Graphics.COLOR_BLACK;
        var buildingColor = Graphics.COLOR_BLACK;
        var windowColor = Graphics.COLOR_WHITE;

        if (phase == 2) {
            if (season == 0) {
                sandColor = Graphics.COLOR_GREEN;
            } else if (season == 3) {
                sandColor = Graphics.COLOR_WHITE;
            } else {
                sandColor = Graphics.COLOR_YELLOW;
            }
            buildingColor = Graphics.COLOR_WHITE;
            windowColor = Graphics.COLOR_BLACK;

        } else if (phase == 0) {
            sandColor = Graphics.COLOR_DK_BLUE;
            buildingColor = Graphics.COLOR_DK_BLUE;
            windowColor = Graphics.COLOR_YELLOW;
        }

        dc.setColor(sandColor, Graphics.COLOR_TRANSPARENT);

        dc.fillPolygon([
            [9, 66],
            [18, 63],
            [34, 61],
            [53, 62],
            [68, 65],
            [74, 67],
            [9, 67]
        ]);

        dc.fillPolygon([
            [136, 67],
            [144, 64],
            [159, 62],
            [178, 61],
            [191, 63],
            [199, 66],
            [199, 67]
        ]);

        var buildings = [
            [24, 54, 8, 9],
            [36, 49, 9, 13],
            [50, 55, 7, 9],
            [148, 55, 8, 9],
            [162, 50, 9, 13],
            [178, 54, 8, 9]
        ];

        for (var i = 0; i < buildings.size(); i++) {
            var x = buildings[i][0];
            var y = buildings[i][1];
            var width = buildings[i][2];
            var height = buildings[i][3];

            dc.setColor(buildingColor, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, y, width, height);

            dc.setColor(windowColor, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + 2, y + 3, 1, 2);
            dc.fillRectangle(x + width - 3, y + 3, 1, 2);

            if (height >= 12) {
                dc.fillRectangle(x + 2, y + 7, 1, 2);
                dc.fillRectangle(x + width - 3, y + 7, 1, 2);
            }
        }
    }

    function getSeason(month) as Number {
    // Northern Hemisphere meteorological seasons:
    // 0 spring, 1 summer, 2 fall, 3 winter
        if (month >= 3 && month <= 5) {
            return 0;
        }

        if (month >= 6 && month <= 8) {
            return 1;
        }

        if (month >= 9 && month <= 11) {
            return 2;
        }

        return 3;
    }

    function getHoliday(year, month, day) as Number {
    // Holiday decorations take priority over ordinary seasonal details.
    // 0 none, 1 Christmas, 2 Halloween, 3 Easter, 4 New Year
        if (month == 12 && day == 25) {
            return 1; // Christmas
        }

        if (month == 10 && day == 31) {
            return 2; // Halloween
        }

        var easter = getEasterDate(year);

        if (month == easter[0] && day == easter[1]) {
            return 3; // Easter
        }

        if (month == 1 && day == 1) {
            return 4; // New Year's Day
        }

        if (month == 2 && day == 14) {
            return 5; // Valentine's Day
        }

        if (month == 3 && day == 17) {
            return 6; // St. Patrick's Day
        }

        if (month == 7 && day == 4) {
            return 7; // Independence Day
        }

        // U.S. Thanksgiving: fourth Thursday in November.
        if (month == 11) {
            // Day of week for November 1: Sunday = 0.
            var novemberFirst = (
                year
                + Math.floor(year / 4.0).toNumber()
                - Math.floor(year / 100.0).toNumber()
                + Math.floor(year / 400.0).toNumber()
                + 3
            ) % 7;

            var thanksgivingDay =
                1 + ((4 - novemberFirst + 7) % 7) + 21;

            if (day == thanksgivingDay) {
                return 8;
            }
        }

        return 0;
    }

    function drawSeasonDecoration(dc as Dc,centerX as Number,phase as Number,season as Number) as Void {

        // Small trees on the inner edges of the existing islands.
        var treePositions = [centerX - 40, centerX + 39];

        for (var tree = 0; tree < treePositions.size(); tree++) {
            var x = treePositions[tree];

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x, 57, x, 64);

            if (season == 3) {
                // Bare winter branches
                dc.drawLine(x, 60, x - 3, 57);
                dc.drawLine(x, 59, x + 3, 56);

                // Snow at the base
                dc.drawLine(x - 4, 64, x + 4, 64);

            } else {
                var leafColor = Graphics.COLOR_GREEN;

                if (season == 2) {
                    leafColor = Graphics.COLOR_YELLOW;
                } else if (phase == 0) {
                    leafColor = Graphics.COLOR_DK_BLUE;
                }

                dc.setColor(leafColor, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, 54, 4);
                dc.fillCircle(x - 3, 57, 3);
                dc.fillCircle(x + 3, 57, 3);

                if (season == 0 && phase != 0) {
                    // Spring blossoms
                    dc.setColor(Graphics.COLOR_PINK, Graphics.COLOR_TRANSPARENT);
                    dc.drawPoint(x - 2, 54);
                    dc.drawPoint(x + 2, 56);

                } else if (season == 2 && phase != 0) {
                    // Red fall leaves
                    dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                    dc.drawPoint(x - 2, 55);
                    dc.drawPoint(x + 2, 57);
                }
            }
        }
    }

    function drawHolidayDecoration(dc as Dc,centerX as Number,holiday as Number,sceneId as Number) as Void {

        var x = centerX - 40;
        var baseY = 64;

        // Place decorations on a suitable surface in each scene.
        if (sceneId == 0) {
            // Sunday: top of the left meadow hill
            x = centerX - 42;
            baseY = 57;

        } else if (sceneId == 1) {
            // Monday: clearing between the forest trees
            x = centerX;
            baseY = 70;

        } else if (sceneId == 2) {
            // Tuesday: shoreline beside the cabin
            x = centerX - 40;
            baseY = 68;

        } else if (sceneId == 3) {
            // Wednesday: rooftop of the central building
            x = centerX + 4;
            baseY = 45;

        } else if (sceneId == 4) {
            // Thursday: between the desert cacti
            x = centerX + 8;
            baseY = 71;

        } else if (sceneId == 5) {
            // Friday: mountain foothills
            x = centerX;
            baseY = 82;

        } else {
            // Saturday: inner edge of the left island
            x = centerX - 40;
            baseY = 64;
        }

            if (holiday == 1) {
                // CHRISTMAS: larger tree with presents.
                var treeTop = baseY - 33;

                // Trunk.
                dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x - 2, baseY - 7, 4, 7);

                // Three overlapping tiers of branches.
                dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);

                dc.fillPolygon([
                    [x, treeTop],
                    [x - 7, treeTop + 12],
                    [x + 7, treeTop + 12]
                ]);

                dc.fillPolygon([
                    [x, treeTop + 6],
                    [x - 10, treeTop + 21],
                    [x + 10, treeTop + 21]
                ]);

                dc.fillPolygon([
                    [x, treeTop + 14],
                    [x - 13, baseY - 5],
                    [x + 13, baseY - 5]
                ]);

                // Golden star.
                dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);

                dc.fillPolygon([
                    [x, treeTop - 6],
                    [x + 1, treeTop - 3],
                    [x + 4, treeTop - 3],
                    [x + 2, treeTop - 1],
                    [x + 3, treeTop + 2],
                    [x, treeTop],
                    [x - 3, treeTop + 2],
                    [x - 2, treeTop - 1],
                    [x - 4, treeTop - 3],
                    [x - 1, treeTop - 3]
                ]);

                // Golden garland.
                dc.drawLine(
                    x - 3, treeTop + 9,
                    x + 4, treeTop + 11
                );

                dc.drawLine(
                    x - 6, treeTop + 17,
                    x + 7, treeTop + 20
                );

                dc.drawLine(
                    x - 9, treeTop + 24,
                    x + 10, treeTop + 27
                );

                // Red ornaments.
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x + 2, treeTop + 7, 1);
                dc.fillCircle(x - 4, treeTop + 14, 1);
                dc.fillCircle(x + 5, treeTop + 23, 1);
                dc.fillCircle(x - 7, treeTop + 25, 1);

                // White twinkling lights.
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.drawPoint(x - 1, treeTop + 5);
                dc.drawPoint(x + 4, treeTop + 15);
                dc.drawPoint(x - 2, treeTop + 21);
                dc.drawPoint(x + 8, treeTop + 26);

                // Left present: red with a white ribbon.
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x - 15, baseY - 6, 8, 7);

                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x - 12, baseY - 6, x - 12, baseY);
                dc.drawLine(x - 15, baseY - 4, x - 8, baseY - 4);

                // Bow.
                dc.drawLine(x - 12, baseY - 6, x - 14, baseY - 8);
                dc.drawLine(x - 12, baseY - 6, x - 10, baseY - 8);

                // Right present: cyan with a yellow ribbon.
                dc.setColor(0x00FFFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x + 5, baseY - 8, 8, 9);

                dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x + 9, baseY - 8, x + 9, baseY);
                dc.drawLine(x + 5, baseY - 5, x + 12, baseY - 5);

                // Bow.
                dc.drawLine(x + 9, baseY - 8, x + 7, baseY - 10);
                dc.drawLine(x + 9, baseY - 8, x + 11, baseY - 10);

                // Small front present: pink with a white ribbon.
                dc.setColor(0xFF00FF, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x - 4, baseY - 4, 7, 5);

                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x - 1, baseY - 4, x - 1, baseY);
                dc.drawLine(x - 4, baseY - 2, x + 2, baseY - 2);

                // Extra presents distributed across each landscape.
                var giftSpots = [];

                if (sceneId == 0) {
                    // Meadow hilltops.
                    giftSpots = [
                        [24, 65], [88, 65], [127, 66],
                        [145, 60], [179, 64]
                    ];

                } else if (sceneId == 1) {
                    // Forest floor.
                    giftSpots = [
                        [29, 73], [54, 74], [78, 72],
                        [139, 74], [162, 73], [182, 74]
                    ];

                } else if (sceneId == 2) {
                    // Lake shorelines.
                    giftSpots = [
                        [12, 65], [22, 64], [155, 71],
                        [173, 66], [190, 65]
                    ];

                } else if (sceneId == 3) {
                    // City rooftops.
                    giftSpots = [
                        [23, 56], [39, 47], [55, 39],
                        [73, 51], [143, 50],
                        [162, 41], [181, 54]
                    ];

                } else if (sceneId == 4) {
                    // Desert dunes.
                    giftSpots = [
                        [24, 66], [66, 65], [85, 70],
                        [145, 65], [179, 68], [195, 73]
                    ];

                } else if (sceneId == 5) {
                    // Mountain foothills.
                    giftSpots = [
                        [19, 77], [44, 75], [67, 78],
                        [145, 76], [164, 75], [190, 78]
                    ];

                } else {
                    // Ocean islands.
                    giftSpots = [
                        [18, 65], [31, 64], [44, 64],
                        [145, 66], [158, 65],
                        [175, 64], [190, 65]
                    ];
                }

                for (var gift = 0; gift < giftSpots.size(); gift++) {
                    drawHolidayPresent(
                        dc,
                        giftSpots[gift][0],
                        giftSpots[gift][1],
                        gift
                    );
                }

            } else if (holiday == 2 || holiday == 3) {
                // Each point marks where a decoration rests.
                var spots = [];

                if (sceneId == 0) {
                    // Meadow: follow the rolling hills.
                    spots = [
                        [24, 65], [43, 59], [64, 58],
                        [86, 65], [125, 67], [148, 60],
                        [175, 63], [191, 70]
                    ];

                } else if (sceneId == 1) {
                    // Forest: scattered along the forest floor.
                    spots = [
                        [28, 73], [52, 75], [73, 74],
                        [94, 71], [114, 72], [139, 74],
                        [163, 73], [181, 74]
                    ];

                } else if (sceneId == 2) {
                    // Lake: stay on the two shorelines.
                    spots = [
                        [12, 65], [24, 64], [57, 67],
                        [69, 73], [155, 71], [171, 66],
                        [188, 65], [199, 67]
                    ];

                } else if (sceneId == 3) {
                    // City: decorate individual rooftops.
                    spots = [
                        [23, 56], [39, 47], [55, 39],
                        [73, 51], [90, 33], [108, 45],
                        [125, 38], [143, 50],
                        [162, 41], [181, 54]
                    ];

                } else if (sceneId == 4) {
                    // Desert: follow the dune crests.
                    spots = [
                        [22, 67], [39, 63], [65, 65],
                        [86, 70], [123, 70], [145, 65],
                        [179, 68], [195, 73]
                    ];

                } else if (sceneId == 5) {
                    // Mountains: scattered across the foothills.
                    spots = [
                        [18, 77], [43, 75], [65, 78],
                        [90, 82], [118, 81], [145, 76],
                        [164, 75], [190, 78]
                    ];

                } else {
                    // Ocean: only place decorations on the islands.
                    spots = [
                        [18, 65], [31, 64], [44, 64],
                        [61, 66], [145, 66], [157, 65],
                        [174, 64], [190, 65]
                    ];
                }

                for (var item = 0; item < spots.size(); item++) {
                    var itemX = spots[item][0];
                    var itemY = spots[item][1];

                    if (holiday == 2) {
                        drawHolidayPumpkin(dc, itemX, itemY, item);
                    } else {
                        drawHolidayEgg(dc, itemX, itemY, item);
                    }
                }


            } else if (holiday == 4) {
                // New Year's: fireworks spread across the upper sky.
                var fireworks = [
                    [65, 27, 7, 0xFFFF00],
                    [104, 18, 6, 0x00FFFF],
                    [143, 28, 8, 0xFF00FF],
                    [34, 49, 6, 0xFFFFFF],
                    [79, 49, 8, 0xFF0000],
                    [125, 45, 7, 0x00FF00],
                    [173, 49, 6, 0xFFFF00]
                ];

                for (var i = 0; i < fireworks.size(); i++) {
                    var firework = fireworks[i];

                    drawHolidayFirework(
                        dc,
                        firework[0],
                        firework[1],
                        firework[2],
                        firework[3]
                    );
                }

            } else if (holiday == 5) {
                // Valentine's: a heart on the landscape.
                dc.setColor(0xFF00FF, Graphics.COLOR_TRANSPARENT);

                dc.fillCircle(x - 4, baseY - 10, 5);
                dc.fillCircle(x + 4, baseY - 10, 5);

                dc.fillPolygon([
                    [x - 9, baseY - 9],
                    [x + 9, baseY - 9],
                    [x, baseY]
                ]);

                // Two smaller floating hearts.
                drawHolidayHeart(dc, 66, 31);
                drawHolidayHeart(dc, 142, 39);

                } else if (holiday == 6) {
                    // St. Patrick's: four heart-shaped leaves.
                    var cloverY = baseY - 12;

                    dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);

                    // Upper-left leaf.
                    dc.fillCircle(x - 6, cloverY - 3, 3);
                    dc.fillCircle(x - 3, cloverY - 6, 3);
                    dc.fillPolygon([
                        [x - 8, cloverY - 2],
                        [x - 2, cloverY - 8],
                        [x - 1, cloverY - 1]
                    ]);

                    // Upper-right leaf.
                    dc.fillCircle(x + 6, cloverY - 3, 3);
                    dc.fillCircle(x + 3, cloverY - 6, 3);
                    dc.fillPolygon([
                        [x + 8, cloverY - 2],
                        [x + 2, cloverY - 8],
                        [x + 1, cloverY - 1]
                    ]);

                    // Lower-left leaf.
                    dc.fillCircle(x - 6, cloverY + 3, 3);
                    dc.fillCircle(x - 3, cloverY + 6, 3);
                    dc.fillPolygon([
                        [x - 8, cloverY + 2],
                        [x - 2, cloverY + 8],
                        [x - 1, cloverY + 1]
                    ]);

                    // Lower-right leaf.
                    dc.fillCircle(x + 6, cloverY + 3, 3);
                    dc.fillCircle(x + 3, cloverY + 6, 3);
                    dc.fillPolygon([
                        [x + 8, cloverY + 2],
                        [x + 2, cloverY + 8],
                        [x + 1, cloverY + 1]
                    ]);

                    // Join the leaves and curve the stem downward.
                    dc.fillCircle(x, cloverY, 2);
                    dc.drawLine(x, cloverY, x, cloverY + 8);
                    dc.drawLine(x, cloverY + 8, x + 2, cloverY + 11);
                    dc.drawLine(x + 2, cloverY + 11, x + 4, baseY);

            } else if (holiday == 7) {
                // July 4: small flag and patriotic fireworks.
                var flagX = x - 7;
                var flagY = baseY - 21;

                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(flagX, flagY, 19, 13);
                dc.drawLine(flagX - 1, flagY, flagX - 1, baseY);

                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);

                for (var stripe = 0; stripe < 7; stripe++) {
                    dc.drawLine(
                        flagX,
                        flagY + stripe * 2,
                        flagX + 18,
                        flagY + stripe * 2
                    );
                }

                dc.setColor(0x0000FF, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(flagX, flagY, 8, 7);

                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.drawPoint(flagX + 2, flagY + 2);
                dc.drawPoint(flagX + 5, flagY + 2);
                dc.drawPoint(flagX + 3, flagY + 4);

                drawHolidayFirework(dc, 64, 29, 7, 0xFF0000);
                drawHolidayFirework(dc, 104, 20, 6, 0xFFFFFF);
                drawHolidayFirework(dc, 147, 31, 7, 0x0000FF);

                } else if (holiday == 8) {
                    // Thanksgiving: cornucopia resting on the landscape.
                    var hornX = x - 3;
                    var hornY = baseY - 7;

                    // Curved, tapered golden horn.
                    dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);

                    dc.fillPolygon([
                        [hornX + 4,  hornY - 8],
                        [hornX - 3,  hornY - 7],
                        [hornX - 9,  hornY - 4],
                        [hornX - 13, hornY],
                        [hornX - 16, hornY - 1],
                        [hornX - 17, hornY - 5],
                        [hornX - 18, hornY - 3],
                        [hornX - 18, hornY + 1],
                        [hornX - 15, hornY + 4],
                        [hornX - 10, hornY + 5],
                        [hornX - 3,  hornY + 5],
                        [hornX + 4,  hornY + 3]
                    ]);

                    // Woven ridges along the horn.
                    dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);

                    dc.drawLine(
                        hornX - 10, hornY,
                        hornX - 8, hornY + 3
                    );

                    dc.drawLine(
                        hornX - 6, hornY - 3,
                        hornX - 3, hornY + 3
                    );

                    // Dark opening with a golden rim.
                    dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
                    dc.fillRoundedRectangle(
                        hornX, hornY - 9, 10, 15, 5
                    );

                    dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
                    dc.fillRoundedRectangle(
                        hornX + 2, hornY - 7, 6, 11, 3
                    );

                    // Green leaves spilling from the opening.
                    dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);

                    dc.fillPolygon([
                        [hornX + 5,  hornY],
                        [hornX + 8,  hornY - 9],
                        [hornX + 11, hornY - 7],
                        [hornX + 8,  hornY + 2]
                    ]);

                    dc.fillPolygon([
                        [hornX + 7,  hornY + 2],
                        [hornX + 16, hornY - 2],
                        [hornX + 17, hornY + 1],
                        [hornX + 9,  hornY + 4]
                    ]);

                    // Red apple.
                    dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(hornX + 9, hornY, 3);
                    dc.fillCircle(hornX + 12, hornY, 3);

                    // Apple stem.
                    dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
                    dc.drawLine(
                        hornX + 11, hornY - 3,
                        hornX + 12, hornY - 5
                    );

                    // Small bunch of purple grapes.
                    dc.setColor(0xFF00FF, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(hornX + 5, hornY + 3, 2);
                    dc.fillCircle(hornX + 9, hornY + 3, 2);
                    dc.fillCircle(hornX + 7, hornY + 6, 2);

                    // Golden pear at the edge of the harvest.
                    dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(hornX + 16, hornY + 4, 3);
                    dc.fillCircle(hornX + 16, hornY + 1, 2);

                    dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
                    dc.drawPoint(hornX + 16, hornY - 2);
                }

            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        }

    function getEasterDate(year) {
        var a = year % 19;
        var b = Math.floor(year / 100.0).toNumber();
        var c = year % 100;
        var d = Math.floor(b / 4.0).toNumber();
        var e = b % 4;
        var f = Math.floor((b + 8) / 25.0).toNumber();
        var g = Math.floor((b - f + 1) / 3.0).toNumber();

        var h = (19 * a + b - d - g + 15) % 30;
        var i = Math.floor(c / 4.0).toNumber();
        var k = c % 4;

        var l = (32 + 2 * e + 2 * i - h - k) % 7;

        var m = Math.floor(
            (a + 11 * h + 22 * l) / 451.0
        ).toNumber();

        var result = h + l - 7 * m + 114;
        var month = Math.floor(result / 31.0).toNumber();
        var day = result % 31 + 1;

        return [month, day];
    }

    function drawDailyScene(dc as Dc,sceneId as Number,phase as Number,season as Number,holiday as Number) as Void {
        var centerX = dc.getWidth() / 2;
        var landColor = getLandscapeColor(phase, season);

        if (sceneId == 0) {
            // SUNDAY: rolling hills and meadow.
            dc.setColor(landColor, Graphics.COLOR_TRANSPARENT);

            dc.fillPolygon([
                [0, 72], [20, 65], [41, 58],
                [62, 56], [83, 61], [108, 73],
                [130, 82], [0, 82]
            ]);

            dc.fillPolygon([
                [82, 82], [108, 70], [133, 60],
                [156, 57], [179, 62], [208, 73],
                [208, 86], [82, 86]
            ]);

            drawLandscapeTree(
                dc, 160, 61, 18, phase, season, false
            );

            if (phase != 0 && (season == 0 || season == 1)) {
                dc.setColor(
                    season == 0 ? 0xFF00FF : 0xFFFF00,
                    Graphics.COLOR_TRANSPARENT
                );

                dc.fillCircle(39, 67, 1);
                dc.fillCircle(54, 63, 1);
                dc.fillCircle(72, 68, 1);
                dc.fillCircle(140, 67, 1);
                dc.fillCircle(181, 71, 1);
            }

        } else if (sceneId == 1) {
            // MONDAY: forest.
            dc.setColor(landColor, Graphics.COLOR_TRANSPARENT);

            dc.fillPolygon([
                [0, 73], [30, 68], [67, 72],
                [103, 67], [143, 72], [177, 67],
                [208, 73], [208, 80], [0, 80]
            ]);

            var trees = [
                [20, 74, 25], [40, 72, 34],
                [62, 74, 27], [80, 72, 20],
                [128, 72, 21], [148, 74, 31],
                [171, 71, 36], [190, 74, 24]
            ];

            for (var t = 0; t < trees.size(); t++) {
                drawLandscapeTree(
                    dc,
                    trees[t][0],
                    trees[t][1],
                    trees[t][2],
                    phase,
                    season,
                    t % 2 == 0
                );
            }

        } else if (sceneId == 2) {
            // TUESDAY: lake and cabin.
            dc.setColor(landColor, Graphics.COLOR_TRANSPARENT);

            dc.fillPolygon([
                [0, 65], [23, 59], [49, 61],
                [68, 68], [78, 75], [0, 80]
            ]);

            dc.fillPolygon([
                [145, 74], [161, 65], [184, 61],
                [208, 65], [208, 81]
            ]);

            drawLandscapeHouse(
                dc, 29, 52, 24, 17, phase, season
            );

            drawLandscapeTree(
                dc, 16, 66, 23, phase, season, true
            );

            drawLandscapeTree(
                dc, 178, 65, 25, phase, season, true
            );

            drawLandscapeTree(
                dc, 196, 68, 18, phase, season, true
            );

            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(65, 73, 91, 73);
            dc.drawLine(74, 73, 74, 78);
            dc.drawLine(86, 73, 86, 78);

        } else if (sceneId == 3) {
            // WEDNESDAY: city skyline.
            var buildings = [
                [17, 13, 18], [33, 12, 27],
                [48, 16, 35], [68, 11, 23],
                [83, 14, 41], [101, 15, 29],
                [120, 11, 36], [135, 17, 24],
                [156, 13, 33], [173, 17, 20]
            ];

            for (var b = 0; b < buildings.size(); b++) {
                var bx = buildings[b][0];
                var bw = buildings[b][1];
                var bh = buildings[b][2];
                var by = 74 - bh;

                dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(bx, by, bw, bh);

                dc.setColor(
                    phase == 0 ? 0x0000FF : 0xFFFFFF,
                    Graphics.COLOR_TRANSPARENT
                );

                dc.drawRectangle(bx, by, bw, bh);

                dc.setColor(
                    phase == 0 || phase == 3
                        ? 0xFFFF00
                        : 0x00FFFF,
                    Graphics.COLOR_TRANSPARENT
                );

                for (var wy = by + 4; wy < 70; wy += 6) {
                    for (var wx = bx + 3; wx < bx + bw - 2; wx += 5) {
                        if ((wx + wy + b) % 3 != 0) {
                            dc.fillRectangle(wx, wy, 2, 2);
                        }
                    }
                }

                if (season == 3) {
                    dc.setColor(
                        0xFFFFFF,
                        Graphics.COLOR_TRANSPARENT
                    );

                    dc.drawLine(bx, by, bx + bw - 1, by);
                }
            }

            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(90, 33, 90, 25);

            drawLandscapeTree(
                dc, 12, 78, 13, phase, season, false
            );

            drawLandscapeTree(
                dc, 197, 78, 13, phase, season, false
            );

            } else if (sceneId == 4) {
                // THURSDAY: sand dunes and cacti.
                dc.setColor(
                    phase == 0 ? 0x0000FF : 0xFFFF00,
                    Graphics.COLOR_TRANSPARENT
                );

                // Left dune.
                dc.fillPolygon([
                    [0, 72],
                    [31, 62],
                    [59, 61],
                    [90, 69],
                    [122, 79],
                    [0, 82]
                ]);

                // Right dune.
                dc.fillPolygon([
                    [78, 81],
                    [112, 70],
                    [143, 63],
                    [172, 64],
                    [208, 73],
                    [208, 85]
                ]);

                // Rounded cacti.
                drawDesertCactus(dc, 48, 65, 27, phase, season, 0);
                drawDesertCactus(dc, 166, 67, 20, phase, season, 1);


        } else if (sceneId == 5) {
            // FRIDAY: mountains.
            drawLandscapePeak(
                dc, 5, 83, 53, 29, 105, phase, season
            );

            drawLandscapePeak(
                dc, 70, 85, 126, 19, 187, phase, season
            );

            drawLandscapePeak(
                dc, 145, 83, 181, 39, 218, phase, season
            );

            dc.setColor(landColor, Graphics.COLOR_TRANSPARENT);

            dc.fillPolygon([
                [0, 78], [34, 72], [70, 77],
                [106, 83], [144, 74], [177, 72],
                [208, 79], [208, 87], [0, 87]
            ]);

            drawLandscapeTree(
                dc, 27, 77, 16, phase, season, true
            );

            drawLandscapeTree(
                dc, 183, 76, 19, phase, season, true
            );

        } else {
            // SATURDAY: ocean islands.
            drawHorizonIslands(dc, phase, season);
        }

        if (holiday != 0) {
            drawHolidayDecoration(dc, centerX, holiday, sceneId);
        } else if (sceneId == 6) {
            drawSeasonDecoration(dc, centerX, phase, season);
        }
    }

    function drawHolidayFirework(dc as Dc,x as Number,y as Number,radius as Number,color as Number) as Void {
        var diagonal = Math.floor(radius * 0.7).toNumber();

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);

        dc.drawLine(x, y - 3, x, y - radius);
        dc.drawLine(x, y + 3, x, y + radius);

        dc.drawLine(x - 3, y, x - radius, y);
        dc.drawLine(x + 3, y, x + radius, y);

        dc.drawLine(
            x - 2, y - 2,
            x - diagonal, y - diagonal
        );

        dc.drawLine(
            x + 2, y - 2,
            x + diagonal, y - diagonal
        );

        dc.drawLine(
            x - 2, y + 2,
            x - diagonal, y + diagonal
        );

        dc.drawLine(
            x + 2, y + 2,
            x + diagonal, y + diagonal
        );

        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);

        dc.drawPoint(x, y);
        dc.drawPoint(x - radius - 2, y + 2);
        dc.drawPoint(x + radius + 2, y - 2);
        dc.drawPoint(x + 2, y - radius - 2);
    }

    function drawHolidayHeart(dc as Dc,x as Number,y as Number) as Void {
        dc.setColor(0xFF00FF, Graphics.COLOR_TRANSPARENT);

        dc.fillCircle(x - 2, y, 3);
        dc.fillCircle(x + 2, y, 3);

        dc.fillPolygon([
            [x - 5, y],
            [x + 5, y],
            [x, y + 6]
        ]);
    }

    function drawHolidayPumpkin(dc as Dc,x as Number,baseY as Number,variation as Number) as Void {
        var height = 7 + (variation % 3);
        var top = baseY - height;
        var middle = top + 4;

        // Lobed pumpkin silhouette.
        dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);

        dc.fillCircle(x - 2, middle, 3);
        dc.fillCircle(x + 2, middle, 3);
        dc.fillRectangle(x - 3, middle, 7, baseY - middle);

        // Fine red grooves.
        dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);

        dc.drawLine(x - 2, top + 2, x - 2, baseY - 1);
        dc.drawLine(x + 2, top + 2, x + 2, baseY - 1);

        // Green stem.
        dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);

        dc.drawLine(x, top + 1, x, top - 2);
        dc.drawPoint(x + 1, top - 2);

        // Every other pumpkin is a jack-o'-lantern.
        if (variation % 2 == 0) {
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);

            dc.drawPoint(x - 2, middle);
            dc.drawPoint(x + 2, middle);

            dc.drawLine(
                x - 1, baseY - 2,
                x + 1, baseY - 2
            );
        }
    }

    function drawHolidayEgg(dc as Dc,x as Number,baseY as Number,variation as Number) as Void {
        var colors = [
            0xFF00FF,
            0x00FFFF,
            0xFFFF00,
            0xFFFFFF
        ];

        var height = 8 + (variation % 2);
        var top = baseY - height;

        dc.setColor(
            colors[variation % colors.size()],
            Graphics.COLOR_TRANSPARENT
        );

        // Narrow top and rounded, wider bottom.
        dc.fillPolygon([
            [x - 1, top],
            [x + 1, top],
            [x + 2, top + 2],
            [x + 3, top + 5],
            [x + 3, baseY - 2],
            [x + 2, baseY - 1],
            [x + 1, baseY],
            [x - 1, baseY],
            [x - 2, baseY - 1],
            [x - 3, baseY - 2],
            [x - 3, top + 5],
            [x - 2, top + 2]
        ]);

        // Alternate between a stripe and dotted decoration.
        dc.setColor(0x0000FF, Graphics.COLOR_TRANSPARENT);

        if (variation % 2 == 0) {
            dc.drawLine(x - 2, top + 4, x + 2, top + 4);
        } else {
            dc.drawPoint(x - 1, top + 3);
            dc.drawPoint(x + 1, top + 5);
            dc.drawPoint(x - 1, top + 7);
        }
    }

    function drawHolidayPresent(dc as Dc,x as Number,baseY as Number,variation as Number) as Void {
        var colors = [
            0xFF0000,
            0x00FFFF,
            0xFF00FF,
            0x0000FF
        ];

        // Alternate between wide boxes and taller boxes.
        var width = 9;
        var height = 6;

        if (variation % 2 != 0) {
            width = 7;
            height = 9;
        }

        var left = x - Math.floor(width / 2.0).toNumber();
        var top = baseY - height;

        dc.setColor(
            colors[variation % colors.size()],
            Graphics.COLOR_TRANSPARENT
        );

        dc.fillRectangle(left, top, width, height);

        // Alternate white and gold ribbons.
        dc.setColor(
            variation % 2 == 0 ? 0xFFFFFF : 0xFFFF00,
            Graphics.COLOR_TRANSPARENT
        );

        dc.drawLine(x, top, x, baseY - 1);
        dc.drawLine(left, top + 2, left + width - 1, top + 2);

        // Small bow resting on the lid.
        dc.drawLine(x, top, x - 2, top - 2);
        dc.drawLine(x - 2, top - 2, x - 3, top - 1);

        dc.drawLine(x, top, x + 2, top - 2);
        dc.drawLine(x + 2, top - 2, x + 3, top - 1);
    }

    function drawDesertCactus(dc as Dc,x as Number,baseY as Number,height as Number,phase as Number,season as Number,variation as Number) as Void {
        var top = baseY - height;

        var cactusColor = 0x00FF00;
        var spineColor = 0x000000;

        if (phase == 0) {
            cactusColor = 0x0000FF;
            spineColor = 0x00FFFF;
        }

        dc.setColor(cactusColor, Graphics.COLOR_TRANSPARENT);

        // Rounded central column.
        dc.fillRoundedRectangle(x - 3, top, 7, height, 3);

        // Different arm heights give each cactus its own silhouette.
        var leftTop = top + 7;
        var rightTop = top + 12;
        var leftJoin = baseY - 9;
        var rightJoin = baseY - 6;

        if (variation == 1) {
            leftTop = top + 10;
            rightTop = top + 4;
            leftJoin = baseY - 5;
            rightJoin = baseY - 8;
        }

        // Left arm: upright tip and rounded elbow.
        dc.fillRoundedRectangle(
            x - 11,
            leftTop,
            5,
            leftJoin - leftTop + 4,
            2
        );

        dc.fillRoundedRectangle(
            x - 10,
            leftJoin,
            9,
            4,
            2
        );

        // Right arm.
        dc.fillRoundedRectangle(
            x + 8,
            rightTop,
            5,
            rightJoin - rightTop + 4,
            2
        );

        dc.fillRoundedRectangle(
            x + 2,
            rightJoin,
            10,
            4,
            2
        );

            // Dense alternating spines along the central stem.
            dc.setColor(spineColor, Graphics.COLOR_TRANSPARENT);

            for (var spineY = top + 4;
                spineY < baseY - 2;
                spineY += 4) {

                // Short spines sticking out of each side.
                dc.drawLine(x - 4, spineY - 1, x - 3, spineY);
                dc.drawLine(x + 3, spineY + 1, x + 4, spineY);

                // Staggered dots on the cactus itself.
                dc.drawPoint(x - 1, spineY);
                dc.drawPoint(x + 1, spineY + 2);
            }

            // Spines along the left arm.
            for (var leftSpineY = leftTop + 3;
                leftSpineY < leftJoin;
                leftSpineY += 4) {

                dc.drawLine(
                    x - 12, leftSpineY - 1,
                    x - 11, leftSpineY
                );

                dc.drawPoint(x - 9, leftSpineY + 1);
            }

            // Spines along the right arm.
            for (var rightSpineY = rightTop + 3;
                rightSpineY < rightJoin;
                rightSpineY += 4) {

                dc.drawLine(
                    x + 12, rightSpineY,
                    x + 13, rightSpineY - 1
                );

                dc.drawPoint(x + 10, rightSpineY + 1);
            }

            // Small spikes at the growing tips.
            dc.drawLine(x, top - 2, x, top - 1);
            dc.drawPoint(x - 9, leftTop - 1);
            dc.drawPoint(x + 10, rightTop - 1);

        if (season == 0 && phase != 0) {
            // Spring blossom on one growing tip.
            var flowerX = x;
            var flowerY = top - 1;

            if (variation == 1) {
                flowerX = x + 10;
                flowerY = rightTop - 1;
            }

            dc.setColor(0xFF00FF, Graphics.COLOR_TRANSPARENT);

            dc.drawLine(
                flowerX - 2, flowerY,
                flowerX + 2, flowerY
            );

            dc.drawLine(
                flowerX, flowerY - 2,
                flowerX, flowerY + 1
            );

            dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            dc.drawPoint(flowerX, flowerY);

        } else if (season == 3) {
            // Small winter snow caps.
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);

            dc.drawLine(x - 1, top, x + 1, top);
            dc.drawLine(x - 10, leftTop, x - 8, leftTop);
            dc.drawLine(x + 9, rightTop, x + 11, rightTop);
        }
    }

    function wrapWeather(value, period) {
        var size = period.toFloat();
        return value - size * Math.floor(value / size);
    }

    function updateWeatherMotion(conditions,scene as Number) as Void {
        var tick = System.getTimer();
        var elapsed = 0.0;

        if (_weatherLastTick >= 0) {
            elapsed = (tick - _weatherLastTick) / 1000.0;

            if (elapsed < 0) {
                elapsed = 0.0;
            } else if (elapsed > 120) {
                elapsed = 120.0;
            }
        }

        _weatherLastTick = tick;
        _weatherSeconds += elapsed;

        // Accumulate movement so wind changes don't teleport clouds.
        _cloudDistance = wrapWeather(
            _cloudDistance + _cloudVelocity * elapsed,
            720.0
        );

                // Keep wind direction, but use a fixed cloud speed.
        if (conditions != null && conditions.windBearing != null) {
            var eastward = -Math.sin(
                conditions.windBearing * Math.PI / 180.0
            );

            if (eastward < -0.05) {
                _windDirection = -1;
            } else if (eastward > 0.05) {
                _windDirection = 1;
            }
        }

        // Higher = faster. About 25 seconds to cross the screen.
        _cloudVelocity = _windDirection * 12.0;

        if (_cloudVelocity < -0.01) {
            _windDirection = -1;
        } else if (_cloudVelocity > 0.01) {
            _windDirection = 1;
        }

        // Lightning only flashes while the watch face is awake.
        _flashActive = false;

        if (scene == 8 && _weatherAwake) {
            if (_weatherSeconds >= _nextFlash) {
                // One strike contains several flashes.
                _flashUntil = _weatherSeconds + 1.2;

                _nextFlash = _weatherSeconds + 7.0
                    + (Time.now().value() % 8);

                // Keep the same bolt position throughout the strike.
                _lightningX =
                    55 + (Time.now().value() % 95);
            }

            var strikeAge =
                _weatherSeconds - (_flashUntil - 1.2);

            _flashActive =
                (strikeAge >= 0.0 && strikeAge < 0.25) ||
                (strikeAge >= 0.4 && strikeAge < 0.65) ||
                (strikeAge >= 0.8 && strikeAge < 1.1);
        }
    }

    function drawWeatherForeground(dc as Dc,scene as Number) as Void {
        var width = dc.getWidth();

        // Fog and mist partially obscure the distant scenery.
        if (scene == 6 || scene == 7) {
            var bands =
                scene == 6 ? [40, 58, 76] : [53, 72];

            var spacing = scene == 6 ? 8 : 12;
            var rows = scene == 6 ? 6 : 4;

            var drift = wrapWeather(
                _cloudDistance,
                spacing
            ).toNumber();

            dc.setClip(0, 20, width, 66);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);

            for (var band = 0; band < bands.size(); band++) {
                for (var row = 0; row < rows; row++) {
                    for (
                        var fx = -spacing;
                        fx < width;
                        fx += spacing
                    ) {
                        var fogX =
                            fx + drift + (row % 2) * 3;

                        var fogY = bands[band] + row + (
                            Math.sin(
                                (fx + band * 19) / 30.0
                            ) * 2
                        ).toNumber();

                        if (scene == 6) {
                            dc.drawLine(
                                fogX, fogY,
                                fogX + 1, fogY
                            );
                        } else {
                            dc.drawPoint(fogX, fogY);
                        }
                    }
                }
            }

            dc.clearClip();
        }

                // Start a gust shortly after waking; repeat every six seconds.
        var gust = wrapWeather(
            _weatherSeconds - _gustStart,
            6.0
        );

        if (
            scene == 5 &&
            _weatherAwake &&
            gust >= 0.5 &&
            gust < 4.5
        ) {
            var progress = (gust - 0.5) / 4.0;

            var windX = (
                -55 + (width + 110) * progress
            ).toNumber();

            if (_windDirection < 0) {
                windX = width - windX;
            }

            dc.setClip(0, 15, width, 47);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);

            drawWindStroke(dc, windX, 33, 25, -1);

            drawWindStroke(
                dc,
                windX - _windDirection * 16,
                43,
                33,
                1
            );

            dc.drawLine(
                windX - _windDirection * 9, 51,
                windX + _windDirection * 12, 51
            );

            dc.clearClip();
        }

        if (scene == 8) {
            // Keep the brief scene flashes when awake.
            if (_flashActive) {
                dc.setColor(
                    0xFFFFFF,
                    Graphics.COLOR_TRANSPARENT
                );

                for (
                    var lightY = 0;
                    lightY < dc.getHeight();
                    lightY += 2
                ) {
                    dc.drawLine(
                        0, lightY,
                        width - 1, lightY
                    );
                }
            }

            // Small storm bolts remain visible in either power mode.
            var clock = System.getClockTime();
            var minute = clock.hour * 60 + clock.min;

            var boltPositions = [
                54 + ((minute * 7) % 24),
                135 + ((minute * 11) % 20)
            ];

            dc.setColor(
                0xFFFF00,
                Graphics.COLOR_TRANSPARENT
            );

            dc.setPenWidth(1);

            for (
                var lightning = 0;
                lightning < boltPositions.size();
                lightning++
            ) {
                var boltX = boltPositions[lightning];

                // Begin inside the cloud's lower edge.
                dc.fillPolygon([
                    [boltX,      35],
                    [boltX + 4,  35],
                    [boltX - 1,  44],
                    [boltX + 4,  43],
                    [boltX - 5,  59],
                    [boltX - 2,  48],
                    [boltX - 6,  49]
                ]);
            }
        }
    }



    function drawWindStroke(dc as Dc,x as Number,y as Number,length as Number,bend as Number) as Void {
        var d = _windDirection;

        dc.drawLine(x, y, x + d * length, y);

        var curl = [
            [0, 0],
            [3, 1],
            [5, 4],
            [4, 7],
            [1, 8],
            [-2, 6]
        ];

        for (var n = 0; n < curl.size() - 1; n++) {
            dc.drawLine(
                x + d * (length + curl[n][0]),
                y + bend * curl[n][1],
                x + d * (length + curl[n + 1][0]),
                y + bend * curl[n + 1][1]
            );
        }
    }

    function weatherAnimationTick() as Void {
        if (_weatherAwake) {
            WatchUi.requestUpdate();
        }
    }

    function stopWeatherAnimation() as Void {
        _weatherAwake = false;
        _flashActive = false;
        _flashUntil = 0.0;

        if (_weatherTimer != null) {
            _weatherTimer.stop();
            _weatherTimer = null;
        }
    }

    function getLandscapeColor(phase as Number,season as Number) as Number {

        if (season == 3) {
            return Graphics.COLOR_WHITE;
        }

        if (phase == 0) {
            return Graphics.COLOR_DK_BLUE;
        }

        if (season == 2) {
            return Graphics.COLOR_YELLOW;
        }

        return Graphics.COLOR_GREEN;
    }

    function drawSceneBase(dc as Dc, sceneId as Number, phase as Number, season as Number) as Void {
        if (sceneId == 2 || sceneId == 6) {
            groundBitmap = null;
            groundKey = -1;
            drawOcean(dc, phase);
            return;
        }

        // Land scenes don't need to retain the previous water bitmap.
        oceanBitmap = null;
        oceanPhase = -1;

        var light = 2;
        if (phase == 2) {
            light = 0;
        } else if (phase == 1 || phase == 3) {
            light = 1;
        }

        var index = season * 3 + light;
        var key = sceneId * 12 + index;

        if (groundBitmap == null || groundKey != key) {
            groundBitmap = null;
            groundBitmap = WatchUi.loadResource(
                getGroundResource(sceneId, index)
            ) as WatchUi.BitmapResource;
            groundKey = key;
        }

        if (groundBitmap != null) {
            dc.drawBitmap(0, 62, groundBitmap);
        }
    }

    function getGroundResource(sceneId as Number, index as Number) {
        if (sceneId == 0) {
            var textures = [
                Rez.Drawables.GroundMeadowSpringDay,
                Rez.Drawables.GroundMeadowSpringTwilight,
                Rez.Drawables.GroundMeadowSpringNight,
                Rez.Drawables.GroundMeadowSummerDay,
                Rez.Drawables.GroundMeadowSummerTwilight,
                Rez.Drawables.GroundMeadowSummerNight,
                Rez.Drawables.GroundMeadowFallDay,
                Rez.Drawables.GroundMeadowFallTwilight,
                Rez.Drawables.GroundMeadowFallNight,
                Rez.Drawables.GroundMeadowWinterDay,
                Rez.Drawables.GroundMeadowWinterTwilight,
                Rez.Drawables.GroundMeadowWinterNight
            ];
            return textures[index];
        }
        else if (sceneId == 1) {
            var textures = [
                Rez.Drawables.GroundForestSpringDay,
                Rez.Drawables.GroundForestSpringTwilight,
                Rez.Drawables.GroundForestSpringNight,
                Rez.Drawables.GroundForestSummerDay,
                Rez.Drawables.GroundForestSummerTwilight,
                Rez.Drawables.GroundForestSummerNight,
                Rez.Drawables.GroundForestFallDay,
                Rez.Drawables.GroundForestFallTwilight,
                Rez.Drawables.GroundForestFallNight,
                Rez.Drawables.GroundForestWinterDay,
                Rez.Drawables.GroundForestWinterTwilight,
                Rez.Drawables.GroundForestWinterNight
            ];
            return textures[index];
        }
        else if (sceneId == 3) {
            var textures = [
                Rez.Drawables.GroundCitySpringDay,
                Rez.Drawables.GroundCitySpringTwilight,
                Rez.Drawables.GroundCitySpringNight,
                Rez.Drawables.GroundCitySummerDay,
                Rez.Drawables.GroundCitySummerTwilight,
                Rez.Drawables.GroundCitySummerNight,
                Rez.Drawables.GroundCityFallDay,
                Rez.Drawables.GroundCityFallTwilight,
                Rez.Drawables.GroundCityFallNight,
                Rez.Drawables.GroundCityWinterDay,
                Rez.Drawables.GroundCityWinterTwilight,
                Rez.Drawables.GroundCityWinterNight
            ];
            return textures[index];
        }
        else if (sceneId == 4) {
            var textures = [
                Rez.Drawables.GroundDesertSpringDay,
                Rez.Drawables.GroundDesertSpringTwilight,
                Rez.Drawables.GroundDesertSpringNight,
                Rez.Drawables.GroundDesertSummerDay,
                Rez.Drawables.GroundDesertSummerTwilight,
                Rez.Drawables.GroundDesertSummerNight,
                Rez.Drawables.GroundDesertFallDay,
                Rez.Drawables.GroundDesertFallTwilight,
                Rez.Drawables.GroundDesertFallNight,
                Rez.Drawables.GroundDesertWinterDay,
                Rez.Drawables.GroundDesertWinterTwilight,
                Rez.Drawables.GroundDesertWinterNight
            ];
            return textures[index];
        }
        else if (sceneId == 5) {
            var textures = [
                Rez.Drawables.GroundMountainsSpringDay,
                Rez.Drawables.GroundMountainsSpringTwilight,
                Rez.Drawables.GroundMountainsSpringNight,
                Rez.Drawables.GroundMountainsSummerDay,
                Rez.Drawables.GroundMountainsSummerTwilight,
                Rez.Drawables.GroundMountainsSummerNight,
                Rez.Drawables.GroundMountainsFallDay,
                Rez.Drawables.GroundMountainsFallTwilight,
                Rez.Drawables.GroundMountainsFallNight,
                Rez.Drawables.GroundMountainsWinterDay,
                Rez.Drawables.GroundMountainsWinterTwilight,
                Rez.Drawables.GroundMountainsWinterNight
            ];
            return textures[index];
        }
        return Rez.Drawables.GroundMeadowSummerDay;
    }

    function drawLandscapeTree(dc as Dc,x as Number,baseY as Number,height as Number,phase as Number,season as Number,pine as Boolean) as Void {

        var topY = baseY - height;
        var leafColor = getLandscapeColor(phase, season);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, topY + 5, x, baseY);

        if (pine) {
            // Evergreen silhouette
            leafColor = phase == 0
                ? Graphics.COLOR_DK_BLUE
                : Graphics.COLOR_GREEN;

            dc.setColor(leafColor, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([
                [x, topY],
                [x - 5, topY + height / 3],
                [x - 3, topY + height / 3],
                [x - 8, topY + height * 2 / 3],
                [x - 5, topY + height * 2 / 3],
                [x - 10, baseY - 3],
                [x + 10, baseY - 3],
                [x + 5, topY + height * 2 / 3],
                [x + 8, topY + height * 2 / 3],
                [x + 3, topY + height / 3],
                [x + 5, topY + height / 3]
            ]);

            if (season == 3) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x - 3, topY + 5, x + 3, topY + 5);
                dc.drawLine(
                    x - 6,
                    topY + height / 2,
                    x + 6,
                    topY + height / 2
                );
            }

        } else if (season == 3) {
            // Bare deciduous branches in winter
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x, topY + 8, x - 5, topY + 3);
            dc.drawLine(x, topY + 11, x + 6, topY + 5);
            dc.drawLine(x, topY + 15, x - 6, topY + 10);

        } else {
            // Rounded deciduous canopy
            var canopyRadius = (height / 4).toNumber();

            if (canopyRadius < 4) {
                canopyRadius = 4;
            }

            dc.setColor(leafColor, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, topY + canopyRadius, canopyRadius);
            dc.fillCircle(
                x - canopyRadius / 2,
                topY + canopyRadius + 3,
                canopyRadius
            );
            dc.fillCircle(
                x + canopyRadius / 2,
                topY + canopyRadius + 3,
                canopyRadius
            );

            if (phase != 0 && season == 0) {
                dc.setColor(Graphics.COLOR_PINK, Graphics.COLOR_TRANSPARENT);
                dc.drawPoint(x - 2, topY + canopyRadius);
                dc.drawPoint(x + 2, topY + canopyRadius + 3);

            } else if (phase != 0 && season == 2) {
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x - 2, topY + canopyRadius + 1, 2);
            }
        }
    }

    function drawLandscapeHouse(dc as Dc,x as Number,y as Number,width as Number,height as Number,phase as Number,season as Number) as Void {

        // Cabin walls
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, width, height);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, width, height);

        // Roof
        dc.setColor(
            season == 3
                ? Graphics.COLOR_WHITE
                : Graphics.COLOR_RED,
            Graphics.COLOR_TRANSPARENT
        );

        dc.fillPolygon([
            [x - 3, y],
            [x + width / 2, y - 9],
            [x + width + 3, y]
        ]);

        // Door
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x + width / 2 - 2, y + height - 8, 5, 8);

        // Windows glow at sunset and night.
        dc.setColor(
            phase == 0 || phase == 3
                ? Graphics.COLOR_YELLOW
                : 0x00FFFF,
            Graphics.COLOR_TRANSPARENT
        );

        dc.fillRectangle(x + 3, y + 4, 4, 4);
        dc.fillRectangle(x + width - 7, y + 4, 4, 4);
    }

    function drawLandscapePeak(dc as Dc,leftX as Number,baseY as Number,peakX as Number,peakY as Number,rightX as Number,phase as Number,season as Number) as Void {

        dc.setColor(Graphics.COLOR_DK_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [leftX, baseY],
            [peakX, peakY],
            [rightX, baseY]
        ]);

        // One darker mountain face
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [peakX, peakY],
            [peakX + 9, baseY],
            [rightX, baseY]
        ]);

        // Snow extends farther down the mountain in winter.
        var snowDepth = 9;

        if (season == 3) {
            snowDepth = 19;
        } else if (season == 0) {
            snowDepth = 13;
        }

        var fraction = snowDepth.toFloat() / (baseY - peakY);

        var snowLeft = (
            peakX + (leftX - peakX) * fraction
        ).toNumber();

        var snowRight = (
            peakX + (rightX - peakX) * fraction
        ).toNumber();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [peakX, peakY],
            [snowLeft, peakY + snowDepth],
            [peakX - 2, peakY + snowDepth - 3],
            [peakX + 3, peakY + snowDepth + 1],
            [snowRight, peakY + snowDepth]
        ]);
    }

    function onHide() as Void {
        stopWeatherAnimation();
    }

    function onExitSleep() as Void {
        _weatherAwake = true;
        _gustStart = _weatherSeconds;
        _weatherLastTick = System.getTimer();
        _nextFlash = _weatherSeconds + 1.5;

        if (_weatherTimer == null) {
            _weatherTimer = new Timer.Timer();
        }

        _weatherTimer.start(
            method(:weatherAnimationTick),
            200,
            true
        );

        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        stopWeatherAnimation();
        WatchUi.requestUpdate();
    }

}