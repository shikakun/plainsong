import { getCollection } from 'astro:content';
import { pagePath, parsePageId } from './i18n';
import { defaultLocale, isNoindexSlug, type Locale, SITE_URL } from './site';

export interface SitemapEntry {
  url: string;
  alternates: ReadonlyArray<{ hreflang: string; url: string }>;
}

export async function sitemapEntries(): Promise<SitemapEntry[]> {
  const pages = await getCollection('pages');

  const items = pages
    .map((entry) => parsePageId(entry.id))
    .filter((item) => !isNoindexSlug(item.slug));

  const published = new Set(items.map((item) => `${item.locale}:${item.slug}`));

  return items
    .map((item) => {
      const other: Locale = item.locale === 'ja' ? 'en' : 'ja';
      const hasAlternate = published.has(`${other}:${item.slug}`);
      return {
        url: new URL(pagePath(item.locale, item.slug), SITE_URL).href,
        alternates: hasAlternate
          ? [
              { hreflang: 'ja', url: new URL(pagePath('ja', item.slug), SITE_URL).href },
              { hreflang: 'en', url: new URL(pagePath('en', item.slug), SITE_URL).href },
              {
                hreflang: 'x-default',
                url: new URL(pagePath(defaultLocale, item.slug), SITE_URL).href,
              },
            ]
          : [],
      };
    })
    .sort((a, b) => a.url.localeCompare(b.url));
}

export function escapeXml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function xmlResponse(body: string): Response {
  return new Response(body, {
    headers: { 'Content-Type': 'application/xml; charset=utf-8' },
  });
}
