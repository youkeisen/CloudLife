/* MyDay 前端 */
'use strict';

var $ = function (id) { return document.getElementById(id); };

function esc(s) {
  return String(s === undefined || s === null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function toast(msg) {
  var t = $('toast');
  t.textContent = msg;
  t.classList.add('on');
  clearTimeout(window.__toastTimer);
  window.__toastTimer = setTimeout(function () { t.classList.remove('on'); }, 1800);
}

function api(path, options) {
  options = options || {};
  var opts = { method: options.method || 'GET', headers: {} };
  if (options.body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(options.body);
  }
  return fetch(path, opts).then(function (r) {
    return r.json().catch(function () { return { ok: false, error: '返回不是 JSON' }; });
  }).then(function (j) {
    if (!j.ok) {
      toast(j.error || '操作失败');
      throw new Error(j.error || 'request failed');
    }
    return j.data;
  });
}

function showDlg(title, html, buttons) {
  $('dlg').innerHTML = '<h4>' + title + '</h4>' + html + '<div class="btns"></div>';
  var bar = $('dlg').querySelector('.btns');
  (buttons || [{ text: '关闭', kind: '' }]).forEach(function (b) {
    var el = document.createElement('button');
    el.textContent = b.text;
    if (b.kind === 'primary') el.className = 'primary';
    if (b.kind === 'danger') el.className = 'danger';
    el.onclick = function () { b.onClick && b.onClick(); };
    bar.appendChild(el);
  });
  $('mask').classList.add('on');
}

function closeDlg() { $('mask').classList.remove('on'); }

$('mask').addEventListener('click', function (e) { if (e.target.id === 'mask') closeDlg(); });
document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeDlg(); });

var PAGES = {
  home: ['首页', '今天的课、天气和备忘'],
  courses: ['课程', '每周一套课表，整周可复制'],
  weather: ['天气', '你选的城市的实况与预报'],
  notes: ['备忘录', '随手记，也支持打勾清单'],
  settings: ['数据与设置', '备份、还原与全部自定义项']
};

function go(page) {
  document.querySelectorAll('.nav').forEach(function (n) {
    n.classList.toggle('on', n.dataset.p === page);
  });
  document.querySelectorAll('.page').forEach(function (p) {
    p.classList.toggle('on', p.id === 'p-' + page);
  });
  $('ttl').textContent = PAGES[page][0];
  $('sub').textContent = PAGES[page][1];
  if (page === 'home') renderHome();
  if (page === 'courses') renderCourses();
  if (page === 'notes') renderNotes();
  if (page === 'weather') renderWeather();
  if (page === 'settings') renderSettings();
}

document.querySelectorAll('.nav').forEach(function (n) {
  n.addEventListener('click', function () { go(n.dataset.p); });
});
document.querySelectorAll('[data-go]').forEach(function (el) {
  el.addEventListener('click', function () { go(el.dataset.go); });
});

/* ---------- 全局状态 ---------- */
var State = { settings: null, weekMeta: null, courses: [], notes: [], weather: null };

function debounce(fn, ms) {
  var t = null;
  return function () {
    var args = arguments, self = this;
    clearTimeout(t);
    t = setTimeout(function () { fn.apply(self, args); }, ms);
  };
}

function showWarnings(list) {
  var box = $('banners');
  box.innerHTML = '';
  (list || []).forEach(function (w) {
    var el = document.createElement('div');
    el.className = 'notice';
    el.textContent = w.message || ('数据文件有问题：' + (w.file || ''));
    box.appendChild(el);
  });
}

function applyTheme() {
  var t = (State.settings && State.settings.theme) || 'system';
  if (t === 'system') {
    var dark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    document.body.dataset.theme = dark ? 'dark' : 'light';
  } else {
    document.body.dataset.theme = t;
  }
}

function renderTopbar() {
  var meta = State.weekMeta || {};
  var map = { 1: '周一', 2: '周二', 3: '周三', 4: '周四', 5: '周五', 6: '周六', 7: '周日' };
  $('today').textContent = (meta.today || '') + ' ' + (map[meta.dow] || '');
  var pill = $('weekpill');
  if (meta.week) {
    pill.textContent = '第 ' + meta.week + ' 教学周';
    pill.className = 'pill';
  } else {
    pill.textContent = '教学周未设置';
    pill.className = 'pill gray';
  }
}

function loadBootstrap() {
  return api('/api/bootstrap').then(function (d) {
    State.settings = d.settings;
    State.weekMeta = d.weekMeta;
    $('ver').textContent = 'v' + d.version;
    $('dataPath').textContent = d.dataDir || '—';
    showWarnings(d.warnings);
    applyTheme();
    renderTopbar();
    return d;
  });
}

/* ---------- 设置页 ---------- */
var settingsBound = false;

function saveSettings(patch) {
  return api('/api/settings', { method: 'PUT', body: patch }).then(function (s) {
    State.settings = s;
    return s;
  });
}

/* ---------- 我的地点 ---------- */
var placesBound = false;
var placeResults = [];

function places() {
  return (State.settings && State.settings.weatherCities) || [];
}

function placeLabel(p) {
  return p.name + (p.admin ? ' · ' + p.admin : '');
}

function placeIsCurrent(p) {
  var cur = currentCity();
  if (!cur.name || cur.name !== p.name) return false;
  return Math.abs((cur.latitude || 0) - p.latitude) < 1e-4 &&
    Math.abs((cur.longitude || 0) - p.longitude) < 1e-4;
}

function applyPlacesData(d) {
  if (d && d.settings) State.settings = d.settings;
  renderPlaces();
  return d;
}

function renderPlaces() {
  var sel = $('s_city');
  if (!sel) return;
  var list = places();
  var currentId = '';
  var opts = ['<option value="">' + (currentCity().name ? '当前：' + esc(currentCity().name) : '未选择地点') + '</option>'];
  opts = opts.concat(list.map(function (p) {
    if (placeIsCurrent(p)) currentId = p.id;
    return '<option value="' + esc(p.id) + '">' + esc(placeLabel(p)) + '</option>';
  }));
  sel.innerHTML = opts.join('');
  sel.value = currentId;

  var cur = currentCity();
  if ($('s_lat')) $('s_lat').value = cur.latitude != null ? cur.latitude : '';
  if ($('s_lon')) $('s_lon').value = cur.longitude != null ? cur.longitude : '';

  var box = $('s_placeList');
  if (box) {
    if (!list.length) {
      box.innerHTML = '<span class="small faint">还没有地点，点上面的「＋ 添加地点」</span>';
    } else {
      box.innerHTML = list.map(function (p) {
        return '<div class="between" style="width:100%;padding:3px 0;border-bottom:1px dashed var(--line)">' +
          '<span class="small">' + esc(placeLabel(p)) +
          (placeIsCurrent(p) ? ' <span class="tag">当前</span>' : '') + '</span>' +
          '<button class="del" data-place="' + esc(p.id) + '" title="移除">×</button></div>';
      }).join('');
    }
  }
}

function renderCityResults(msg) {
  var box = $('s_cityResults');
  if (!box) return;
  if (!placeResults.length) {
    box.innerHTML = msg ? '<div class="small faint">' + esc(msg) + '</div>' : '';
    return;
  }
  box.innerHTML = placeResults.map(function (c, i) {
    return '<button class="ghost" data-city="' + i + '" style="margin:0 6px 6px 0">' +
      esc(c.name) + (c.admin ? ' · ' + esc(c.admin) : '') + '</button>';
  }).join('') + '<div class="small faint">点一个加进「我的地点」</div>';
}

