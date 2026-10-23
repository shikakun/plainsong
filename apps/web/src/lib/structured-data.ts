import { landingContent } from './landing';
import {
  type Locale,
  locales,
  MAC_APP_STORE_STOREFRONTS,
  macAppStoreUrl,
  SITE_NAME,
  SITE_URL,
} from './site';

export type JsonLdNode = Record<string, unknown>;

export const PERSON_ID = `${SITE_URL}/#person`;

export const WEBSITE_ID = `${SITE_URL}/#website`;

export const APP_ID = `${SITE_URL}/#app`;

export function absoluteUrl(path: string): string {
  return new URL(path, SITE_URL).href;
}

export function nodeId(pageUrl: string, name: string): string {
  return `${pageUrl}#${name}`;
}

export function siteNodes(): JsonLdNode[] {
  return [
    {
      '@type': 'Person',
      '@id': PERSON_ID,
      name: 'shikakun',
      url: 'https://shikakun.com',
    },
    {
      '@type': 'WebSite',
      '@id': WEBSITE_ID,
      url: absoluteUrl('/'),
      name: SITE_NAME,
      inLanguage: [...locales],
      publisher: { '@id': PERSON_ID },
    },
    {
      '@type': 'SoftwareApplication',
      '@id': APP_ID,
      name: SITE_NAME,
      url: absoluteUrl('/'),
    },
  ];
}

export function appNode(locale: Locale, description: string): JsonLdNode {
  const content = landingContent[locale];
  const storeUrl = macAppStoreUrl(locale);
  return {
    '@type': 'SoftwareApplication',
    '@id': APP_ID,
    name: SITE_NAME,
    description,
    applicationCategory: 'UtilitiesApplication',
    operatingSystem: 'macOS 26.0 or later',
    url: absoluteUrl('/'),
    downloadUrl: storeUrl,
    installUrl: storeUrl,
    sameAs: locales.map((code) => macAppStoreUrl(code)),
    inLanguage: [...locales],
    offers: locales.map((code) => ({
      '@type': 'Offer',
      price: 0,
      priceCurrency: code === 'ja' ? 'JPY' : 'USD',
      availability: 'https://schema.org/InStock',
      url: macAppStoreUrl(code),
      eligibleRegion: MAC_APP_STORE_STOREFRONTS[code].toUpperCase(),
    })),
    featureList: content.features.map((feature) => feature.title),
    screenshot: content.features.map((feature) => absoluteUrl(feature.image.src)),
    author: { '@id': PERSON_ID },
    publisher: { '@id': PERSON_ID },
  };
}

export function documentPageType(slug: string): string | undefined {
  return slug === 'contact' ? 'ContactPage' : undefined;
}

export interface WebPageInput {
  type?: string;
  url: string;
  name: string;
  description: string;
  locale: Locale;
  image?: string;
  mainEntityId?: string;
}

export function webPageNode(input: WebPageInput): JsonLdNode {
  return {
    '@type': input.type ?? 'WebPage',
    '@id': nodeId(input.url, 'webpage'),
    url: input.url,
    name: input.name,
    description: input.description,
    inLanguage: input.locale,
    isPartOf: { '@id': WEBSITE_ID },
    about: { '@id': APP_ID },
    publisher: { '@id': PERSON_ID },
    ...(input.image ? { primaryImageOfPage: { '@type': 'ImageObject', url: input.image } } : {}),
    ...(input.mainEntityId ? { mainEntity: { '@id': input.mainEntityId } } : {}),
  };
}

export function pageGraph(webPage: JsonLdNode, nodes: readonly JsonLdNode[]): JsonLdNode {
  const all = [...siteNodes(), webPage, ...nodes];

  const byId = new Map<string, JsonLdNode>();
  for (const node of all) {
    const id = node['@id'];
    if (typeof id !== 'string') {
      throw new Error('JSON-LDのノードには@idが必要です');
    }
    byId.set(id, node);
  }

  return { '@context': 'https://schema.org', '@graph': [...byId.values()] };
}

/** 内容が`</script>`を含んでも要素が閉じないよう、`<`をエスケープする */
export function serializeJsonLd(value: unknown): string {
  return JSON.stringify(value).replace(/</g, '\\u003c');
}
