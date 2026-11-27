#!/usr/bin/env node
/**
 * vars-build.js — 装载变量表 vars.json
 *
 * 用法: 各输入经环境变量传入，输出写入 $VARS_FILE
 *   ASDM_BASE_URL          网关域名（13 个 {{xxxBaseUrl}} 缺省收敛目标）
 *   SERVICE_BASE_URL_*     逐服务覆盖（CORE/SSO/INTEGRATION/ADS_ADAPTER/GITLAB_ADAPTER/
 *                          AGENTORBIT/MCP_HOSTING/TELEMETRY/FILE_SERVICE/CODEARTS_ADAPTER/
 *                          ORG_MAPPING/PORTAL_BACKEND/AUTOMATION_ADAPTER）
 *   ASDM_PAT / TOKEN / OPEN_ACCESS_TOKEN / CITIC_SECRET
 *   INTERNAL_TOKEN_CORE / INTERNAL_TOKEN_AGENTORBIT / INTERNAL_TOKEN_TELEMETRY
 *   PARAMS_FILE            config/params.json 路径
 *   VARS_FILE              输出目标路径
 *
 * 输出结构:
 *   {
 *     base:     { coreBaseUrl: "https://...", ... 13 个 },
 *     creds:    { token, pat, internalToken: {core,agentorbit,telemetry},
 *                 openAccessToken, citicSecret },
 *     captured: { },                       // L1/L2 上下文捕获（Phase 2 扩充）
 *     params:   { ...common 段 + 各域段扁平展开 }
 *   }
 */
'use strict';
const fs = require('fs');

const env = process.env;
const VARS_FILE = env.VARS_FILE;
const PARAMS_FILE = env.PARAMS_FILE;
if (!VARS_FILE) {
  console.error('VARS_FILE 未设置');
  process.exit(2);
}

function clean(v) {
  return v && String(v).trim() ? String(v).replace(/\/+$/, '') : '';
}

const gateway = clean(env.ASDM_BASE_URL);

// 13 个服务 baseUrl 变量 → env.sh SERVICE_BASE_URL_* 覆盖键
const SVC_MAP = {
  coreBaseUrl: 'CORE',
  ssoBaseUrl: 'SSO',
  integrationBaseUrl: 'INTEGRATION',
  adsAdapterBaseUrl: 'ADS_ADAPTER',
  gitlabAdapterBaseUrl: 'GITLAB_ADAPTER',
  agentorbitBaseUrl: 'AGENTORBIT',
  mcpHostingBaseUrl: 'MCP_HOSTING',
  telemetryBaseUrl: 'TELEMETRY',
  fileServiceBaseUrl: 'FILE_SERVICE',
  codeartsAdapterBaseUrl: 'CODEARTS_ADAPTER',
  orgMappingBaseUrl: 'ORG_MAPPING',
  portalBackendBaseUrl: 'PORTAL_BACKEND',
  automationAdapterBaseUrl: 'AUTOMATION_ADAPTER',
};

// baseUrl 收敛（admin-G4）：缺省全部收敛为网关域名；SERVICE_BASE_URL_* 逐服务覆盖
const base = {};
for (const [varName, svcKey] of Object.entries(SVC_MAP)) {
  const override = clean(env[`SERVICE_BASE_URL_${svcKey}`]);
  base[varName] = override || gateway;
}

const creds = {
  token: env.TOKEN || '',
  pat: env.ASDM_PAT || '',
  internalToken: {
    core: env.INTERNAL_TOKEN_CORE || '',
    agentorbit: env.INTERNAL_TOKEN_AGENTORBIT || '',
    telemetry: env.INTERNAL_TOKEN_TELEMETRY || '',
  },
  openAccessToken: env.OPEN_ACCESS_TOKEN || '',
  citicSecret: env.CITIC_SECRET || '',
};

// 业务参数扁平装载：common 段优先，域段键直接展开（键冲突时 common 优先）
const params = {};
try {
  if (PARAMS_FILE && fs.existsSync(PARAMS_FILE)) {
    const p = JSON.parse(fs.readFileSync(PARAMS_FILE, 'utf8'));
    for (const [dn, cfg] of Object.entries(p.domains || {})) {
      if (cfg && typeof cfg === 'object') {
        for (const [k, v] of Object.entries(cfg)) {
          if (!(k in params)) params[k] = v;
        }
      }
    }
    for (const [k, v] of Object.entries(p.common || {})) params[k] = v;
  }
} catch (e) {
  console.error(`params.json 解析失败: ${e.message}`);
  process.exit(2);
}

const vars = { base, creds, captured: {}, params };
fs.writeFileSync(VARS_FILE, JSON.stringify(vars, null, 1));