function addPlace(c) {
  return api('/api/places', {
    method: 'POST',
    body: { name: c.name, admin: c.admin || '', latitude: c.latitude, longitude: c.longitude }
  }).then(function (d) {
    applyPlacesData(d);
    placeResults = [];
    renderCityResults();
    if ($('s_placeAddBox')) $('s_placeAddBox').style.display = 'none';
    if ($('s_cityQ')) $('s_cityQ').value = '';
    toast(d.created ? ('已添加 ' + d.place.name) : ('已切换到 ' + d.place.name));
    if (typeof loadWeather === 'function') loadWeather(true);
    return d;
  });
}

function doPlaceSearch() {
  var q = $('s_cityQ').value.trim();
  if (!q) { toast('先输入城市名'); return; }
  api('/api/cities?q=' + encodeURIComponent(q)).then(function (d) {
    placeResults = d.cities || [];
    renderCityResults(placeResults.length ? '' : '没搜到，换个词或直接手填坐标');
  }).catch(function () {
    placeResults = [];
    renderCityResults('搜索失败，检查网络或直接手填坐标');
  });
}

function bindPlaces() {
  if (placesBound) return;
  placesBound = true;
  $('s_cityToggle').addEventListener('click', function () {
    var box = $('s_placeAddBox');
    var open = box.style.display !== 'none';
    box.style.display = open ? 'none' : 'flex';
    if (!open) $('s_cityQ').focus();
  });
  $('s_city').addEventListener('change', function () {
    var id = this.value;
    if (!id) return;
    api('/api/places/select', { method: 'POST', body: { id: id } }).then(function (d) {
      applyPlacesData(d);
      toast('已切换到 ' + d.place.name);
      if (typeof loadWeather === 'function') loadWeather(true);
    });
  });
  $('s_citySearchBtn').addEventListener('click', doPlaceSearch);
  $('s_cityQ').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') doPlaceSearch();
  });
  $('s_cityResults').addEventListener('click', function (e) {
    var idx = e.target.getAttribute && e.target.getAttribute('data-city');
    if (idx === null || idx === undefined) return;
    var c = placeResults[parseInt(idx, 10)];
    if (c) addPlace(c);
  });
  $('s_placeList').addEventListener('click', function (e) {
    var id = e.target.getAttribute && e.target.getAttribute('data-place');
    if (!id) return;
    api('/api/places', { method: 'DELETE', body: { id: id } }).then(function (d) {
      applyPlacesData(d);
      toast('已移除');
      if (typeof loadWeather === 'function') loadWeather(true);
    });
  });
}

function periodRowHtml(p, idx, total) {
  return '<div class="prow" data-id="' + esc(p.id) + '">' +
    '<input class="p_label" value="' + esc(p.label) + '" placeholder="名称，如 第 1-2 节">' +
    '<input class="p_start" type="time" value="' + esc(p.start) + '">' +
    '<input class="p_end" type="time" value="' + esc(p.end) + '">' +
    '<button class="del" data-act="del" title="删除">×</button>' +
    '<div class="row" style="gap:4px">' +
    '<button data-act="up"' + (idx === 0 ? ' disabled' : '') + ' style="padding:4px 8px">↑</button>' +
    '<button data-act="down"' + (idx === total - 1 ? ' disabled' : '') + ' style="padding:4px 8px">↓</button>' +
    '</div></div>';
}

function renderPeriods() {
  var list = (State.settings && State.settings.periods) || [];
  var box = $('perList');
  if (!list.length) {
    box.innerHTML = '<div class="empty"><b>还没有节次</b>点下面的按钮自己添加，名称和时间随便填</div>';
    return;
  }
  box.innerHTML = list.map(function (p, i) {
    return periodRowHtml(p, i, list.length);
  }).join('');
  Array.prototype.forEach.call(box.querySelectorAll('.prow'), function (row) {
    var id = row.dataset.id;
    var label = row.querySelector('.p_label');
    var start = row.querySelector('.p_start');
    var end = row.querySelector('.p_end');
    var push = debounce(function () {
      api('/api/settings/period', {
        method: 'PUT',
        body: { id: id, label: label.value, start: start.value, end: end.value }
      }).then(function () { reloadSettings(); });
    }, 400);
    label.addEventListener('input', push);
    start.addEventListener('input', push);
    end.addEventListener('input', push);
    row.querySelector('[data-act=del]').addEventListener('click', function () { removePeriod(id); });
    var up = row.querySelector('[data-act=up]');
    var down = row.querySelector('[data-act=down]');
    if (up) up.addEventListener('click', function () { movePeriod(id, 'up'); });
    if (down) down.addEventListener('click', function () { movePeriod(id, 'down'); });
  });
}

function movePeriod(id, direction) {
  api('/api/settings/period/move', { method: 'POST', body: { id: id, direction: direction } })
    .then(function () { reloadSettings(); });
}

function removePeriod(id) {
  api('/api/settings/period', { method: 'DELETE', body: { id: id, mode: 'cancel' } })
    .then(function (res) {
      if (!res.deleted && res.used) {
        showDlg('删除这个节次',
          '<div class="small">有 <b>' + res.used + '</b> 节课用到了它，要怎么处理？</div>' +
          '<div class="field" style="margin-top:12px"><label>处理方式</label>' +
          '<select id="dm"><option value="move">把这些课改挂到其他节次</option>' +
          '<option value="drop">连同这些课一起删除</option>' +
          '<option value="cancel">取消，先不改</option></select></div>',
          [{
            text: '确定', kind: 'primary', onClick: function () {
              var mode = document.getElementById('dm').value;
              closeDlg();
              if (mode === 'cancel') return;
              api('/api/settings/period', { method: 'DELETE', body: { id: id, mode: mode } })
                .then(function () { toast('已删除'); reloadSettings().then(renderCoursesTable); });
            }
          }, { text: '取消', onClick: closeDlg }]);
        return;
      }
      toast('已删除');
      reloadSettings();
    });
}

function reloadSettings() {
  return api('/api/settings').then(function (s) {
    State.settings = s;
    renderPeriods();
    if (document.getElementById('p-courses').classList.contains('on')) renderCoursesTable();
    return s;
  });
}

