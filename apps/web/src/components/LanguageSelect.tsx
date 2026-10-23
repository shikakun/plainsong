import { useId } from 'react';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { pagePath } from '@/lib/i18n';
import { LOCALE_STORAGE_KEY, type Locale } from '@/lib/site';

function resolvePath(locale: Locale, slug: string, hasAlternate: boolean): string {
  if (locale === 'en' && !hasAlternate) {
    return pagePath('ja', slug);
  }
  return pagePath(locale, slug);
}

export interface LanguageSelectProps {
  locale: Locale;
  slug: string;
  hasAlternate: boolean;
  label: string;
  options: ReadonlyArray<{ value: Locale; label: string }>;
}

export function LanguageSelect({
  locale,
  slug,
  hasAlternate,
  label,
  options,
}: LanguageSelectProps) {
  const id = useId();
  const selectedLabel = options.find((option) => option.value === locale)?.label ?? locale;

  return (
    <div className="flex items-center gap-2">
      <label htmlFor={id} className="sr-only">
        {label}
      </label>
      <Select
        value={locale}
        onValueChange={(next) => {
          if (next !== 'ja' && next !== 'en') {
            return;
          }
          window.localStorage.setItem(LOCALE_STORAGE_KEY, next);
          window.location.assign(resolvePath(next, slug, hasAlternate));
        }}
      >
        <SelectTrigger id={id} size="sm" aria-label={label} className="min-w-28">
          <SelectValue>
            {(value) => options.find((option) => option.value === value)?.label ?? selectedLabel}
          </SelectValue>
        </SelectTrigger>
        <SelectContent align="end">
          {options.map((option) => (
            <SelectItem key={option.value} value={option.value} lang={option.value}>
              {option.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}
