#!/usr/bin/env node
/**
 * render.js — 单接口占位符渲染引擎（vars.sh 调用）
 *
 * 输入（经环境变量传递，避免命令行注入与转义问题）:
 *   IF_RAW_URL   url.raw 原文
 *   IF_METHOD    HTTP 方法
 *   IF_SVC       服务短名（core/agentorbit/...，internalToken 按服务选值）
 *   IF_HEADERS   header 数组 JSON（已过滤 disabled）
 *   IF_BODY      body 编码串（raw: JSON.stringify(raw)；formdata: {mode,...}；空串=无 body）
 *   IFACE_FILE   config/iface.json（读取 route 映射）
 *   VARS_FILE    变量表 vars.json（base/creds/captured/params）
 *   WORK_DIR     工作目录（渲染后 body 落盘 render-body.json）
 *
 * 输出（stdout，制表符分隔的 key\tvalue 行，bash 逐行解析，禁 eval）:
 *   url\t<渲染后完整 URL>
 *   path\t<path+query>（进度日志展示用）
 *   header\t<Key: Value>（多行，同名去重后）
 *   bodyFile\t<路径>（有 raw body 时）
 *   missing\t<缺失原因>（多行或无；非空 → 调用方判 SKIP）
 *
 * 替换顺序（设计 5.2）: :id 归一为 {{var}} → 变量表统一替换 → baseUrl 已在变量表收敛。
 * 缺失分类: 路径参数缺失（:param 无 route 映射）/ 前置数据缺失（CAPTURED.* 未捕获）/
 *           凭据缺失（token/pat/internalToken/openAccessToken/citicSecret 为空）/
 *           未定义变量 / 请求体JSON非法 / formdata暂不支持。
 */
'use strict';
const fs = require('fs');

const env = process.env;
const iface = JSON.parse(fs.readFileSync(env.IFACE_FILE, 'utf8'));
const vars = JSON.parse(fs.readFileSync(env.VARS_FILE, 'utf8'));
const route = iface.route || {};
const workDir = env.WORK_DIR;

const rawUrl = env.IF_RAW_URL || '';
const svc = env.IF_SVC || '';
const headers = JSON.parse(env.IF_HEADERS || '[]');
const bodyEnc = env.IF_BODY || '';

const missing = [];
const CRED_KEYS = new Set(['token', 'pat', 'openAccessToken', 'citicSecret', 'internalToken']);

/** 变量解析：返回 { value } 或 { missing } */
function resolveVar(name) {
  if (vars.base && name in vars.base) return { value: vars.base[name] };
  if (name === 'internalToken') {
    const key = svc.indexOf('agentorbit') >= 0 ? 'agentorbit'
      : svc.indexOf('telemetry') >= 0 ? 'telemetry' : 'core';
    return { value: (vars.creds.internalToken || {})[key] || '' };
  }
  if (vars.creds && name in vars.creds) {
    const v = vars.creds[name];
    if (!v && CRED_KEYS.has(name)) return { value: v, missing: `凭据缺失:{{${name}}}` };
    return { value: v };
  }
  if (vars.captured && name in vars.captured) {
    const v = vars.captured[name];
    if (v === '' || v == null) return { value: '', missing: `前置数据缺失:{{${name}}}` };
    return { value: v };
  }
  if (vars.params && name in vars.params) return { value: String(vars.params[name]) };
  return { value: '', missing: `未定义变量:{{${name}}}` };
}

/** 统一 {{var}} 替换：逐个占位符解析，空值凭据/未定义记入 missing（跳过内部 MISSING_ 占位） */
function replaceVars(text) {
  let out = text;
  const seen = new Set();
  for (const m of text.match(/\{\{([\w.]+)\}\}/g) || []) {
    const name = m.slice(2, -2);
    if (name.startsWith('MISSING_')) continue; // 内部占位符，由 missing 记录驱动 SKIP
    if (seen.has(name)) continue;
    seen.add(name);
    const r = resolveVar(name);
    if (r.missing && !missing.includes(r.missing)) missing.push(r.missing);
    out = out.split(m).join(r.value != null ? String(r.value) : '');
  }
  return out;
}