function renderSettings() {
  var s = State.settings || {};
  $('s_name').value = s.displayName || '';
  $('s_sem').value = s.semesterName || '';
  $('s_w1').value = s.week1Monday || '';
  $('s_ws').value = String(s.weekStartsOn || 1);
  $('s_campus').value = s.campus || '';
  $('s_theme').value = s.theme || 'system';
  $('s_refresh').value = String(s.refreshMinutes == null ? 30 : s.refreshMinutes);
  $('s_lat').value = s.weatherCity && s.weatherCity.latitude != null ? s.weatherCity.latitude : '';
  $('s_lon').value = s.weatherCity && s.weatherCity.longitude != null ? s.weatherCity.longitude : '';
  renderPeriods();
  renderPlaces();
  if (typeof renderCityOptions === 'function') renderCityOptions();
  if (settingsBound) return;
  settingsBound = true;
  bindPlaces();

  var text = function (el, key, cast) {
    el.addEventListener('change', function () {
      var patch = {};
      patch[key] = cast ? cast(el.value) : el.value;
      saveSettings(patch).then(function () {
        toast('已保存');
        refreshDerived();
      });
    });
  };
  text($('s_name'), 'displayName');
  text($('s_sem'), 'semesterName');
  text($('s_w1'), 'week1Monday');
  text($('s_ws'), 'weekStartsOn', Number);
  text($('s_campus'), 'campus');
  text($('s_refresh'), 'refreshMinutes', Number);
  $('s_theme').addEventListener('change', function () {
    saveSettings({ theme: $('s_theme').value }).then(function () { applyTheme(); toast('已保存'); });
  });
  $('s_lonSave').addEventListener('click', function () {
    var lat = parseFloat($('s_lat').value);
    var lon = parseFloat($('s_lon').value);
    if (isNaN(lat) || isNaN(lon)) { toast('请填写正确的经纬度'); return; }
    addPlace({ name: '自定义坐标', latitude: lat, longitude: lon });
  });
  $('addPer').addEventListener('click', function () { addPeriod(); });
  $('btnFolder').addEventListener('click', function () {
    api('/api/open-folder', { method: 'POST', body: { open: true } })
      .then(function (d) { toast('已打开 ' + d.path); })
      .catch(function () { toast('打开失败，手动去 D:\\App\\MyDay\\data'); });
  });
  $('btnBackup').addEventListener('click', function () {
    fetch('/api/backup').then(function (r) { return r.blob(); }).then(function (b) {
      var url = URL.createObjectURL(b);
      var a = document.createElement('a');
      a.href = url;
      var d = new Date();
      var p = function (x) { return (x < 10 ? '0' : '') + x; };
      a.download = 'MyDay-backup-' + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) +
        '-' + p(d.getHours()) + p(d.getMinutes()) + '.zip';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      toast('备份已下载，本机也留了一份');
    });
  });
  $('btnRestore').addEventListener('click', function () {
    var f = $('restoreFile').files[0];
    if (!f) { toast('先选择一个备份 zip'); return; }
    var reader = new FileReader();
    reader.onload = function () {
      var b64 = String(reader.result).split(',')[1];
      var text = '用这份备份覆盖当前全部数据？还原前会自动给现在的数据留一份备份。';
      showDlg('还原备份', '<div class="small">' + text + '</div>' +
        '<div class="small faint" style="margin-top:8px">文件：' + esc(f.name) + '</div>', [
        { text: '取消', onClick: closeDlg },
        { text: '确认还原', kind: 'primary', onClick: function () {
          closeDlg();
          api('/api/restore', { method: 'POST', body: { filename: f.name, content: b64 } })
            .then(function (d) {
              toast('还原成功');
              return loadBootstrap();
            }).then(function () {
              return renderCourses();
            }).then(function () {
              return renderNotes();
            }).then(function () { renderHome(); renderSettings(); });
        } }
      ]);
    };
    reader.readAsDataURL(f);
  });
  $('btnReset').addEventListener('click', function () {
    showDlg('清空全部数据',
      '<div class="small">课程、备忘录、天气缓存和设置都会被清掉。清空前会自动备份一次。</div>' +
      '<div class="field" style="margin-top:12px"><label>确认方式：输入「清空」两个字</label>' +
      '<input id="resetWord" placeholder="清空"></div>',
      [{ text: '取消', onClick: closeDlg },
      { text: '确认清空', kind: 'danger', onClick: function () {
        var v = $('resetWord').value.trim();
        if (v !== '清空') { toast('请先输入「清空」两个字'); return; }
        closeDlg();
        api('/api/reset-all', { method: 'POST', body: {} }).then(function (d) {
          toast('已清空，备份文件：' + d.backupFile);
          return loadBootstrap();
        }).then(function () { return renderCourses(); })
          .then(function () { return renderNotes(); })
          .then(function () { renderHome(); renderSettings(); });
      } }]);
  });
}

function addPeriod(label, start, end) {
  return api('/api/settings/period', {
    method: 'POST', body: { label: label || '', start: start || '', end: end || '' }
  }).then(function () {
    // 必须先把最新设置拉回来，否则列表还是旧状态，界面上看不到新加的那条
    return reloadSettings();
  });
}

function refreshDerived() {
  return loadBootstrap().then(function () {
    if (document.getElementById('p-home').classList.contains('on')) renderHome();
    if (document.getElementById('p-courses').classList.contains('on')) renderCoursesTable();
  });
}

/* ---------- 课程 ---------- */
var curWeek = 1;
var courseBound = false;

function dayOrder() {
  var start = (State.settings && State.settings.weekStartsOn) || 1;
  var nums = [], i;
  if (start === 7) {
    nums = [7, 1, 2, 3, 4, 5, 6];
  } else {
    nums = [1, 2, 3, 4, 5, 6, 7];
  }
  var names = { 1: '周一', 2: '周二', 3: '周三', 4: '周四', 5: '周五', 6: '周六', 7: '周日' };
  return nums.map(function (n) { return { num: n, name: names[n] }; });
}

function weekRangeText(week) {
  var w1 = State.settings && State.settings.week1Monday;
  if (!w1) return '（先设置第 1 周周一才有日期）';
  var d = new Date(w1 + 'T00:00:00');
  d.setDate(d.getDate() + (week - 1) * 7);
  var end = new Date(d.getTime());
  end.setDate(end.getDate() + 6);
  var f = function (x) { return (x.getMonth() + 1) + '月' + x.getDate() + '日'; };
  return f(d) + ' - ' + f(end);
}

function initWeekSel() {
  var sel = $('weekSel');
  sel.innerHTML = '';
  for (var i = 1; i <= 20; i++) {
    var o = document.createElement('option');
    o.value = i;
    o.textContent = '第 ' + i + ' 周';
    sel.appendChild(o);
  }
  sel.addEventListener('change', function () {
    curWeek = parseInt(sel.value, 10);
    renderCourses();
  });
  if (!courseBound) {
    courseBound = true;
    $('toToday').addEventListener('click', function () {
      var w = State.weekMeta && State.weekMeta.week;
      if (!w) { toast('还没设置第 1 周周一，去设置页填一下'); return; }
      curWeek = w;
      $('weekSel').value = w;
      renderCourses();
    });
    $('addCourse').addEventListener('click', function () { openCourseDialog(null); });
    $('copyWeek').addEventListener('click', copyWeekDialog);
    $('importTt').addEventListener('click', pickTimetableFile);
    $('clearWeek').addEventListener('click', function () {
      showDlg('清空第 ' + curWeek + ' 周',
        '<div class="small">会删掉这一周的全部课程，不可撤销。</div>',
        [{ text: '确认清空', kind: 'danger', onClick: function () {
            closeDlg();
            api('/api/courses/clear', { method: 'POST', body: { week: curWeek } })
              .then(function () { toast('已清空'); renderCourses(); });
          } }, { text: '取消', onClick: closeDlg }]);
    });
  }
}

function renderCourses() {
  return api('/api/courses?week=' + curWeek).then(function (d) {
    State.courses = d.list;
    if (State.courses === undefined) State.courses = [];
    renderCoursesTable();
  });
}

