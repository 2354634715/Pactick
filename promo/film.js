/* Pactick 代码短片：时间单位为秒，所有图形和运动均由 Canvas 计算。 */
(() => {
  'use strict';
  const W = 1920, H = 1080;
  const C = { paper: '#F4F1E9', ink: '#171714', red: '#DA291C' };
  const chapters = [
    { start: 0, end: 8, title: '计划，变成行动', name: 'INTRODUCTION', bg: C.paper },
    { start: 8, end: 16, title: '记下任务', name: 'CAPTURE', bg: C.ink },
    { start: 16, end: 24, title: '安排时间', name: 'PLAN', bg: C.paper },
    { start: 24, end: 34, title: '开始专注', name: 'FOCUS', bg: C.red },
    { start: 34, end: 42, title: '回看用时', name: 'REFLECT', bg: C.paper },
    { start: 42, end: 50, title: '从本地开始', name: 'LOCAL FIRST', bg: C.ink },
    { start: 50, end: 56, title: '保留自己的记录', name: 'YOUR DATA', bg: C.paper },
    { start: 56, end: 60, title: 'Pactick', name: 'PACTICK', bg: C.red },
  ];
  let ctx;
  const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
  const ease = x => 1 - Math.pow(1 - clamp(x), 3);
  const smooth = x => { x = clamp(x); return x * x * (3 - 2 * x); };
  const enter = (t, delay = 0, duration = .7) => ease((t - delay) / duration);
  const mix = (a, b, p) => a + (b - a) * p;
  const sans = 'Arial, Helvetica, sans-serif';
  const zh = '"NotoSC", "Noto Sans SC", "Microsoft YaHei", sans-serif';
  const rect = (x, y, w, h, color) => { ctx.fillStyle = color; ctx.fillRect(x, y, w, h); };
  const line = (x, y, x2, y2, color, width = 2) => {
    ctx.strokeStyle = color; ctx.lineWidth = width; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x2, y2); ctx.stroke();
  };
  const circle = (x, y, r, color) => { ctx.fillStyle = color; ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill(); };
  function text(str, x, y, size, color = C.ink, weight = 400, family = zh, tracking = 0) {
    ctx.fillStyle = color; ctx.font = `${weight} ${size}px ${family}`; ctx.textBaseline = 'top';
    if (!tracking) { ctx.fillText(str, x, y); return; }
    for (const ch of str) { ctx.fillText(ch, x, y); x += ctx.measureText(ch).width + tracking; }
  }
  function outline(x, y, w, h, color, width = 2) {
    ctx.strokeStyle = color; ctx.lineWidth = width; ctx.strokeRect(x, y, w, h);
  }
  function reveal(p, x, y, w, h, draw) {
    if (p <= 0) return;
    ctx.save(); ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip();
    ctx.translate(0, (1 - p) * h); draw(); ctx.restore();
  }
  function appear(p, dx, dy, draw) {
    if (p <= 0) return;
    ctx.save(); ctx.globalAlpha *= p; ctx.translate((1 - p) * dx, (1 - p) * dy); draw(); ctx.restore();
  }
  function arrow(x, y, length, color, p = 1, width = 6) {
    line(x, y, x + length * p, y, color, width);
    if (p > .9) { line(x + length - 22, y - 22, x + length, y, color, width); line(x + length - 22, y + 22, x + length, y, color, width); }
  }
  function tick(x, y, size, color, p = 1, width = 8) {
    const points = [[x, y + size * .52], [x + size * .32, y + size * .82], [x + size, y]];
    const first = clamp(p * 2), second = clamp(p * 2 - 1);
    line(points[0][0], points[0][1], mix(points[0][0], points[1][0], first), mix(points[0][1], points[1][1], first), color, width);
    if (second > 0) line(points[1][0], points[1][1], mix(points[1][0], points[2][0], second), mix(points[1][1], points[2][1], second), color, width);
  }
  function heading(lines, t, x, y, size, color, delay = .15, gap = 1.24) {
    lines.forEach((s, i) => reveal(enter(t, delay + i * .13), x - 2, y + i * size * gap - 5, 1450, size * 1.24,
      () => text(s, x, y + i * size * gap, size, color, 700)));
  }
  function furniture(t, sceneIndex, sample = true) {
    const dark = chapters[sceneIndex].bg !== C.paper;
    const fg = dark ? C.paper : C.ink;
    const secondary = dark ? C.paper : C.ink;
    text('PACTICK', 96, 65, 27, fg, 700, sans, 1.5);
    text(`${String(sceneIndex).padStart(2, '0')} / ${chapters[sceneIndex].name}`, 672, 67, 23, fg, 400, sans, 2);
    text('ANDROID', 1536, 67, 23, fg, 400, sans, 1.5);
    line(96, 128, 1824, 128, fg, 2);
    line(96, 964, 1824, 964, fg, 2);
    text(sample ? '功能示意 / 演示数据' : '任务 · 日历 · 专注', 96, 995, 22, secondary);
    text('0.2.0-preview.1', 816, 997, 21, secondary, 400, sans);
    const index = String(sceneIndex + 1).padStart(2, '0');
    text(`${index} / 08`, 1680, 995, 22, secondary, 400, sans);
    const progress = clamp(t / 60);
    rect(0, 1072, W * progress, 8, dark ? C.paper : C.red);
  }
  function intro(t) {
    reveal(enter(t, .05, 1.0), 90, 207, 1310, 299, () => text('Pactick.', 90, 205, 270, C.ink, 700, sans, -11));
    appear(enter(t, .5), 0, 18, () => text('任务 / 日历 / 专注', 96, 519, 32));
    heading(['把计划，', '变成行动。'], t, 96, 627, 98, C.ink, 1.0, 1.23);
    const p = enter(t, .65, 1.15);
    ctx.save(); ctx.translate(1464, 601); ctx.scale(Math.max(.001, p), Math.max(.001, p));
    circle(0, 0, 216, C.red);
    tick(-91, -56, 190, C.paper, enter(t, 2.1, .65), 20);
    ctx.restore();
    appear(enter(t, 1.8), 0, 18, () => {
      text('PLAN.', 1248, 848, 24, C.ink, 700, sans, 2);
      text('START.', 1440, 848, 24, C.ink, 700, sans, 2);
      text('FOCUS.', 1632, 848, 24, C.ink, 700, sans, 2);
    });
    if (t > 4.0) {
      const q = smooth((t - 4) / 1.1);
      line(1248, 818, 1248 + 540 * q, 818, C.ink, 2);
      rect(1248 + 528 * q, 812, 12, 12, C.red);
    }
  }
  function tasks(t) {
    heading(['先记下，', '再开始。'], t, 96, 225, 104, C.paper);
    appear(enter(t, .8), 0, 24, () => {
      text('想做的事，收进任务。', 96, 550, 31, C.paper);
      text('项目、标签、优先级。', 96, 602, 31, C.paper);
    });
    const rows = ['读完下一章', '整理项目草稿', '留时间给练习'];
    text('INBOX', 816, 208, 24, C.paper, 400, sans, 3);
    rows.forEach((label, i) => {
      const p = enter(t, .55 + i * .34);
      appear(p, 110, 0, () => {
        const y = 273 + i * 170;
        line(816, y, 1824, y, C.paper, 2);
        text(String(i + 1).padStart(2, '0'), 816, y + 38, 50, C.red, 700, sans);
        text(label, 960, y + 41, 46, C.paper, 700);
        outline(1776, y + 48, 36, 36, C.paper, 2);
        if (i === 0 && t > 4.4) {
          tick(1781, y + 51, 27, C.red, enter(t, 4.4, .35), 5);
          const done = enter(t, 4.65, .5);
          line(960, y + 70, 960 + 230 * done, y + 70, C.red, 3);
        }
      });
    });
    line(816, 783, 1824, 783, C.paper, 2);
    appear(enter(t, 2.0), 0, 18, () => {
      rect(816, 832, 150, 48, C.red);
      text('个人项目', 833, 841, 23, C.paper);
      text('学习', 1008, 841, 23, C.paper);
      text('工作', 1152, 841, 23, C.paper);
      text('生活', 1296, 841, 23, C.paper);
    });
    text('01', 96, 738, 154, C.paper, 700, sans, -6);
    arrow(344, 842, 300, C.red, enter(t, 2.2));
  }
  function calendar(t) {
    heading(['给任务，', '留一段时间。'], t, 96, 222, 91, C.ink);
    appear(enter(t, .8), 0, 20, () => {
      text('把待办安排进日历。', 96, 523, 31);
      text('计划，从时间开始。', 96, 576, 31);
    });
    text('02', 96, 737, 154, C.ink, 700, sans, -6);
    const x = 960, y = 270, dayW = 288, hourH = 126;
    ['周一', '周二', '周三'].forEach((d, i) => text(d, x + i * dayW + 20, 204, 28));
    ['09:00', '10:00', '11:00', '12:00', '13:00'].forEach((hour, i) => {
      text(hour, 816, y + i * hourH - 12, 23, C.ink, 400, sans);
      line(x, y + i * hourH, 1824, y + i * hourH, C.ink, 1);
    });
    for (let i = 0; i < 4; i++) line(x + i * dayW, 186, x + i * dayW, 832, C.ink, 1);
    const cards = [
      [x, y + 23, dayW, 102, '读完下一章', '09:00 — 10:00', C.red, C.paper, .7],
      [x + dayW, y + hourH + 23, dayW, 228, '整理项目草稿', '10:00 — 12:00', C.ink, C.paper, 1.4],
      [x + dayW * 2, y + hourH * 3 + 23, dayW, 102, '练习', '12:00 — 13:00', C.red, C.paper, 2.1],
    ];
    cards.forEach(([cx, cy, cw, ch, title, hour, bg, fg, delay]) => {
      const p = enter(t, delay, .8);
      ctx.save(); ctx.beginPath(); ctx.rect(x, 186, 864, 648); ctx.clip();
      appear(p, 0, -68, () => {
        rect(cx + 8, cy, cw - 16, ch, bg);
        text(title, cx + 24, cy + 19, 26, fg, 700);
        text(hour, cx + 24, cy + ch - 32, 20, fg, 400, sans);
      }); ctx.restore();
    });
    appear(enter(t, 2.8), 0, 12, () => text('TASK → TIME', 960, 863, 24, C.red, 700, sans, 2));
  }
  function focus(t) {
    heading(['现在，', '只做这一件。'], t, 96, 225, 99, C.paper);
    appear(enter(t, .8), 0, 24, () => {
      text('选择任务，开始专注。', 96, 535, 31, C.paper);
      text('结束后，记录实际用时。', 96, 588, 31, C.paper);
    });
    text('03', 96, 737, 154, C.paper, 700, sans, -6);
    const cx = 1392, cy = 493, r = 246;
    const p = enter(t, .5, 1.0);
    for (let i = 0; i < 60; i++) {
      const a = -Math.PI / 2 + i / 60 * Math.PI * 2;
      if (i / 60 > p) continue;
      const long = i % 5 === 0;
      line(cx + Math.cos(a) * (r - (long ? 22 : 12)), cy + Math.sin(a) * (r - (long ? 22 : 12)),
        cx + Math.cos(a) * r, cy + Math.sin(a) * r, C.paper, long ? 5 : 2);
    }
    const elapsed = Math.max(0, Math.floor((t - 1.8) * 1.0));
    const time = t < 1.8 ? '25:00' : `24:${String(59 - elapsed).padStart(2, '0')}`;
    appear(p, 0, 18, () => {
      text('FOCUS', 1269, 369, 27, C.paper, 400, sans, 5);
      text(time, 1146, 423, 168, C.paper, 700, sans, -7);
      text('读完下一章', 1287, 638, 25, C.paper);
    });
    const a = -Math.PI / 2 + clamp((t - 1) / 11) * 1.5;
    if (p > .9) circle(cx + Math.cos(a) * r, cy + Math.sin(a) * r, 10, C.ink);
    appear(enter(t, 1.6), 0, 18, () => {
      line(960, 820, 1824, 820, C.paper, 2);
      rect(960, 857, 12, 12, C.paper);
      text('专注进行中', 998, 846, 29, C.paper);
      text('25 MIN', 1650, 850, 27, C.paper, 400, sans);
    });
  }
  function reflect(t) {
    heading(['看见投入，', '再调整计划。'], t, 96, 225, 95, C.ink);
    appear(enter(t, .85), 0, 24, () => {
      text('回看计划与实际用时。', 96, 535, 31);
      text('每一次专注，都有记录。', 96, 588, 31);
    });
    text('04', 96, 737, 154, C.ink, 700, sans, -6);
    rect(960, 213, 15, 15, C.ink); text('计划', 992, 198, 25);
    rect(1248, 213, 15, 15, C.red); text('实际', 1280, 198, 25);
    text('近 7 天 / 小时', 1536, 202, 22);
    const values = [[1.5, 1.2], [2.0, 1.8], [1.25, 1.4], [2.4, 2.0], [1.8, 1.9], [1.1, 1.3], [1.7, 1.5]];
    const base = 780, top = 330;
    [0, 1, 2, 3].forEach(n => {
      const y = base - n * 150;
      line(960, y, 1824, y, C.ink, n === 0 ? 2 : 1);
      text(`${n}h`, 883, y - 16, 21, C.ink, 400, sans);
    });
    values.forEach(([planned, actual], i) => {
      const x = 976 + i * 122;
      const p = enter(t, .9 + i * .13, .9);
      rect(x, base - planned * 150 * p, 31, planned * 150 * p, C.ink);
      rect(x + 42, base - actual * 150 * p, 31, actual * 150 * p, C.red);
      text(String(i + 1).padStart(2, '0'), x + 16, 808, 23, C.ink, 400, sans);
    });
    appear(enter(t, 2.4), 0, 18, () => {
      text('PLAN / ACTUAL', 960, 878, 24, C.ink, 700, sans, 2);
      arrow(1500, 891, 320, C.red);
    });
  }
  function local(t) {
    heading(['无需账号，', '从本地开始。'], t, 96, 225, 99, C.paper);
    appear(enter(t, .8), 0, 24, () => {
      text('本地任务、日历与专注，', 96, 544, 31, C.paper);
      text('在自己的设备上使用。', 96, 597, 31, C.paper);
    });
    text('05', 96, 737, 154, C.paper, 700, sans, -6);
    const p = enter(t, .55);
    appear(p, 0, 60, () => {
      outline(1104, 218, 432, 615, C.paper, 3);
      line(1104, 295, 1536, 295, C.paper, 2);
      text('LOCAL', 1135, 244, 24, C.paper, 700, sans, 2);
      circle(1503, 259, 6, C.red);
      rect(1136, 328, 368, 420, C.paper);
      text('Pactick.', 1167, 363, 52, C.ink, 700, sans, -2);
      ['任务', '日历', '专注'].forEach((label, i) => {
        const q = enter(t, 1.25 + i * .25);
        appear(q, 0, 16, () => {
          const y = 474 + i * 83;
          rect(1168, y + 10, 18, 18, C.red);
          text(label, 1220, y - 3, 31, C.ink, 700);
          line(1168, y + 55, 1472, y + 55, C.ink, 1);
        });
      });
      line(1278, 787, 1362, 787, C.paper, 4);
    });
    appear(enter(t, 2.1), 0, 20, () => {
      text('LOCAL', 1632, 350, 26, C.paper, 400, sans, 1.5);
      text('FIRST.', 1632, 393, 26, C.paper, 700, sans, 1.5);
      line(1632, 452, 1824, 452, C.red, 6);
      text('你的设备', 1632, 485, 25, C.paper);
      text('你的记录', 1632, 532, 25, C.paper);
    });
  }
  function data(t) {
    heading(['自己的记录，', '自己保留。'], t, 96, 218, 96, C.ink);
    appear(enter(t, .65), 0, 18, () => text('导出离线备份，按需恢复。', 96, 536, 30));
    const p = enter(t, .5);
    appear(p, 90, 0, () => {
      outline(1248, 212, 432, 420, C.ink, 3);
      rect(1248, 212, 432, 85, C.red);
      text('WORKSPACE', 1280, 239, 26, C.paper, 700, sans, 2);
      ['任务', '日历', '专注记录'].forEach((s, i) => {
        text(String(i + 1).padStart(2, '0'), 1280, 342 + i * 82, 25, C.red, 700, sans);
        text(s, 1376, 329 + i * 82, 31, C.ink);
      });
    });
    arrow(960, 427, 240, C.red, enter(t, 1.2));
    line(96, 688, 1824, 688, C.ink, 2);
    appear(enter(t, 1.7), 0, 28, () => {
      text('06', 96, 740, 130, C.ink, 700, sans, -5);
      text('同步，由你选择。', 528, 752, 53, C.ink, 700);
      text('可选自部署同步', 1248, 756, 31, C.ink, 700);
      text('自部署仍需真实环境验收', 1248, 826, 25, C.ink);
      text('SOURCE AVAILABLE', 528, 843, 23, C.red, 400, sans, 1.8);
    });
  }
  function outro(t) {
    reveal(enter(t, .06, .6), 88, 234, 1700, 329, () => text('Pactick.', 88, 230, 310, C.paper, 700, sans, -12));
    appear(enter(t, .35), 0, 24, () => {
      text('任务。日历。专注。', 96, 631, 76, C.paper, 700);
      line(96, 762, 1104, 762, C.paper, 3);
      text('ANDROID 预览版', 96, 812, 29, C.paper, 400, zh);
      text('Source Available', 672, 814, 29, C.paper, 400, sans);
    });
    appear(enter(t, .7), 0, 16, () => {
      text('https://github.com/2354634715/Pactick', 96, 884, 38, C.paper, 400, sans);
    });
    const p = enter(t, .3, .7);
    appear(p, 0, 35, () => {
      rect(1392, 640, 288, 240, C.paper);
      tick(1453, 714, 165, C.red, enter(t, .85, .45), 18);
    });
  }
  const draws = [intro, tasks, calendar, focus, reflect, local, data, outro];
  function renderAt(time, canvas = document.querySelector('canvas')) {
    const t = clamp(Number(time), 0, 59.999999);
    ctx = canvas.getContext('2d', { alpha: false });
    ctx.save(); ctx.setTransform(canvas.width / W, 0, 0, canvas.height / H, 0, 0);
    const i = chapters.findIndex(c => t < c.end);
    const chapter = chapters[i];
    rect(0, 0, W, H, chapter.bg);
    draws[i](t - chapter.start);
    furniture(t, i, i > 0 && i < 7);
    // 新章节开头用红色平涂擦除；渲染帧由绝对时间决定，不依赖播放状态。
    if (i > 0) {
      const local = t - chapter.start;
      if (local < .38) {
        const p = smooth(local / .38);
        rect(W * p, 0, W * (1 - p), H, i === 3 || i === 7 ? C.ink : C.red);
      }
    }
    ctx.restore();
    return { time: t, chapter: i, title: chapter.title };
  }
  window.PactickFilm = { width: W, height: H, duration: 60, chapters, palette: C, renderAt };
})();
