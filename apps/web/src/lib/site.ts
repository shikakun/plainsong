export const SITE_URL = 'https://plainsong.shikakun.com';
export const SITE_NAME = 'Plainsong';
export const LOCALE_STORAGE_KEY = 'plainsong.locale';

export const locales = ['ja', 'en'] as const;
export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = 'ja';

export const MAC_APP_STORE_APP_ID = '6823806442';

export const MAC_APP_STORE_STOREFRONTS = {
  ja: 'jp',
  en: 'us',
} as const satisfies Record<Locale, string>;

export function macAppStoreUrl(locale: Locale): string {
  const storefront = MAC_APP_STORE_STOREFRONTS[locale];
  return `https://apps.apple.com/${storefront}/app/id${MAC_APP_STORE_APP_ID}`;
}

export const SOURCE_CODE_URL = 'https://github.com/shikakun/plainsong';

export const localeLabels: Record<Locale, string> = {
  ja: '日本語',
  en: 'English',
};

export const navLabels: Record<
  Locale,
  {
    home: string;
    features: string;
    sourceCode: string;
    download: string;
    terms: string;
    privacy: string;
    contact: string;
  }
> = {
  ja: {
    home: 'ホーム',
    features: '機能紹介',
    sourceCode: 'ソースコード',
    download: 'ダウンロード',
    terms: '利用規約',
    privacy: 'プライバシーポリシー',
    contact: 'お問い合わせ',
  },
  en: {
    home: 'Home',
    features: 'Features',
    sourceCode: 'Source Code',
    download: 'Download',
    terms: 'Terms of Service',
    privacy: 'Privacy Policy',
    contact: 'Contact',
  },
};

export type HeaderNavItem =
  | {
      kind: 'internal';
      slug: string;
      labelKey: 'features';
      drawerOnly?: boolean;
    }
  | {
      kind: 'external';
      labelKey: 'sourceCode' | 'download';
      id: 'sourceCode' | 'download';
    };

export const headerNavItems: readonly HeaderNavItem[] = [
  { kind: 'internal', slug: '', labelKey: 'features', drawerOnly: true },
  { kind: 'external', labelKey: 'download', id: 'download' },
  { kind: 'external', labelKey: 'sourceCode', id: 'sourceCode' },
];

export function isCurrentNavSlug(navSlug: string, pageSlug: string): boolean {
  if (navSlug === '') {
    return pageSlug === '';
  }
  return pageSlug === navSlug || pageSlug.startsWith(`${navSlug}/`);
}

export function headerNavExternalHref(
  item: Extract<HeaderNavItem, { kind: 'external' }>,
  locale: Locale,
): string {
  switch (item.id) {
    case 'sourceCode':
      return SOURCE_CODE_URL;
    case 'download':
      return macAppStoreUrl(locale);
  }
}

export const footerNavItems = [
  { slug: 'terms', labelKey: 'terms' as const },
  { slug: 'privacy-policy', labelKey: 'privacy' as const },
  { slug: 'contact', labelKey: 'contact' as const },
] as const;

export const noindexSlugs = ['terms', 'privacy-policy'] as const;

export function isNoindexSlug(slug: string): boolean {
  return (noindexSlugs as readonly string[]).includes(slug);
}