function renderCoursesTable() {
  if (!State.settings) return;
  var periods = State.settings.periods || [];
  var card = $('ttCard');
  $('weekRange').textContent = weekRangeText(curWeek);
  $('weekStat').textContent = '本周 ' + (State.courses || []).length + ' 节课';
  if (!periods.length) {
    card.innerHTML = '<div class="empty"><b>还没有任何节次</b>' +
      '节次名称和时间完全由你定义，去「数据与设置 → 作息与节次」添加后，' +
      '这里会出现对应的课表网格</div>';
    return;
  }
  var days = dayOrder();
  var head = '<th style="width:92px"></th>' + days.map(function (d) {
    var today = State.weekMeta || {};
    var isToday = today.week === curWeek && today.dow === d.num;
    return '<th' + (isToday ? ' style="color:var(--accent)"' : '') + '>' + d.name + '</th>';
  }).join('');
  var rows = '';
  var skip = {};
  periods.forEach(function (p, pi) {
    rows += '<tr><td class="slot">' + esc(p.label || '未命名') +
      '<br><span style="font-size:10px">' + esc(timeRange(p)) + '</span></td>';
    days.forEach(function (d, di) {
      var key = pi + '-' + di;
      if (skip[key]) return;
      var lesson = (State.courses || []).filter(function (c) {
        return c.day === d.num && c.slot === p.id;
      })[0];
      var rowspan = 1;
      if (lesson && lesson.spanEnd) {
        var endIdx = periods.findIndex(function (x) { return x.id === lesson.spanEnd; });
        if (endIdx > pi) {
          rowspan = endIdx - pi + 1;
          for (var k = pi + 1; k <= endIdx; k++) skip[k + '-' + di] = true;
        }
      }
      rows += '<td' + (rowspan > 1 ? ' rowspan="' + rowspan + '"' : '') + '>' +
        (lesson ? '<div class="cb" data-id="' + esc(lesson.id) + '"><b>' + esc(lesson.name) +
          '</b><i>' + esc(periodLabel(lesson.slot)) + (lesson.spanEnd ? ' - ' + esc(periodLabel(lesson.spanEnd)) : '') +
          '</i><i>' + esc(lesson.location) + '</i></div>' : '') + '</td>';
    });
    rows += '</tr>';
  });
  card.innerHTML = '<table class="tt"><thead><tr>' + head + '</tr></thead><tbody>' + rows + '</tbody></table>';
  Array.prototype.forEach.call(card.querySelectorAll('.cb'), function (el) {
    el.addEventListener('click', function () { openCourseDialog(el.dataset.id); });
  });
}

function timeRange(p) {
  return (p.start && p.end) ? (p.start + ' - ' + p.end) : '时间未设置';
}

function periodLabel(id) {
  var list = (State.settings && State.settings.periods) || [];
  var hit = list.filter(function (p) { return p.id === id; })[0];
  return hit && hit.label ? hit.label : '未命名';
}

function periodOptions(selected) {
  var list = (State.settings && State.settings.periods) || [];
  return list.map(function (p) {
    return '<option value="' + esc(p.id) + '"' + (p.id === selected ? ' selected' : '') + '>' +
      esc(p.label || '未命名') + ' ' + esc(timeRange(p)) + '</option>';
  }).join('');
}

function openCourseDialog(id) {
  var list = (State.settings && State.settings.periods) || [];
  if (!list.length) {
    showDlg('还不能添加课程',
      '<div class="small">节次列表是空的，先到「数据与设置 → 作息与节次」里添加至少一条节次。</div>',
      [{ text: '知道了', onClick: closeDlg }]);
    return;
  }
  var lesson = null;
  if (id) {
    lesson = (State.courses || []).filter(function (c) { return c.id === id; })[0];
  }
  var dowDefault = lesson ? lesson.day : ((State.weekMeta && State.weekMeta.dow) || 1);
  var days = dayOrder();
  var html =
    '<div class="field"><label>课程名</label><input id="f_name" value="' + esc(lesson && lesson.name) + '" placeholder="自己填"></div>' +
    '<div class="two"><div class="field"><label>星期</label><select id="f_day">' +
    days.map(function (d) {
      return '<option value="' + d.num + '"' + (d.num === dowDefault ? ' selected' : '') + '>' + d.name + '</option>';
    }).join('') + '</select></div>' +
    '<div class="field"><label>开始节次</label><select id="f_slot">' +
    periodOptions(lesson ? lesson.slot : list[0].id) + '</select></div></div>' +
    '<div class="field"><label>跨到哪一节（可选）</label><select id="f_end">' +
    '<option value="">不跨节次</option>' + periodOptions(lesson && lesson.spanEnd) + '</select></div>' +
    '<div class="two"><div class="field"><label>地点</label><input id="f_loc" value="' + esc(lesson && lesson.location) + '"></div>' +
    '<div class="field"><label>老师</label><input id="f_tea" value="' + esc(lesson && lesson.teacher) + '"></div></div>' +
    '<div class="field"><label>备注</label><input id="f_note" value="' + esc(lesson && lesson.note) + '"></div>';

  showDlg(lesson ? '编辑课程' : '添加课程', html, [
    lesson ? {
      text: '删除', kind: 'danger', onClick: function () {
        closeDlg();
        api('/api/courses', { method: 'DELETE', body: { id: lesson.id } })
          .then(function () { toast('已删除'); renderCourses(); });
      }
    } : null,
    { text: '取消', onClick: closeDlg },
    {
      text: '保存', kind: 'primary', onClick: function () {
        var body = {
          week: curWeek,
          day: parseInt($('f_day').value, 10),
          slot: $('f_slot').value,
          spanEnd: $('f_end').value,
          name: $('f_name').value.trim(),
          location: $('f_loc').value.trim(),
          teacher: $('f_tea').value.trim(),
          note: $('f_note').value.trim()
        };
        if (lesson) body.id = lesson.id;
        var p = lesson
          ? api('/api/courses', { method: 'PUT', body: body })
          : api('/api/courses', { method: 'POST', body: body });
        p.then(function () {
          closeDlg();
          toast('已保存');
          renderCourses();
          if (document.getElementById('p-home').classList.contains('on') && typeof renderHome === 'function') renderHome();
        });
      }
    }
  ].filter(Boolean));
}

function copyWeekDialog() {
  var chips = '';
  for (var i = 1; i <= 20; i++) {
    chips += '<span class="chip' + (i === Math.min(curWeek + 1, 20) ? ' on' : '') + '" data-w="' + i + '">第 ' + i + ' 周</span>';
  }
  showDlg('复制第 ' + curWeek + ' 周的课表',
    '<div class="small faint" style="margin-bottom:8px">本周共 ' + (State.courses || []).length +
    ' 节课，选择目标周（可多选），整周铺过去。</div>' +
    '<div id="dst" style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:14px">' + chips + '</div>' +
    '<div class="field"><label>遇到目标周已有课程时</label><select id="cmode">' +
    '<option value="overwrite">覆盖目标周</option>' +
    '<option value="merge">保留两边（合并）</option>' +
    '<option value="empty-only">只填空的周</option></select></div>',
    [{ text: '取消', onClick: closeDlg }, {
      text: '开始复制', kind: 'primary', onClick: function () {
        var targets = Array.prototype.map.call(document.querySelectorAll('#dst .chip.on'),
          function (el) { return parseInt(el.dataset.w, 10); });
        var mode = $('cmode').value;
        closeDlg();
        if (!targets.length) { toast('还没选目标周'); return; }
        api('/api/courses/copy', { method: 'POST', body: { from: curWeek, to: targets, mode: mode } })
          .then(function (r) {
            toast('已复制到 ' + targets.length + ' 周');
            renderCourses();
            return r;
          });
      }
    }]);
  Array.prototype.forEach.call(document.querySelectorAll('#dst .chip'), function (el) {
    el.addEventListener('click', function () { el.classList.toggle('on'); });
  });
}

