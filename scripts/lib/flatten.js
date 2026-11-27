#!/usr/bin/env node
/**
 * flatten.js — api.json 递归展平为接口清单 TSV
 *
 * 用法: node flatten.js <api.json> <out.tsv> <out.stats.txt>
 *
 * TSV 字段（0x1F US 单元分隔符分隔——bash read 对连续 tab 会压缩致字段错位，故不用 \t）:
 *   1 domain     域（L1 中文名，如 认证授权域）
 *   2 svc        服务短名（core / sso / adapter-ads ...）
 *   3 svcFull    服务目录全名（asdm-admin-services-core (端口 8880)）
 *   4 module     模块名（Postman L3 分组）
 *   5 name       接口名称（保留中英文原名）
 *   6 method     HTTP 方法
 *   7 rawUrl     url.raw 原文（含 {{xxxBaseUrl}} 前缀与 query）
 *   8 headersJ   过滤 disabled 后的 header 数组 JSON
 *   9 bodyJ      body 编码：raw 模式为 JSON.stringify(raw) 字符串；formdata 为 {mode,...} 对象；无 body 为空串
 *  10 queryJ     url.query 数组 JSON（无则空串）
 */
'use strict';
const fs = require('fs');

const [, , apiPath, tsvPath, statsPath] = process.argv;
if (!apiPath || !tsvPath || !statsPath) {
  console.error('用法: node flatten.js <api.json> <out.tsv> <out.stats.txt>');
  process.exit(2);
}

const collection = JSON.parse(fs.readFileSync(apiPath, 'utf8'));
const rows = [];

/** 'asdm-admin-services-core (端口 8880)' → 'core' */
function svcShort(full) {
  const m = /^asdm-admin-services-(.+?)\s*(?:\(端口.*\))?$/.exec(full);
  return m ? m[1] : full;
}

function walk(items, depth, domain, svcFull, moduleName) {
  for (const it of items || []) {
    if (it.item) {
      // 层级语义: L0=域 L1=服务 L2+=模块（更深嵌套按模块更新）
      if (depth === 0) walk(it.item, 1, it.name, '', it.name);
      else if (depth === 1) walk(it.item, 2, domain, it.name, it.name);
      else walk(it.item, depth + 1, domain, svcFull, it.name);
    } else if (it.request) {
      const r = it.request;
      const headers = (r.header || [])
        .filter((h) => !h.disabled)
        .map((h) => ({ key: h.key, value: h.value }));
      let bodyJ = '';
      if (r.body) {
        if (r.body.mode === 'raw') {
          bodyJ = JSON.stringify(r.body.raw);
        } else {
          bodyJ = JSON.stringify({ mode: r.body.mode, formdata: r.body.formdata || [] });
        }
      }
      const queryJ = r.url && r.url.query ? JSON.stringify(r.url.query) : '';
      const rawUrl = (r.url && r.url.raw) || '';
      rows.push([
        domain, svcShort(svcFull), svcFull, moduleName || '', it.name || '',
        r.method || 'GET', rawUrl, JSON.stringify(headers), bodyJ, queryJ,
      ].join('\x1f'));
    }
  }
}

walk(collection.item, 0, '', '', '');

fs.writeFileSync(tsvPath, rows.join('\n') + '\n');

// ---- 统计输出（供人工/文档对账，禁止脚本侧硬编码 1000） ----
const method = {};
const domain = {};
const svcEntry = {};   // 域/服务条目分布（与调研口径一致：core 在多个域分别计数）
const svcGlobal = {};  // 服务短名全局聚合
for (const line of rows) {
  const f = line.split('\t');
  method[f[5]] = (method[f[5]] || 0) + 1;
  domain[f[0]] = (domain[f[0]] || 0) + 1;
  const key = `${f[0]}/${f[1]}`;
  svcEntry[key] = (svcEntry[key] || 0) + 1;
  svcGlobal[f[1]] = (svcGlobal[f[1]] || 0) + 1;
}
const out = [`total=${rows.length}`];
out.push('--- method ---');
for (const k of Object.keys(method).sort()) out.push(`method:${k}=${method[k]}`);
out.push('--- domain ---');
for (const k of Object.keys(domain)) out.push(`domain:${k}=${domain[k]}`);
out.push('--- domain/service ---');
for (const k of Object.keys(svcEntry)) out.push(`domainService:${k}=${svcEntry[k]}`);
out.push('--- service global ---');
for (const k of Object.keys(svcGlobal).sort()) out.push(`service:${k}=${svcGlobal[k]}`);
fs.writeFileSync(statsPath, out.join('\n') + '\n');
console.log(`展平完成: total=${rows.length}（写入 ${tsvPath}）`);