// ---- 1) :id 路径参数归一为 {{var}}（段级处理，兼容 :id:\d+ 正则后缀形式）----
function normalizeRouteParams(text) {
  const parts = text.split('/');
  for (let i = 0; i < parts.length; i++) {
    const seg = parts[i];
    if (seg.startsWith(':')) {
      // 去掉 :\d+ 等正则后缀（如 ':id:\d+' → ':id'）；query 部分不含 ':' 段
      const base = seg.split(':')[1] || '';
      if (!/^[\w-]+$/.test(base)) continue;
      const routeKey = `:${base}`;
      const mapped = route[routeKey];
      if (mapped) {
        parts[i] = seg.split(':').slice(0, 2).join(':');
        parts[i] = `{{${mapped.replace(/^\{\{|\}\}$/g, '')}}}`;
      } else {
        // 未映射：查 params.json 同名键兜底（如 :fileName）
        const fallback = vars.params ? vars.params[base] : undefined;
        if (fallback !== undefined && fallback !== '') {
          parts[i] = String(fallback);
        } else {
          missing.push(`路径参数缺失:${routeKey}`);
          parts[i] = `{{MISSING_${base}}}`;
        }
      }
    }
  }
  return parts.join('/');
}

// ---- 2) URL 渲染 ----
let url = normalizeRouteParams(rawUrl);
url = replaceVars(url);
// 清理未解析残留占位符（缺失已记录，URL 不实际发出）；压缩 :id 清空残留的连续斜杠（保留 http://）
url = url.replace(/\{\{MISSING_[\w.-]+\}\}/g, '');
url = url.replace(/([^:])\/{2,}/g, '$1/');
const pathForLog = url.replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^/]+/, '');

// ---- 3) header 渲染（同名去重：Authorization 优先 Bearer 形式，api.json 双头陷阱）----
const byKey = {};
for (const h of headers) {
  const k = h.key.toLowerCase();
  if (byKey[k]) {
    if (k === 'authorization') {
      const curBearer = /bearer/i.test(h.value || '');
      const prevBearer = /bearer/i.test(byKey[k].orig || '');
      if (curBearer && !prevBearer) byKey[k] = { key: h.key, orig: h.value };
    }
    continue; // 其余同名冲突：保留首个（确定性规则）
  }
  byKey[k] = { key: h.key, orig: h.value };
}
const outHeaderLines = [];
for (const k of Object.keys(byKey)) {
  const h = byKey[k];
  const value = replaceVars(h.orig || '');
  const clean = String(value).replace(/\{\{MISSING_[\w.-]+\}\}/g, '');
  if (clean.trim() === '' && h.orig && /\{\{/.test(h.orig)) {
    continue; // 凭据缺失头不输出（missing 已记录，接口整体 SKIP）
  }
  outHeaderLines.push(`header\t${h.key}: ${clean}`);
}

// ---- 4) body 渲染（raw JSON 替换 + 合法性校验；formdata 暂不支持）----
let bodyFileLine = '';
if (bodyEnc) {
  let bodyObj;
  try { bodyObj = JSON.parse(bodyEnc); } catch (e) { bodyObj = null; }
  if (bodyObj !== null && typeof bodyObj === 'string') {
    let raw = replaceVars(bodyObj);
    raw = raw.replace(/\{\{MISSING_[\w.-]+\}\}/g, '');
    try {
      JSON.parse(raw); // 合法性校验（设计 5.2）
      const p = `${workDir}/render-body.json`;
      fs.writeFileSync(p, raw);
      bodyFileLine = `bodyFile\t${p}`;
    } catch (e) {
      missing.push('请求体JSON非法');
    }
  } else if (bodyObj !== null && bodyObj.mode === 'formdata') {
    missing.push('formdata暂不支持(Phase2)');
  } else if (bodyObj !== null) {
    missing.push('请求体格式未知');
  }
}

// ---- 输出 ----
const lines = [`url\t${url}`, `path\t${pathForLog}`];
lines.push(...outHeaderLines);
if (bodyFileLine) lines.push(bodyFileLine);
for (const m of missing) lines.push(`missing\t${m}`);
process.stdout.write(lines.join('\n') + '\n');