/* ---------- 导入课表 ---------- */
var importPayload = null;

function pickTimetableFile() {
  var input = document.createElement('input');
  input.type = 'file';
  input.accept = '.xlsx';
  input.style.display = 'none';
  input.addEventListener('change', function () {
    var f = input.files && input.files[0];
    if (!f) return;
    if (f.size > 6 * 1024 * 1024) { toast('文件超过 6MB 了，确认一下是不是导错了'); return; }
    var reader = new FileReader();
    reader.onload = function () {
      var text = String(reader.result || '');
      var b64 = text.indexOf(',') >= 0 ? text.split(',')[1] : text;
      importPayload = b64;
      toast('正在读课表…');
      api('/api/import/preview', { method: 'POST', body: { content: b64 } })
        .then(showImportDialog)
        .catch(function () { importPayload = null; });
    };
    reader.onerror = function () { toast('文件读不出来'); };
    reader.readAsDataURL(f);
  });
  document.body.appendChild(input);
  input.click();
  setTimeout(function () { document.body.removeChild(input); }, 0);
}

function importPeriodsHtml(plan) {
  var fresh = plan.newPeriods || [];
  var reuse = plan.reusePeriods || [];
  return '<div class="small">节次：' +
    (fresh.length ? '<b>' + fresh.length + '</b> 个新的会按课表里的节次名建出来（时间留空，你后面自己填）：' +
      esc(fresh.join('、')) : '不需要新建节次') +
    (reuse.length ? '<br><span class="faint">已有的直接复用：' + esc(reuse.join('、')) + '</span>' : '') +
    '</div>';
}

function showImportDialog(plan) {
  var weeks = plan.weeks || [];
  var span = weeks.length ? (weeks[0] + ' – ' + weeks[weeks.length - 1] + ' 周') : '—';
  var rooms = {};
  (plan.courses || []).forEach(function (c) { if (c.room) rooms[c.room] = 1; });
  showDlg('导入课表',
    '<div class="small faint" style="margin-bottom:8px">' + esc(plan.sheet || '课表') +
    (plan.title ? '：' + esc(plan.title) : '') + '</div>' +
    '<div class="small" style="line-height:1.9">' +
    '读到 <b>' + plan.courseCount + '</b> 条课程记录，覆盖 <b>' + span + '</b>，' +
    '共要排 <b>' + plan.totalLessons + '</b> 节课<br>' +
    '节次 ' + (plan.periodLabels || []).length + ' 个，涉及地点 ' + Object.keys(rooms).length + ' 个' +
    '</div>' +
    '<div class="small faint" style="margin:8px 0;max-height:130px;overflow:auto">' +
    (plan.courses || []).slice(0, 12).map(function (c) {
      return '· ' + esc(c.dayText) + ' ' + esc(c.periodFrom) + '–' + esc(c.periodTo) + '　' +
        esc(c.name) + '<span class="faint">（' + esc(c.weekText) + '周' +
        (c.room ? ' · ' + esc(c.room) : '') + '）</span>';
    }).join('<br>') +
    (plan.courseCount > 12 ? '<br>… 还有 ' + (plan.courseCount - 12) + ' 条' : '') +
    '</div>' +
    importPeriodsHtml(plan) +
    (plan.warnings && plan.warnings.length ?
      '<div class="small" style="color:var(--warn);margin-top:6px">注意：' +
      esc(plan.warnings.join('；')) + '</div>' : '') +
    '<div class="field" style="margin-top:10px"><label>这次导入的课怎么放进各周</label>' +
    '<select id="imode">' +
    '<option value="merge">追加：保留已有课程，导入的加进去</option>' +
    '<option value="overwrite">覆盖：导入涉及的那几周直接替换</option>' +
    '</select></div>' +
    '<div class="small faint" style="margin-top:6px">导入前会自动备份一份，选错也能还原。</div>',
    [{ text: '取消', onClick: function () { importPayload = null; closeDlg(); } }, {
      text: '导入', kind: 'primary', onClick: function () {
        var mode = $('imode').value;
        var body = { content: importPayload, mode: mode };
        closeDlg();
        api('/api/import', { method: 'POST', body: body }).then(function (r) {
          importPayload = null;
          toast('导入完成：' + r.added + ' 节课');
          if (r.createdPeriods && r.createdPeriods.length) {
            showImportDone(r);
          } else {
            finishImport(r);
          }
        });
      }
    }]);
}

function showImportDone(r) {
  showDlg('导入完成',
    '<div class="small" style="line-height:1.9">' +
    '排入 <b>' + r.added + '</b> 节课，覆盖 ' + (r.weeks || []).length + ' 周<br>' +
    '新建节次 <b>' + r.createdPeriods.length + '</b> 个：' + esc(r.createdPeriods.join('、')) +
    '</div>' +
    '<div class="small faint" style="margin-top:8px">这些节次还没有起止时间，去「数据与设置 → 作息与节次」填一下，' +
    '首页才能显示出「正在上 / 下一节」。备份文件：' + esc(r.backupFile || '—') + '</div>',
    [{ text: '知道了', kind: 'primary', onClick: function () { closeDlg(); finishImport(r); } }]);
}

function finishImport(r) {
  var first = (r.weeks || [])[0];
  if (first) curWeek = first;
  return reloadSettings().then(function () {
    if ($('weekSel')) $('weekSel').value = curWeek;
    return renderCourses();
  }).then(function () {
    toast('已导入 ' + r.added + ' 节课，当前显示第 ' + curWeek + ' 周');
  });
}

/* ---------- 备忘录 ---------- */
var curNoteId = null;
var noteGroup = 'all';
var notesBound = false;
var saveTimer = null;
var noteDirty = false;

function noteGroupsHtml() {
  var notes = State.notes || [];
  var visible = notes.filter(function (n) { return !n.archived; });
  var tags = {};
  visible.forEach(function (n) { (n.tags || []).forEach(function (t) { tags[t] = (tags[t] || 0) + 1; }); });
  var items = [{ key: 'all', label: '全部', cnt: visible.length },
    { key: 'pinned', label: '置顶', cnt: visible.filter(function (n) { return n.pinned; }).length }];
  Object.keys(tags).forEach(function (t) { items.push({ key: 'tag:' + t, label: t, cnt: tags[t] }); });
  items.push({ key: 'archived', label: '归档', cnt: notes.filter(function (n) { return n.archived; }).length });
  return items.map(function (i) {
    return '<div class="grp' + (noteGroup === i.key ? ' on' : '') + '" data-g="' + esc(i.key) + '">' +
      esc(i.label) + '<span class="cnt">' + i.cnt + '</span></div>';
  }).join('') + '<div style="margin-top:14px"><button class="primary" id="newNote" style="width:100%">新建备忘录</button></div>';
}

