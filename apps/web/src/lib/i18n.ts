import type { Locale } from './site';
import { defaultLocale, locales, SITE_NAME } from './site';

export function parsePageId(id: string): { locale: Locale; slug: string } {
  if (id === '' || id === 'index') {
    return { locale: 'ja', slug: '' };
  }

  if ((locales as readonly string[]).includes(id)) {
    return { locale: id as Locale, slug: '' };
  }

  if (id.startsWith('en/')) {
    return { locale: 'en', slug: id.slice(3) };
  }

  return { locale: 'ja', slug: id };
}

export function alternatePageId(locale: Locale, slug: string): string {
  const other: Locale = locale === 'ja' ? 'en' : 'ja';
  if (other === 'ja') {
    return slug;
  }
  return slug ? `en/${slug}` : 'en';
}

export function pagePath(locale: Locale, slug: string): string {
  const segments: string[] = [];
  if (locale !== defaultLocale) {
    segments.push(locale);
  }
  if (slug) {
    segments.push(slug);
  }
  return segments.length === 0 ? '/' : `/${segments.join('/')}/`;
}

export function alternatePath(locale: Locale, slug: string): string {
  return pagePath(locale, slug);
}

export function pageTitle(title: string, slug: string, tagline?: string): string {
  if (slug === '') {
    return tagline ? `${SITE_NAME} — ${tagline}` : SITE_NAME;
  }
  return `${title} — ${SITE_NAME}`;
}

export function ogLocale(locale: Locale): string {
  return locale === 'ja' ? 'ja_JP' : 'en_US';
}

export function htmlLang(locale: Locale): string {
  return locale;
}
