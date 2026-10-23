import type { APIRoute } from 'astro';
import { SITE_URL } from '@/lib/site';
import { escapeXml, xmlResponse } from '@/lib/sitemap';

export const GET: APIRoute = () => {
  const body = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    '  <sitemap>',
    `    <loc>${escapeXml(new URL('/sitemap.xml', SITE_URL).href)}</loc>`,
    '  </sitemap>',
    '</sitemapindex>',
    '',
  ].join('\n');

  return xmlResponse(body);
};