function filteredNotes() {
  var notes = State.notes || [];
  var q = ($('noteSearch').value || '').trim().toLowerCase();
  var list = notes.filter(function (n) {
    if (noteGroup === 'all') return !n.archived;
    if (noteGroup === 'pinned') return !n.archived && n.pinned;
    if (noteGroup === 'archived') return !!n.archived;
    if (noteGroup.indexOf('tag:') === 0) {
      var tag = noteGroup.slice(4);
      return !n.archived && (n.tags || []).indexOf(tag) >= 0;
    }
    return true;
  });
  if (!q) return list;
  return list.filter(function (n) {
    var hay = [n.title, n.body].concat((n.items || []).map(function (i) { return i.text; })).join(' ').toLowerCase();
    return hay.indexOf(q) >= 0;
  });
}

function renderNotes() {
  return api('/api/notes?archived=1').then(function (d) {
    State.notes = d.notes;
    renderNotesList();
  });
}

function renderNotesList() {
  $('notegroups').innerHTML = noteGroupsHtml();
  Array.prototype.forEach.call(document.querySelectorAll('#notegroups .grp'), function (el) {
    el.addEventListener('click', function () { noteGroup = el.dataset.g; renderNotesList(); });
  });
  var list = filteredNotes();
  $('notelist').innerHTML = list.length ? list.map(function (n) {
    return '<div class="nrow' + (n.id === curNoteId ? ' on' : '') + '" data-id="' + esc(n.id) + '">' +
      '<div class="t">' + (n.pinned ? '★ ' : '') + esc(n.title || '无标题') + '</div>' +
      '<div class="p">' + esc(noteSubLine(n)) + '</div></div>';
  }).join('') : '<div class="empty"><b>这里还没有东西</b>右上角「新建备忘录」开始写</div>';
  Array.prototype.forEach.call(document.querySelectorAll('#notelist .nrow'), function (el) {
    el.addEventListener('click', function () {
      // 切走之前先把还没落盘的改动存了，否则刚敲完就点别的会丢
      clearTimeout(saveTimer);
      saveCurrentNote().then(function () {
        curNoteId = el.dataset.id;
        noteDirty = false;
        renderNotesList();
      });
    });
  });
  if (!notesBound) {
    notesBound = true;
    $('noteSearch').addEventListener('input', renderNotesList);
    document.addEventListener('click', function (e) {
      if (e.target && e.target.id === 'newNote') createNote();
    });
  }
  if (!curNoteId || !list.filter(function (n) { return n.id === curNoteId; }).length) {
    curNoteId = list.length ? list[0].id : null;
  }
  renderNoteDetail();
}

function currentNote() {
  return (State.notes || []).filter(function (n) { return n.id === curNoteId; })[0] || null;
}

function noteTypeText(n) {
  return (n && n.type === 'todo') ? '清单' : '笔记';
}

function noteSummary(n) {
  if (!n) return '';
  if (n.type === 'todo') {
    var items = n.items || [];
    if (!items.length) return '';
    return items.filter(function (i) { return i.done; }).length + '/' + items.length + ' 项完成';
  }
  return (n.body || '').split('\n')[0].slice(0, 20);
}

/* 列表第二行：类型 + 标签 + 摘要。没标签就不写「未分类」——
   免得看着像「这条笔记没归到任何类别」，其实它的类别就是「笔记」。 */
function noteSubLine(n) {
  var bits = [noteTypeText(n)];
  var tags = (n.tags || []).filter(Boolean);
  if (tags.length) bits.push(tags.join('、'));
  var summary = noteSummary(n);
  if (summary) bits.push(summary);
  return bits.join(' · ');
}

/* 只刷新列表里那一行，不重建右侧编辑区（否则输入框会掉焦点） */
function refreshNoteRow(n) {
  if (!n) return;
  var el = document.querySelector('#notelist .nrow[data-id="' + n.id + '"]');
  if (!el) return;
  var title = el.querySelector('.t');
  var sub = el.querySelector('.p');
  if (title) title.textContent = (n.pinned ? '★ ' : '') + (n.title || '无标题');
  if (sub) sub.textContent = noteSubLine(n);
}

function renderNoteStatus() {
  var el = $('noteStatus');
  if (!el) return;
  el.textContent = noteDirty ? '有改动…' : '已保存';
  el.className = 'small ' + (noteDirty ? '' : 'faint');
}

function scheduleNoteSave() {
  noteDirty = true;
  renderNoteStatus();
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveCurrentNote, 500);
}

function saveCurrentNote() {
  var n = currentNote();
  if (!n) return Promise.resolve(null);
  return api('/api/notes', {
    method: 'PUT',
    body: { id: n.id, title: n.title, type: n.type, body: n.body, items: n.items,
            tags: n.tags, pinned: n.pinned, archived: n.archived }
  }).then(function (saved) {
    var idx = State.notes.findIndex(function (x) { return x.id === saved.id; });
    if (idx >= 0) State.notes[idx] = saved;
    if (saved.id === curNoteId) {
      noteDirty = false;
      refreshNoteRow(saved);
      renderNoteStatus();
    }
    toast('已保存');
    return saved;
  });
}

function renderNoteDetail() {
  var n = currentNote();
  var box = $('noteDetail');
  if (!n) {
    box.innerHTML = '<div class="empty"><b>没有选中的备忘录</b>左边挑一条，或者新建一条</div>';
    return;
  }
  var bodyHtml = n.type === 'todo'
    ? '<div class="field"><label>清单</label><div id="todoList">' + (n.items || []).map(function (i, ix) {
        return '<div class="todoitem" data-ix="' + ix + '">' +
          '<input type="checkbox"' + (i.done ? ' checked' : '') + ' title="做完打个勾">' +
          '<input type="text" value="' + esc(i.text) + '" placeholder="一件事一行，写在这里">' +
          '<button class="del" title="删这一行">×</button></div>';
      }).join('') + '</div>' +
      '<div class="row" style="margin-top:6px"><button id="addTodo">+ 加一行</button>' +
      '<span class="small faint">勾上就是做完，清单进度会同步到左边列表和首页</span></div></div>'
    : '<div class="field"><label>内容</label><textarea id="noteBody" rows="12">' + esc(n.body) + '</textarea></div>';

  box.innerHTML =
    '<div class="field"><label>标题</label><input id="noteTitle" value="' + esc(n.title) + '"></div>' +
    '<div class="field"><label>标签（逗号分隔）</label><input id="noteTags" value="' + esc((n.tags || []).join('、')) + '"></div>' +
    '<div class="field"><label>类型</label><select id="noteType">' +
    '<option value="text"' + (n.type === 'text' ? ' selected' : '') + '>笔记</option>' +
    '<option value="todo"' + (n.type === 'todo' ? ' selected' : '') + '>清单</option></select></div>' +
    bodyHtml +
    '<div class="row" style="margin-top:12px">' +
    '<button class="primary" id="saveNote">保存</button>' +
    '<span id="noteStatus" class="small faint" style="min-width:52px"></span>' +
    '<button id="togglePin">' + (n.pinned ? '取消置顶' : '置顶') + '</button>' +
    '<button id="toggleArch">' + (n.archived ? '还原' : '归档') + '</button>' +
    '<button class="danger" id="delNote">删除</button></div>';

  $('noteTitle').addEventListener('input', function () { n.title = this.value; scheduleNoteSave(); });
  $('noteTags').addEventListener('input', function () {
    n.tags = this.value.split(/[,，、]/).map(function (s) { return s.trim(); }).filter(Boolean);
    scheduleNoteSave();
  });
  $('noteType').addEventListener('change', function () {
    n.type = this.value;
    if (n.type === 'todo' && !n.items.length) n.items = [{ text: '', done: false }];
    n.body = n.body || '';
    api('/api/notes', { method: 'PUT', body: n }).then(function (s) { renderNotes(); });
  });
  if (n.type === 'text') {
    $('noteBody').addEventListener('input', function () { n.body = this.value; scheduleNoteSave(); });
  } else {
    Array.prototype.forEach.call(box.querySelectorAll('.todoitem'), function (row) {
      var ix = parseInt(row.dataset.ix, 10);
      row.querySelector('input[type=checkbox]').addEventListener('change', function () {
        n.items[ix].done = this.checked; saveCurrentNote().then(renderNotesList);
      });
      row.querySelector('input[type=text]').addEventListener('input', function () {
        n.items[ix].text = this.value; scheduleNoteSave();
      });
      row.querySelector('.del').addEventListener('click', function () {
        n.items.splice(ix, 1); saveCurrentNote().then(function () { renderNotes(); });
      });
    });
    $('addTodo').addEventListener('click', function () {
      n.items.push({ text: '', done: false });
      saveCurrentNote().then(function () { renderNotes(); });
    });
  }
  $('saveNote').addEventListener('click', function () {
    clearTimeout(saveTimer);
    saveCurrentNote().then(function (saved) {
      if (saved) refreshNoteRow(saved);
    });
  });
  $('togglePin').addEventListener('click', function () {
    n.pinned = !n.pinned; saveCurrentNote().then(function () { renderNotes(); });
  });
  $('toggleArch').addEventListener('click', function () {
    n.archived = !n.archived; saveCurrentNote().then(function () { renderNotes(); });
  });
  $('delNote').addEventListener('click', function () {
    showDlg('删除这条备忘录', '<div class="small">删除后不可恢复。</div>', [
      { text: '取消', onClick: closeDlg },
      { text: '删除', kind: 'danger', onClick: function () {
        closeDlg();
        api('/api/notes', { method: 'DELETE', body: { id: n.id } })
          .then(function () { curNoteId = null; toast('已删除'); renderNotes(); });
      } }
    ]);
  });
  renderNoteStatus();
}

