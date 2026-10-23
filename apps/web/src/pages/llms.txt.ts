import { getCollection } from 'astro:content';
import type { APIRoute } from 'astro';
import { pagePath, parsePageId } from '@/lib/i18n';
import { landingContent } from '@/lib/landing';
import { locales, macAppStoreUrl, SITE_URL, SOURCE_CODE_URL } from '@/lib/site';

const pageOrder = ['', 'contact', 'terms', 'privacy-policy'];

function orderIndex(slug: string): number {
  const index = pageOrder.indexOf(slug);
  return index === -1 ? pageOrder.length : index;
}

export const GET: APIRoute = async () => {
  const pages = await getCollection('pages');
  const enPages = pages
    .filter((page) => parsePageId(page.id).locale === 'en')
    .sort((a, b) => {
      const order = orderIndex(parsePageId(a.id).slug) - orderIndex(parsePageId(b.id).slug);
      return order !== 0 ? order : a.id.localeCompare(b.id);
    });
  const jaSlugs = new Set(
    pages.flatMap((page) => {
      const { locale, slug } = parsePageId(page.id);
      return locale === 'ja' ? [slug] : [];
    }),
  );
  const homeDescription = (locale: 'ja' | 'en') =>
    pages.find((page) => {
      const parsed = parsePageId(page.id);
      return parsed.locale === locale && parsed.slug === '';
    })?.data.description ?? '';
  const { download, features } = landingContent.en;

  const absolute = (locale: 'ja' | 'en', slug: string) =>
    new URL(pagePath(locale, slug), SITE_URL).href;
  const url = (path: string) => new URL(path, SITE_URL).href;
  const storeLinks = locales.map(
    (locale) =>
      `- [Mac App Store (${locale === 'ja' ? 'Japan' : 'United States'} storefront)](${macAppStoreUrl(locale)})`,
  );

  const lines = [
    '# Plainsong',
    '',
    `> ${homeDescription('en')} ${homeDescription('ja')}`,
    '',
    'The site is bilingual: Japanese pages at the root, English pages under /en/.',
    '',
    '## The app',
    '',
    `- ${download.requirement}. Distributed only through the Mac App Store.`,
    `- Price: ${download.pricing}. There are no in-app purchases or ads.`,
    '- Lives in the menu bar, so you can start writing the moment you want to.',
    '- Privacy: no account is required, and there is no analytics or tracking. The app does not communicate over the network; drafts, autosave backups, imported themes, and settings stay on your Mac.',
    '- Developed by shikakun (https://shikakun.com).',
    `- [Source code](${SOURCE_CODE_URL}): Licensed under the Apache License 2.0. Images such as the app icon are licensed under CC BY-NC-ND 4.0.`,
    ...storeLinks,
    '',
    '## Features',
    '',
    ...features.map((feature) => `- ${feature.title}: ${feature.body}`),
    '',
    '## Pages',
    '',
    ...enPages.map((page) => {
      const { slug } = parsePageId(page.id);
      const japanese = jaSlugs.has(slug) ? ` 日本語: ${absolute('ja', slug)}` : '';
      return `- [${page.data.title}](${absolute('en', slug)}): ${page.data.description}${japanese}`;
    }),
    '',
    '## Sitemap',
    '',
    `- [Sitemap](${url('/sitemap-index.xml')}): Every indexable page, with hreflang alternates`,
    '',
  ];

  return new Response(lines.join('\n'), {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
};
