(function () {
  const states = {};

  function rowsFromShiny(value) {
    if (!value) return [];
    if (Array.isArray(value)) return value;
    const keys = Object.keys(value);
    if (!keys.length) return [];
    const length = Array.isArray(value[keys[0]]) ? value[keys[0]].length : 0;
    return Array.from({ length }, (_, index) => {
      const row = {};
      keys.forEach((key) => {
        row[key] = value[key][index];
      });
      return row;
    });
  }

  async function rowsFromNdjson(url) {
    if (!url) return [];
    const response = await fetch(url, { cache: "no-store" });
    if (!response.ok) throw new Error(`Unable to load ${url}: HTTP ${response.status}`);
    const text = await response.text();
    return text.split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
  }

  function finite(value) {
    return Number.isFinite(Number(value));
  }

  function lowerBound(rows, timeMs, field) {
    let low = 0;
    let high = rows.length;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (Number(rows[mid][field]) < timeMs) low = mid + 1;
      else high = mid;
    }
    return low;
  }

  function buildAoiGroups(rows) {
    const groups = new Map();
    rows.forEach((row) => {
      if (!finite(row.time_ms) || !finite(row.x_min) || !finite(row.y_min) || !finite(row.x_max) || !finite(row.y_max)) return;
      const stableShape = row.shape_id && !/^row_\d+$/.test(row.shape_id) ? row.shape_id : "";
      const key = [row.aoi_group_id || row.aoi_name || "AOI", stableShape].join("|");
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(row);
    });
    groups.forEach((group) => group.sort((a, b) => Number(a.time_ms) - Number(b.time_ms)));
    return Array.from(groups.values());
  }

  function activeRows(state, timeMs) {
    const hits = [];
    state.aoiGroups.forEach((group) => {
      const index = lowerBound(group, timeMs, "time_ms");
      const candidates = [];
      if (index < group.length) candidates.push(group[index]);
      if (index > 0) candidates.push(group[index - 1]);
      const row = candidates.sort((a, b) => Math.abs(Number(a.time_ms) - timeMs) - Math.abs(Number(b.time_ms) - timeMs))[0];
      if (!row || (state.validOnly && row.valid_aoi !== true)) return;
      const inWindow = finite(row.start_ms) && finite(row.end_ms) &&
        Number(row.end_ms) > Number(row.start_ms) &&
        timeMs >= Number(row.start_ms) && timeMs < Number(row.end_ms);
      if (inWindow || Math.abs(Number(row.time_ms) - timeMs) <= state.nearestMs) hits.push(row);
    });
    return hits;
  }

  function resizeCanvas(video, canvas) {
    const rect = video.getBoundingClientRect();
    const ratio = window.devicePixelRatio || 1;
    const width = Math.max(1, Math.round(rect.width * ratio));
    const height = Math.max(1, Math.round(rect.height * ratio));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
      canvas.style.width = rect.width + "px";
      canvas.style.height = rect.height + "px";
    }
    return { width, height, ratio };
  }

  function draw(state) {
    const video = document.getElementById(state.videoId);
    const canvas = document.getElementById(state.canvasId);
    if (!video || !canvas) return;
    const size = resizeCanvas(video, canvas);
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, size.width, size.height);
    const timeMs = video.currentTime * 1000;
    const sx = size.width / state.screenWidth;
    const sy = size.height / state.screenHeight;
    const aoiScaleX = state.aoiScaleX / 100;
    const aoiScaleY = state.aoiScaleY / 100;
    const transformAoiX = (value) =>
      ((Number(value) - state.screenWidth / 2) * aoiScaleX + state.screenWidth / 2 + state.aoiOffsetX) * sx;
    const transformAoiY = (value) =>
      ((Number(value) - state.screenHeight / 2) * aoiScaleY + state.screenHeight / 2 + state.aoiOffsetY) * sy;

    activeRows(state, timeMs).forEach((row) => {
      const valid = row.valid_aoi === true;
      const scope = row.aoi_scope || row.aoi_group_id || "";
      const scopeColor = scope === "exp2_table_objects" ? "#3ba7ff" :
        scope === "exp2_target_object" ? "#ff7043" : "#39ff88";
      const x = transformAoiX(row.x_min);
      const y = transformAoiY(row.y_min);
      const width = transformAoiX(row.x_max) - x;
      const height = transformAoiY(row.y_max) - y;
      ctx.strokeStyle = valid ? scopeColor : "#ff4d5e";
      ctx.lineWidth = Math.max(2, 2 * size.ratio);
      ctx.strokeRect(x, y, width, height);
      const label = row.aoi_name || row.aoi_group_id || "AOI";
      ctx.font = `${Math.max(12, 12 * size.ratio)}px sans-serif`;
      const textWidth = ctx.measureText(label).width;
      ctx.fillStyle = valid ? `${scopeColor}d1` : "rgba(120, 0, 15, 0.82)";
      ctx.fillRect(x, Math.max(0, y - 20 * size.ratio), textWidth + 10 * size.ratio, 20 * size.ratio);
      ctx.fillStyle = "#ffffff";
      ctx.fillText(label, x + 5 * size.ratio, Math.max(14 * size.ratio, y - 5 * size.ratio));
    });

    const gazeStart = lowerBound(state.gaze, timeMs - state.gazeWindowMs, "video_time_ms");
    for (let gazeIndex = gazeStart; gazeIndex < state.gaze.length; gazeIndex += 1) {
      const row = state.gaze[gazeIndex];
      if (Number(row.video_time_ms) > timeMs + state.gazeWindowMs) break;
        if (!finite(row.gaze_x) || !finite(row.gaze_y)) continue;
        ctx.beginPath();
        ctx.arc(Number(row.gaze_x) * sx, Number(row.gaze_y) * sy, 4 * size.ratio, 0, Math.PI * 2);
        ctx.fillStyle = "rgba(255, 224, 64, 0.88)";
        ctx.fill();
    }

    const status = document.getElementById(state.statusId);
    if (status) status.textContent = `${timeMs.toFixed(0)} ms`;
    const seek = document.getElementById(state.seekId);
    if (seek && !state.userSeeking) seek.value = String(video.currentTime);
  }

  async function prepareSeekableVideo(state) {
    const video = document.getElementById(state.videoId);
    const seek = document.getElementById(state.seekId);
    if (!video || state.videoPreparing) return;
    if (state.videoSeekable && video.currentSrc === state.videoBlobUrl) return;
    if (state.videoSeekable && state.videoBlobUrl) {
      URL.revokeObjectURL(state.videoBlobUrl);
      state.videoBlobUrl = null;
      state.videoSeekable = false;
    }
    if (!video.currentSrc && !video.src) return;
    state.videoPreparing = true;
    if (seek) {
      seek.disabled = true;
      seek.title = "正在加载完整视频，完成后可自由拖动";
    }
    const sourceUrl = video.currentSrc || video.src;
    try {
      const response = await fetch(sourceUrl, { cache: "no-store" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const blob = await response.blob();
      const oldTime = finite(video.currentTime) ? video.currentTime : 0;
      state.videoBlobUrl = URL.createObjectURL(blob);
      video.src = state.videoBlobUrl;
      video.load();
      await new Promise((resolve) => video.addEventListener("loadedmetadata", resolve, { once: true }));
      video.currentTime = Math.min(oldTime, finite(video.duration) ? video.duration : oldTime);
      state.videoSeekable = true;
      if (seek) seek.title = "拖动到指定视频时间";
    } catch (error) {
      console.error("Unable to prepare seekable video", error);
    } finally {
      state.videoPreparing = false;
      if (seek) seek.disabled = false;
    }
  }

  function bindSeekControls(state) {
    const video = document.getElementById(state.videoId);
    const seek = document.getElementById(state.seekId);
    const back = document.getElementById(state.backId);
    const forward = document.getElementById(state.forwardId);
    if (!video || !seek || seek.dataset.bound === "true") return;
    seek.dataset.bound = "true";
    seek.disabled = true;
    const updateDuration = () => {
      if (finite(video.duration)) seek.max = String(video.duration);
    };
    video.addEventListener("loadedmetadata", updateDuration);
    video.addEventListener("durationchange", updateDuration);
    seek.addEventListener("pointerdown", () => { state.userSeeking = true; });
    seek.addEventListener("input", () => {
      state.userSeeking = true;
      if (finite(seek.value)) video.currentTime = Number(seek.value);
    });
    seek.addEventListener("change", () => {
      if (finite(seek.value)) video.currentTime = Number(seek.value);
      state.userSeeking = false;
    });
    seek.addEventListener("pointerup", () => { state.userSeeking = false; });
    if (back) back.addEventListener("click", () => { video.currentTime = Math.max(0, video.currentTime - 5); });
    if (forward) forward.addEventListener("click", () => { video.currentTime = Math.min(finite(video.duration) ? video.duration : Infinity, video.currentTime + 5); });
    updateDuration();
    prepareSeekableVideo(state);
  }

  function startLoop(state) {
    if (state.looping) return;
    state.looping = true;
    const tick = () => {
      bindSeekControls(state);
      draw(state);
      state.frame = window.requestAnimationFrame(tick);
    };
    tick();
  }

  Shiny.addCustomMessageHandler("dynamic-aoi-player-data", async function (message) {
    const state = states[message.id] || {};
    const requestId = (state.requestId || 0) + 1;
    state.requestId = requestId;
    states[message.id] = state;
    let aoi = rowsFromShiny(message.aoi);
    let gaze = rowsFromShiny(message.gaze);
    try {
      if (message.aoiUrl) aoi = await rowsFromNdjson(message.aoiUrl);
      if (message.gazeUrl) gaze = await rowsFromNdjson(message.gazeUrl);
    } catch (error) {
      console.error("Dynamic AOI player data load failed", error);
    }
    if (state.requestId !== requestId) return;
    Object.assign(state, {
      videoId: message.videoId,
      canvasId: message.canvasId,
      statusId: message.statusId,
      aoi,
      gaze,
      screenWidth: Number(message.screenWidth) || 1920,
      screenHeight: Number(message.screenHeight) || 1080,
      aoiOffsetX: Number(message.aoiOffsetX) || 0,
      aoiOffsetY: Number(message.aoiOffsetY) || 0,
      aoiScaleX: Number(message.aoiScaleX) || 100,
      aoiScaleY: Number(message.aoiScaleY) || 100,
      seekId: message.seekId,
      backId: message.backId,
      forwardId: message.forwardId,
      nearestMs: Number(message.nearestMs) || 120,
      gazeWindowMs: Number(message.gazeWindowMs) || 120,
      validOnly: message.validOnly === true
    });
    state.aoiGroups = buildAoiGroups(aoi);
    state.gaze.sort((a, b) => Number(a.video_time_ms) - Number(b.video_time_ms));
    states[message.id] = state;
    bindSeekControls(state);
    startLoop(state);
  });

  Shiny.addCustomMessageHandler("dynamic-aoi-player-seek", function (message) {
    const state = states[message.id];
    if (!state) return;
    const video = document.getElementById(state.videoId);
    if (video && finite(message.timeMs)) video.currentTime = Math.max(0, Number(message.timeMs) / 1000);
  });

  Shiny.addCustomMessageHandler("dynamic-aoi-player-notice", function (message) {
    const state = states[message.id];
    const status = state ? document.getElementById(state.statusId) : null;
    if (status && message.text) status.title = message.text;
  });
})();