function createNote() {
  api('/api/notes', { method: 'POST', body: { title: '', type: 'text', tags: [] } })
    .then(function (n) {
      curNoteId = n.id;
      noteGroup = 'all';
      return renderNotes();
    }).then(function () { toast('已新建'); });
}

/* ---------- 首页 ---------- */
function renderHome() {
  return api('/api/home').then(function (d) {
    State.weekMeta = d.meta;
    State.settings = State.settings || {};
    renderTopbar();
    $('greet').textContent = d.greeting + (d.meta.displayName ? '，' + d.meta.displayName : '');
    var bits = [d.meta.today + ' ' + weekdayCn(d.meta.dow)];
    bits.push(d.meta.week ? '第 ' + d.meta.week + ' 教学周' : '教学周未设置');
    if (d.meta.campus) bits.push(d.meta.campus);
    if (d.meta.semesterName) bits.push(d.meta.semesterName);
    $('homedate').textContent = bits.join(' · ');
    $('hometags').innerHTML = (d.meta.week ? '<span class="tag b">第 ' + d.meta.week + ' 周</span>' :
      '<span class="tag w">未设置教学周</span>') +
      '<span class="tag">今日 ' + d.todayCount + ' 节课</span>';
    $('homelessons').innerHTML = homeLessonsHtml(d);
    $('homewx').innerHTML = homeWeatherHtml(d.weather);
    $('homenotes').innerHTML = homeNotesHtml(d.notesPreview);
    Array.prototype.forEach.call(document.querySelectorAll('#homenotes [data-note]'), function (el) {
      el.addEventListener('click', function () {
        curNoteId = el.dataset.note;
        noteGroup = 'all';
        go('notes');
      });
    });
    return d;
  });
}

function weekdayCn(dow) {
  var m = { 1: '周一', 2: '周二', 3: '周三', 4: '周四', 5: '周五', 6: '周六', 7: '周日' };
  return m[dow] || '';
}

function homeLessonsHtml(d) {
  if (!d.hasPeriods) {
    return '<div class="empty"><b>还没有任何节次</b>先到「数据与设置」里添加自己的节次和时间，再回来排课</div>';
  }
  if (!d.meta.week) {
    return '<div class="empty"><b>还不知道今天是第几周</b>去设置里填一下第 1 周周一的日期</div>';
  }
  if (!d.todayLessons.length) {
    return '<div class="empty"><b>今天没课</b>休息一下</div>';
  }
  return d.todayLessons.map(function (item) {
    var cls = 'lesson' + (item.status === 'now' ? ' now' : item.status === 'done' ? ' done' : '');
    var badge = item.status === 'now' ? '<span class="tag">正在上</span> '
      : item.next ? '<span class="tag b">下一节</span> ' : '';
    return '<div class="' + cls + '"><div class="time">' + esc(item.periodLabel) +
      '<br>' + esc(item.periodRange) + '</div><div><div class="name">' + badge +
      esc(item.lesson.name) + '</div><div class="loc">' +
      esc([item.lesson.location, item.lesson.teacher].filter(Boolean).join(' · ')) + '</div></div></div>';
  }).join('');
}

function homeWeatherHtml(wxState) {
  if (!wxState || wxState.state === 'no_city') {
    return '<div class="empty"><b>还没选城市</b>到天气页或设置里选一个，就能看到实况和预报</div>';
  }
  if (wxState.state === 'error') {
    return '<div class="empty"><b>暂时取不到天气</b>其他地方照常能用，过会儿再试</div>';
  }
  var cur = (wxState.payload && wxState.payload.current) || {};
  var today = ((wxState.payload || {}).daily || [])[0] || {};
  return '<div class="wx"><div class="ico"></div><div><div class="temp">' +
    (cur.temp == null ? '--' : cur.temp) + '°</div>' +
    '<div class="small muted">' + esc(cur.text || '') + ' · ' + esc(((wxState.payload || {}).city || {}).name || '') +
    '</div></div></div>' +
    (wxState.stale ? '<div class="small faint" style="margin-top:6px">网络不可用，显示的是 ' +
      esc((wxState.fetchedAt || '').slice(5, 16)) + ' 的数据</div>' : '') +
    '<div class="kv">' +
    kv('体感', num(cur.feels, '°')) + kv('湿度', num(cur.humidity, '%')) +
    kv('风', (cur.windDir || '') + ' ' + num(cur.wind, ' m/s')) +
    kv('最低 / 最高', num(today.min, '°') + ' / ' + num(today.max, '°')) +
    '</div>';
}

function homeNotesHtml(list) {
  if (!list || !list.length) {
    return '<div class="empty"><b>还没有备忘录</b>想到什么随手记一条</div>';
  }
  return list.map(function (n) {
    var tags = (n.tags || []).filter(Boolean);
    return '<div class="between" style="padding:7px 0;border-bottom:1px solid var(--line);cursor:pointer" data-note="' +
      esc(n.id) + '"><div><div>' + (n.pinned ? '<span class="tag w">置顶</span> ' : '') +
      esc(n.title) + '</div><span class="small faint">' + esc(n.summary || '空') + '</span></div>' +
      '<span class="tag g">' + esc(tags.length ? tags.join('、') : noteTypeText(n)) + '</span></div>';
  }).join('');
}

/* ---------- 天气 ---------- */
var citiesCache = [];
var weatherBound = false;
var WEEK_CN = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

