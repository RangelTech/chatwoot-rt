#!/usr/bin/env node
/*
 * Copies the public provider metadata from the checked-out 9Router registry.
 * Usage:
 *   NINEROUTER_SOURCE=/absolute/path/to/9router node scripts/generate_provider_catalog.mjs
 *
 * Commit the resulting JSON with each intentional 9Router upgrade. Runtime
 * never imports 9Router and never exposes transport configuration or secrets.
 */
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { writeFile } from 'node:fs/promises';

const source = process.env.NINEROUTER_SOURCE;
if (!source) throw new Error('NINEROUTER_SOURCE deve apontar para o checkout do 9Router');

const registryUrl = pathToFileURL(resolve(source, 'open-sse/providers/registry/index.js')).href;
const { default: registry } = await import(registryUrl);
const safeText = value => (typeof value === 'string' ? value : undefined);
const publicProvider = provider => ({
  id: provider.id,
  name: safeText(provider.display?.name) || provider.id,
  category: provider.category,
  icon: safeText(provider.display?.icon) || 'cloud',
  color: safeText(provider.display?.color),
  website: safeText(provider.display?.website),
  api_key_url: safeText(provider.display?.notice?.apiKeyUrl),
  risk_notice: safeText(provider.display?.deprecationNotice),
  auth_modes: Array.isArray(provider.authModes) ? provider.authModes.filter(mode => typeof mode === 'string') : [],
  has_oauth: provider.hasOAuth === true,
  has_free: provider.hasFree === true,
  hidden: provider.hidden === true,
  models: Array.isArray(provider.models)
    ? provider.models.filter(model => typeof model?.id === 'string').map(model => ({ id: model.id, name: safeText(model.name) || model.id }))
    : [],
});

const providers = registry.filter(provider => provider?.id && !provider.hidden).map(publicProvider);
const payload = { source: '9router', generated_at: new Date().toISOString(), providers };
await writeFile(new URL('../app/javascript/dashboard/routes/dashboard/ragent/provider_catalog.json', import.meta.url), `${JSON.stringify(payload, null, 2)}\n`);
console.log(`provider catalog: ${providers.length} entries`);
