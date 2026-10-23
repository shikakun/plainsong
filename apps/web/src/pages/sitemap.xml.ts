import type { APIRoute } from 'astro';
import { escapeXml, sitemapEntries, xmlResponse } from '@/lib/sitemap';

export const GET: APIRoute = async () => {
  const entries = await sitemapEntries();

  const body = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">',
    ...entries.map((entry) =>
      [
        '  <url>',
        `    <loc>${escapeXml(entry.url)}</loc>`,
        ...entry.alternates.map(
          (alternate) =>
            `    <xhtml:link rel="alternate" hreflang="${alternate.hreflang}" href="${escapeXml(alternate.url)}" />`,
        ),
        '  </url>',
      ].join('\n'),
    ),
    '</urlset>',
    '',
  ].join('\n');

  return xmlResponse(body);
};