function currentCity() {
  return (State.settings && State.settings.weatherCity) || { name: '', latitude: null, longitude: null };
}

function loadWeather(force) {
  return api('/api/weather' + (force ? '?refresh=1' : '')).then(function (d) {
    State.weather = d;
    renderWeatherBody();
    return d;
  }).catch(function (err) {
    if (String(err.message).indexOf('还没选城市') >= 0) {
      State.weather = null;
      $('wxBody').innerHTML = '<div class="card"><div class="empty"><b>先选一个城市</b>' +
        '软件不预设任何地区，选好之后这里会显示实况、24 小时温度和未来 7 天预报</div></div>';
      $('wxStamp').textContent = '城市未设置';
      return null;
    }
    State.weather = null;
    $('wxBody').innerHTML = '<div class="card"><div class="empty"><b>暂时取不到天气</b>' +
      '其他地方都能正常用，过一会儿再点刷新试试</div></div>';
    $('wxStamp').textContent = '取数据失败';
    return null;
  });
}

function renderCityOptions() {
  var sel = $('citySel');
  if (!sel) return;
  var city = currentCity();
  var opts = ['<option value="">' + (city.name ? esc(city.name) : '未选择城市') + '</option>'];
  opts = opts.concat(citiesCache.map(function (c, i) {
    return '<option value="' + i + '">' + esc(c.name) + (c.admin ? ' · ' + esc(c.admin) : '') + '</option>';
  }));
  sel.innerHTML = opts.join('');
}

function bindWeather() {
  if (weatherBound) return;
  weatherBound = true;
  $('citySel').addEventListener('change', function () {
    var v = this.value;
    if (v === '') return;
    var c = citiesCache[parseInt(v, 10)];
    if (!c) return;
    api('/api/places', {
      method: 'POST',
      body: { name: c.name, admin: c.admin || '', latitude: c.latitude, longitude: c.longitude }
    }).then(function (d) {
      currentCityValue = c;
      applyPlacesData(d);
      renderCityOptions();
      return loadWeather(true);
    }).then(function () { toast('已切换到 ' + c.name); });
  });
  $('citySearchBtn').addEventListener('click', doCitySearch);
  $('citySearch').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') doCitySearch();
  });
  $('wxRefresh').addEventListener('click', function () { loadWeather(true); });
}

var currentCityValue = null;

function doCitySearch() {
  var q = $('citySearch').value.trim();
  if (!q) { toast('先输入城市名'); return; }
  api('/api/cities?q=' + encodeURIComponent(q)).then(function (d) {
    citiesCache = d.cities || [];
    if (!citiesCache.length) { toast('没搜到，检查一下网络'); return; }
    renderCityOptions();
    $('citySel').value = '0';
    toast('搜到 ' + citiesCache.length + ' 个，选择即可');
  });
}

function renderWeather() {
  bindWeather();
  renderCityOptions();
  return loadWeather(false);
}

function renderWeatherBody() {
  var d = State.weather;
  if (!d) return;
  var p = d.payload || {};
  var cur = p.current || {};
  var stamp = d.fetchedAt ? d.fetchedAt.slice(11, 16) : '--:--';
  $('wxStamp').textContent = '更新于 ' + stamp + (d.stale ? '（旧数据，网络不可用）' : '') + ' · 数据源 Open-Meteo';
  var hours = p.hourly || [];
  var temps = hours.map(function (h) { return h.temp; }).filter(function (t) { return typeof t === 'number'; });
  var max = temps.length ? Math.max.apply(null, temps) : 1;
  var min = temps.length ? Math.min.apply(null, temps) : 0;
  var span = Math.max(max - min, 1);
  var tips = (p.tips || []).join('；');
  var minutes = (p.hourly || []);
  $('wxBody').innerHTML =
    '<div class="grid">' +
    '<div class="card g3"><div class="between">' +
    '<div class="wx" style="gap:18px"><div class="ico" style="width:56px;height:56px"></div>' +
    '<div><div class="temp" style="font-size:46px">' + (cur.temp == null ? '--' : cur.temp) + '°</div>' +
    '<div class="muted">' + esc(cur.text || '') + ' · ' + esc((p.city || {}).name || '') + '</div></div></div>' +
    '<div style="text-align:right;max-width:220px">' +
    (tips ? '<span class="tag w">' + esc(tips) + '</span>' : '<span class="small faint">暂无特别提示</span>') +
    '</div></div>' +
    '<div class="kv" style="grid-template-columns:repeat(4,1fr);margin-top:14px">' +
    kv('体感', num(cur.feels, '°')) + kv('湿度', num(cur.humidity, '%')) +
    kv('风', (cur.windDir || '') + ' ' + num(cur.wind, ' m/s')) +
    kv('气压', num(cur.pressure, ' hPa')) +
    kv('能见度', num(cur.visibility, ' km')) + kv('降水概率', num(cur.pop, '%')) +
    kv('今日最高', num((p.daily || [])[0] && p.daily[0].max, '°')) +
    kv('今日最低', num((p.daily || [])[0] && p.daily[0].min, '°')) +
    '</div></div>' +
    '<div class="card g2"><h3>未来 24 小时 <span class="link">温度</span></h3>' +
    '<div class="hours">' + minutes.map(function (h) {
      var hgt = (typeof h.temp === 'number') ? Math.round(16 + (h.temp - min) / span * 52) : 8;
      return '<div style="height:' + hgt + 'px">' + (h.temp == null ? '' : Math.round(h.temp)) + '</div>';
    }).join('') + '</div>' +
    '<div class="small faint" style="display:flex;justify-content:space-between">' +
    '<span>' + esc((minutes[0] || {}).time || '现在') + '</span><span>8 小时后</span>' +
    '<span>16 小时后</span><span>' + esc((minutes[minutes.length - 1] || {}).time || '') + '</span></div></div>' +
    '<div class="card g3"><h3>未来 7 天</h3>' +
    (p.daily || []).map(function (day) {
      var dnum = new Date(day.date + 'T00:00:00').getDay();
      return '<div class="fc"><div class="d">' + WEEK_CN[dnum] + ' ' + day.date.slice(5) + '</div>' +
        '<div style="width:110px">' + esc(day.text) + '</div>' +
        '<div class="bar"></div>' +
        '<div style="width:96px;text-align:right">' + day.min + '° / ' + day.max + '°</div></div>';
    }).join('') + '</div></div>';
}

function kv(label, value) {
  return '<div><span class="muted">' + esc(label) + '</span><span>' + esc(value) + '</span></div>';
}

function num(v, suffix) {
  return (v === null || v === undefined || v === '') ? '—' : v + (suffix || '');
}

/* ---------- 启动 ---------- */
function boot() {
  initWeekSel();
  loadBootstrap().then(function () {
    var w = State.weekMeta && State.weekMeta.week;
    curWeek = w || 1;
    $('weekSel').value = curWeek;
    return renderCourses();
  }).then(function () {
    renderSettingsPanelIfVisible();
    return renderHome();
  }).catch(function (e) {
    $('today').textContent = '服务未连上';
    $('weekpill').textContent = '看看控制台窗口';
    console.error(e);
  });
}

function renderSettingsPanelIfVisible() {
  if (document.getElementById('p-settings').classList.contains('on')) renderSettings();
}

/* 启动：只要这一处，任何多余调用都会让 boot() 执行不到 */
boot();
